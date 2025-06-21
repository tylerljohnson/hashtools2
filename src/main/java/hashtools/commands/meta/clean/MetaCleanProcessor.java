package hashtools.commands.meta.clean;

import hashtools.commands.*;
import hashtools.models.*;
import hashtools.utils.*;
import org.apache.tika.*;

import java.io.*;
import java.nio.file.*;
import java.nio.file.attribute.*;
import java.time.*;
import java.time.format.*;
import java.util.*;

public class MetaCleanProcessor implements Processor {
    private static final String TIMESTAMP_PATTERN = "yyyy-MM-dd'T'HH:mm:ss";
    private static final DateTimeFormatter fmt =
            DateTimeFormatter.ofPattern(TIMESTAMP_PATTERN);

    private final File[] metaFiles;
    private final boolean dryRun;
    private final boolean verbose;
    private final boolean fullCheck;
    private final boolean noProgress;
    private static final Tika tika = new Tika();

    // Shared cache across all meta files
    private final Map<String, Boolean> basePathCache = new HashMap<>();

    public MetaCleanProcessor(File[] metaFiles,
                              boolean dryRun,
                              boolean verbose,
                              boolean fullCheck,
                              boolean noProgress) {
        this.metaFiles   = metaFiles;
        this.dryRun      = dryRun;
        this.verbose     = verbose;
        this.fullCheck   = fullCheck;
        this.noProgress  = noProgress;
    }

    @Override
    public void run() {
        for (File metaFile : metaFiles) {
            List<MetaItem> items = MetaFileUtils.readMetaFile(metaFile);
            List<MetaItem> kept  = new ArrayList<>();
            List<String>   removalReasons = new ArrayList<>();

            // 1) Verify all basePaths up front, using shared cache
            for (MetaItem it : items) {
                String basePath = it.basePath();
                Boolean ok = basePathCache.get(basePath);
                if (ok == null) {
                    Path base = Paths.get(basePath);
                    ok = Files.exists(base) && Files.isDirectory(base);
                    basePathCache.put(basePath, ok);
                }
                if (!ok) {
                    throw new RuntimeException(String.format(
                            "In %s: basePath '%s' for entry '%s' does not exist or is not a directory",
                            metaFile.getName(), it.basePath(), it.filePath()
                    ));
                }
            }

            // 2) Choose appropriate progress bar
            ProgressBar progress = noProgress
                    ? new NoOpProgressBar()
                    : new SimpleProgressBar(items.size());

            // 3) Process each entry
            for (MetaItem it : items) {
                progress.step();
                progress.render();

                Path path = Paths.get(it.basePath(), it.filePath());
                String reason = !fullCheck
                        ? (Files.isRegularFile(path) ? null : "file missing")
                        : checkItemDeep(it, path);

                if (reason == null) {
                    kept.add(it);
                    if (verbose) System.out.printf("%nKEEP   : %s%n", path);
                } else {
                    removalReasons.add(it.filePath() + " (" + reason + ")");
                    if (verbose) System.out.printf("%nREMOVE : %s  reason=%s%n", path, reason);
                }
            }
            progress.finish();

            // 4) Summary
            System.out.printf("%n=== %s ===%n", metaFile.getName());
            System.out.printf("Examined : %d entries%n", items.size());
            System.out.printf("Kept     : %d entries%n", kept.size());
            System.out.printf("Removed  : %d entries%n", removalReasons.size());

            // 5) Backup & write if needed
            if (!dryRun && !removalReasons.isEmpty()) {
                persistCleanedMeta(metaFile, kept);
            } else if (dryRun) {
                System.out.println("Dry run; no changes written.");
            }
            System.out.println();
        }
    }

    private void persistCleanedMeta(File metaFile, List<MetaItem> kept) {
        try {
            Path backup = MetaFileUtils.backupMetaFile(metaFile.toPath());
            System.out.printf("Backup   : %s%n", backup.getFileName());
            MetaFileUtils.writeMetaFile(metaFile.toPath(), kept);
            System.out.printf("Written  : %d entries%n", kept.size());
        } catch (IOException e) {
            throw new RuntimeException(
                    "Failed to persist cleaned meta for " + metaFile.getName(), e
            );
        }
    }

    private String checkItemDeep(MetaItem it, Path path) {
        if (!Files.exists(path) || !Files.isRegularFile(path)) {
            return "file missing";
        }
        try {
            long actualSize = Files.size(path);
            if (actualSize != it.fileSize()) {
                return String.format("size mismatch (meta=%d,disk=%d)",
                        it.fileSize(), actualSize);
            }
            FileTime ft = Files.getLastModifiedTime(path);
            String actualTs = LocalDateTime.ofInstant(ft.toInstant(),
                    ZoneId.systemDefault()).format(fmt);
            if (!actualTs.equals(it.lastModified())) {
                return String.format("timestamp mismatch (meta=%s,disk=%s)",
                        it.lastModified(), actualTs);
            }
            String actualMime = tika.detect(path);
            if (!actualMime.equals(it.mimeType())) {
                return String.format("mime mismatch (meta=%s,disk=%s)",
                        it.mimeType(), actualMime);
            }
        } catch (IOException e) {
            return "I/O error: " + e.getMessage();
        }
        return null;
    }

    private interface ProgressBar {
        void step();
        void render();
        default void finish() { /* e.g. newline if needed */ }
    }

    private class NoOpProgressBar implements ProgressBar {
        @Override public void step()   { }
        @Override public void render() { }
    }

    private class SimpleProgressBar implements ProgressBar {
        private final int total;
        private final int width;
        private int done;

        SimpleProgressBar(int total) {
            this.total = total;
            this.done  = 0;
            int cols = 80;
            String env = System.getenv("COLUMNS");
            if (env != null) {
                try { cols = Integer.parseInt(env); } catch (NumberFormatException ignored) {}
            }
            this.width = Math.max(10, (int)(cols * 0.75));
        }

        @Override
        public void step() {
            done++;
        }

        @Override
        public void render() {
            double pct = (double) done / total;
            int filled = (int) Math.round(pct * width);
            StringBuilder bar = new StringBuilder(width);
            for (int i = 0; i < filled; i++)   bar.append('#');
            for (int i = filled; i < width; i++) bar.append(' ');
            int percent = (int) Math.round(pct * 100);
            System.out.printf("\r[%s] %3d%%", bar, percent);
            System.out.flush();
        }

        @Override
        public void finish() {
            System.out.println();
        }
    }
}
