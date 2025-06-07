package hashtools.processors;

import hashtools.models.*;
import hashtools.utils.*;
import org.apache.tika.*;

import java.io.*;
import java.nio.file.*;
import java.nio.file.attribute.*;
import java.time.*;
import java.time.format.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;

public class GenerateMetaProcessor implements Processor {
    public static final int DEFAULT_QUEUE_SIZE   = 10_000;
    public static final int DEFAULT_BATCH_SIZE   =    500;
    private static final long   PROGRESS_INTERVAL_MS = 1_000;
    private static final double MS_PER_SECOND        = 1_000.0;
    private static final String TIMESTAMP_PATTERN    = "yyyy-MM-dd'T'HH:mm:ss";
    private static final DateTimeFormatter TIMESTAMP_FORMAT = DateTimeFormatter.ofPattern(TIMESTAMP_PATTERN);

    private static final String ANSI_CARRIAGE_RETURN = "\r";
    private static final String ANSI_ERASE_LINE      = "\u001B[2K";

    private static final String STARTUP_FORMAT  = "Starting with %d threads, queue=%d, batch=%d.%n";
    private static final String PROGRESS_FORMAT = "Generating: %,d/%,d (%s) at %.2f f/s, ETA %s";
    private static final String DONE_FORMAT     = "\rDone. elapsed  %s, hashed %,d, skipped %,d, processed %.2f files/sec%n";

    private static final MetaItem POISON_PILL = new MetaItem("", "", 0, "", "", "");
    public static final String META_EXTENSION = ".meta";

    private final Config config;
    private BlockingQueue<MetaItem> queue;
    private ExecutorService hashingExecutor;
    private ExecutorService writerExecutor;
    private ScheduledExecutorService progressExecutor;
    private AtomicInteger discoveredCount;
    private AtomicInteger processedCount;
    private AtomicInteger skippedCount;
    private long startTime;
    private Tika tika;

    public GenerateMetaProcessor(
            File rootDir,
            String outputFilePath,
            int threadCount,
            int queueSize,
            int batchSize,
            boolean silent,
            Set<String> includeTypeFilter
    ) {
        boolean toStdout = "-".equals(outputFilePath);
        Path outputFile = (!toStdout && outputFilePath != null) ? Path.of(outputFilePath) : null;
        this.config = new Config(
                rootDir.toPath(),
                outputFile,
                toStdout,
                threadCount,
                queueSize,
                batchSize,
                silent || toStdout,
                includeTypeFilter
        );
    }

    @Override
    public void run() {
        validateAndPrepare();
        initState();
        if (!config.silent) printStartupSummary();

        queue = new LinkedBlockingQueue<>(config.queueSize);
        hashingExecutor  = Executors.newFixedThreadPool(config.threadCount);
        writerExecutor   = Executors.newSingleThreadExecutor();
        progressExecutor = Executors.newSingleThreadScheduledExecutor();

        try (BufferedWriter writer = config.toStdout
                ? new BufferedWriter(new OutputStreamWriter(System.out))
                : Files.newBufferedWriter(config.outputFile)) {

            startWriter(writer);
            if (!config.silent && !config.toStdout) startProgressReporter();

            Files.walkFileTree(config.rootDir, new SimpleFileVisitor<>() {
                @Override
                public FileVisitResult visitFile(Path file, BasicFileAttributes attrs) {
                    if (attrs.isRegularFile()) {
                        String mimeType = detectMimeType(file);
                        String type = mimeType.split("/")[0];
                        if (config.includeMimeTypesFilters.isEmpty() || config.includeMimeTypesFilters.contains(type)) {
                            discoveredCount.incrementAndGet();
                            hashingExecutor.submit(() -> processFile(file, attrs));
                        } else {
                            skippedCount.incrementAndGet();
                        }
                    }
                    return FileVisitResult.CONTINUE;
                }
            });

            hashingExecutor.shutdown();
            hashingExecutor.awaitTermination(Long.MAX_VALUE, TimeUnit.NANOSECONDS);

            queue.put(POISON_PILL);

            writerExecutor.shutdown();
            writerExecutor.awaitTermination(Long.MAX_VALUE, TimeUnit.NANOSECONDS);

            progressExecutor.shutdownNow();

            if (!config.silent) printCompletionSummary();

        } catch (IOException | InterruptedException e) {
            System.err.printf("ERROR: %s%n", e.getMessage());
            Thread.currentThread().interrupt();
            System.exit(1);
        }
    }

    private void validateAndPrepare() {
        if (!Files.isDirectory(config.rootDir)) {
            System.err.printf("ERROR: %s is not a directory.%n", config.rootDir);
            System.exit(1);
        }
        if (config.outputFile == null && !config.toStdout) {
            config.outputFile = defaultOutputPath();
        }
    }

