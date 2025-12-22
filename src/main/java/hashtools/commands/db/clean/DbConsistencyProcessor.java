package hashtools.commands.db.clean;

import hashtools.commands.Processor;

import java.io.*;
import java.nio.file.*;
import java.sql.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.stream.*;

/**
 * Java 21+ Optimized Consistency Checker for large-scale file tracking (5m+ rows).
 * DESIGN PRINCIPLES:
 * 1. Spindle-Aware Parallelism: Runs one thread per physical HDD (base_path) to maximize linear I/O.
 * 2. Streaming DB Fetch: Uses Postgres cursors to maintain a tiny memory footprint.
 * 3. Linux Optimization: Uses lstat (NOFOLLOW_LINKS) for faster metadata checks on ext4.
 * 4. Observability: Provides a real-time, column-formatted dashboard.
 */
public final class DbConsistencyProcessor implements Processor {

    // --- Database Configuration ---
    private static final String DB_URL  = "jdbc:postgresql://cooper:5432/tyler";
    private static final String DB_USER = "tyler";
    private static final String DB_PASS = "tyler";

    // --- Performance & Tuning Constants ---
    private static final int JDBC_FETCH_SIZE      = 10_000; // Rows per network trip from Postgres
    private static final int PROGRESS_INTERVAL_MS = 250;    // Refresh rate of console UI
    private static final int UI_COLUMN_WIDTH      = 25;     // Spacing for console columns
    private static final long MAX_RUNTIME_HOURS   = 12;     // Absolute cap on execution time

    // --- ANSI UI Controls ---
    private static final String ANSI_CARRIAGE_RETURN = "\r";
    private static final String ANSI_CLEAR_LINE      = "\033[K";

    // --- State Management ---
    private final Map<String, AtomicLong> progressMap = new ConcurrentHashMap<>();
    private final ScheduledExecutorService progressReporter = Executors.newSingleThreadScheduledExecutor();

    /**
     * Entry point for the consistency check process.
     */
    public void run() {
        System.out.println("Initializing DbConsistencyChecker...");

        try (var executor = Executors.newVirtualThreadPerTaskExecutor();
             Connection conn = DriverManager.getConnection(DB_URL, DB_USER, DB_PASS)) {

            List<String> basePaths = getUniqueBasePaths(conn);

            // Phase 1: Mount Validation
            // We verify all paths before starting to avoid false positives on unmounted drives.
            System.out.printf("Phase 1: Validating %d mount points...%n", basePaths.size());
            for (String pathStr : basePaths) {
                Path path = Path.of(pathStr);
                if (!Files.exists(path) || !Files.isDirectory(path)) {
                    System.err.printf("%nFATAL: Base path missing or unmounted: %s%n", pathStr);
                    System.exit(1);
                }
                progressMap.put(extractLastSegment(pathStr), new AtomicLong(0));
            }

            // Phase 2: Start UI
            startReporter();

            // Phase 3: Launch HDD-specific tasks
            System.out.println("Phase 2: Scanning filesystems (Parallel Spindles)...");
            for (String path : basePaths) {
                executor.execute(new CheckTask(path));
            }

            // Virtual Thread Executor close() handles awaitTermination automatically.
        } catch (Exception e) {
            System.err.println("\n[ERROR] Controller failure:");
            e.printStackTrace();
        } finally {
            cleanup();
        }
    }

    /**
     * Periodically updates the console with a formatted view of progress.
     */
    private void startReporter() {
        progressReporter.scheduleAtFixedRate(() -> {
            String status = progressMap.entrySet().stream()
                    .sorted(Map.Entry.comparingByKey())
                    .map(e -> String.format("%s: %,d", e.getKey(), e.getValue().get()))
                    .map(s -> String.format("%-" + UI_COLUMN_WIDTH + "s", s))
                    .collect(Collectors.joining(""));

            System.out.print(ANSI_CARRIAGE_RETURN + status + ANSI_CLEAR_LINE);
            System.out.flush();
        }, PROGRESS_INTERVAL_MS, PROGRESS_INTERVAL_MS, TimeUnit.MILLISECONDS);
    }

    private void cleanup() {
        progressReporter.shutdown();
        try {
            if (!progressReporter.awaitTermination(5, TimeUnit.SECONDS)) {
                progressReporter.shutdownNow();
            }
        } catch (InterruptedException ignored) {}
        System.out.println("\nConsistency check finished.");
    }

    /**
     * Determines the most readable name for a base_path (the folder name).
     */
    private static String extractLastSegment(String path) {
        if (path == null || path.isEmpty()) return "root";
        String normalized = path.endsWith("/") ? path.substring(0, path.length() - 1) : path;
        int lastSlash = normalized.lastIndexOf('/');
        String segment = (lastSlash == -1) ? normalized : normalized.substring(lastSlash + 1);
        return segment.replaceAll("[^a-zA-Z0-9._-]", "_");
    }

    private List<String> getUniqueBasePaths(Connection conn) throws SQLException {
        List<String> paths = new ArrayList<>();
        try (Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery("SELECT DISTINCT base_path FROM hashes")) {
            while (rs.next()) {
                paths.add(rs.getString("base_path"));
            }
        }
        return paths;
    }

    /**
     * Task to process all files on a specific physical HDD.
     */
    private final class CheckTask implements Runnable {
        private final String basePath;
        private final String segmentName;

        public CheckTask(String basePath) {
            this.basePath = basePath;
            this.segmentName = extractLastSegment(basePath);
        }

        @Override
        public void run() {
            Path tsvPath = Path.of("missing_rows_" + segmentName + ".tsv");
            AtomicLong counter = progressMap.get(segmentName);

            // FetchSize + AutoCommit(false) are the keys to cursor-based streaming in Postgres
            try (Connection conn = DriverManager.getConnection(DB_URL, DB_USER, DB_PASS);
                 BufferedWriter writer = new BufferedWriter(new FileWriter(tsvPath.toFile()))) {

                conn.setAutoCommit(false);
                String sql = "SELECT id, full_path FROM hashes WHERE base_path = ?";

                try (PreparedStatement pstmt = conn.prepareStatement(sql)) {
                    pstmt.setFetchSize(JDBC_FETCH_SIZE);
                    pstmt.setString(1, basePath);

                    try (ResultSet rs = pstmt.executeQuery()) {
                        while (rs.next()) {
                            long id = rs.getLong("id");
                            String fullPathStr = rs.getString("full_path");

                            // Check filesystem; NOFOLLOW_LINKS is faster on Linux ext4
                            if (!Files.exists(Path.of(fullPathStr), LinkOption.NOFOLLOW_LINKS)) {
                                writer.write(id + "\t" + fullPathStr + "\n");
                            }
                            counter.incrementAndGet();
                        }
                        writer.flush();
                    }
                }
            } catch (Exception e) {
                System.err.printf("%n[%s] Error during I/O loop: %s%n", segmentName, e.getMessage());
            }
        }
    }
}