    private String detectMimeType(Path file) {
        try {
            String full = tika.detect(file);
            return full != null ? full.split(";")[0].trim() : "application/octet-stream";
        } catch (IOException e) {
            System.err.printf("ERROR detecting MIME type for %s: %s%n", file, e.getMessage());
            return "application/octet-stream";
        }
    }

    private void initState() {
        startTime       = System.currentTimeMillis();
        tika            = new Tika();
        discoveredCount = new AtomicInteger(0);
        processedCount  = new AtomicInteger(0);
        skippedCount    = new AtomicInteger(0);
    }

    private void printStartupSummary() {
        System.out.printf(STARTUP_FORMAT, config.threadCount, config.queueSize, config.batchSize);
        if (!config.toStdout && config.outputFile != null) {
            System.out.printf("Output file: %s%n", config.outputFile);
        }
    }

    private void startWriter(BufferedWriter writer) {
        writerExecutor.submit(() -> {
            try {
                List<String> batch = new ArrayList<>(config.batchSize);
                while (true) {
                    MetaItem r = queue.take();
                    if (r == POISON_PILL) break;
                    batch.add(MetaFileUtils.toTsvString(r) + System.lineSeparator());
                    if (batch.size() >= config.batchSize) {
                        flushBatch(writer, batch);
                    }
                    processedCount.incrementAndGet();
                }
                flushBatch(writer, batch);
                writer.flush();
            } catch (Exception e) {
                System.err.printf("ERROR writing results: %s%n", e.getMessage());
            }
        });
    }

    private void startProgressReporter() {
        progressExecutor.scheduleAtFixedRate(() -> {
            long elapsed = System.currentTimeMillis() - startTime;
            int d = discoveredCount.get(), p = processedCount.get();
            double rate = elapsed>0 ? p * MS_PER_SECOND/elapsed : 0;
            double pct  = d>0 ? 100.0 * p/d : 0;
            String pctFmt = d>0 ? String.format("%%.%df%%%%", Math.max(0, (int) Math.ceil(-Math.log10(100.0/d)))) : "%.0f%%";
            String pctStr = String.format(pctFmt, pct);
            long rem = d - p;
            long etaMs = rate>0 ? (long)(rem*MS_PER_SECOND/rate) : 0;
            String eta  = formatHMS(etaMs);
            String line = String.format(PROGRESS_FORMAT, p, d, pctStr, rate, eta);
            System.out.print(ANSI_CARRIAGE_RETURN + ANSI_ERASE_LINE + line);
            System.out.flush();
        }, 0, PROGRESS_INTERVAL_MS, TimeUnit.MILLISECONDS);
    }

    private void processFile(Path file, BasicFileAttributes attrs) {
        try {
            String mimeType = detectMimeType(file);
            String hash = DigestUtils.hash(file);
            String lastModified = LocalDateTime.ofInstant(attrs.lastModifiedTime().toInstant(), ZoneId.systemDefault()).format(TIMESTAMP_FORMAT);
            long sizeBytes = attrs.size();
            String basePath = config.rootDir.toAbsolutePath().toString();
            String relativePath = config.rootDir.relativize(file).toString();
            queue.put(new MetaItem(hash, lastModified, sizeBytes, mimeType, basePath, relativePath));
        } catch (Exception e) {
            System.err.printf("ERROR processing %s: %s%n", file, e.getMessage());
        }
    }

    private void flushBatch(BufferedWriter w, List<String> batch) throws IOException {
        for (String l : batch) w.write(l);
        w.flush(); batch.clear();
    }

    private void printCompletionSummary() {
        long totalMs = System.currentTimeMillis() - startTime;
        int total    = processedCount.get();
        double avg   = totalMs>0 ? total * MS_PER_SECOND/totalMs : 0;
        System.out.printf(DONE_FORMAT, formatHMS(totalMs), total, skippedCount.get(), avg);
    }

    private static Path defaultOutputPath() {
        return Path.of(LocalDateTime.now().format(TIMESTAMP_FORMAT) + META_EXTENSION);
    }

    private String formatHMS(long ms) {
        long s = ms/1000;
        return String.format("%d:%02d:%02d", s/3600, (s%3600)/60, s%60);
    }

    private static class Config {
        Path rootDir;
        Path outputFile;
        boolean toStdout;
        int threadCount; int queueSize; int batchSize;
        boolean silent;
        Set<String> includeMimeTypesFilters;

        Config(Path rootDir, Path outputFile, boolean toStdout,
               int threadCount, int queueSize,
               int batchSize, boolean silent, Set<String> includeFilters) {
            this.rootDir = rootDir;
            this.outputFile = outputFile;
            this.toStdout = toStdout;
            this.threadCount = threadCount;
            this.queueSize = queueSize;
            this.batchSize = batchSize;
            this.silent = silent;
            this.includeMimeTypesFilters = includeFilters != null ? includeFilters : Collections.emptySet();
        }

        static Config cwd() {
            return new Config(null, Path.of("."), false, 0,0,0,false, Collections.emptySet());
        }
    }
}
