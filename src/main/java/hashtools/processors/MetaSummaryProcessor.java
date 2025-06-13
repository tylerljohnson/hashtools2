package hashtools.processors;

import java.io.*;
import java.nio.file.*;
import java.time.*;
import java.time.format.*;
import java.util.*;

public class MetaSummaryProcessor implements Processor {

    private record MetaStats(String hash, LocalDateTime timestamp, long size, String mime) {}

    private final List<File> metaFiles;
    public static boolean detail = false;

    private int total = 0;
    private long totalSize = 0;
    private final Set<String> uniqueHashes = new HashSet<>();
    private final Map<String, Integer> mimeCounts = new HashMap<>();
    private final Map<String, Integer> sizeBuckets = new LinkedHashMap<>(Map.of(
            "< 1KB", 0,
            "KB", 0,
            "MB", 0,
            "GB", 0,
            "TB", 0
    ));
    private LocalDateTime oldest = null;
    private LocalDateTime newest = null;

    public MetaSummaryProcessor(List<File> metaFiles) {
        this.metaFiles = metaFiles;
    }

    @Override
    public void run() {
        for (File file : metaFiles) {
            if (!file.exists() || !file.isFile()) {
                System.err.printf("ERROR: %s is not a valid file.%n", file);
                continue;
            }

            try (BufferedReader reader = Files.newBufferedReader(file.toPath())) {
                String line;
                int lineNumber = 0;
                while ((line = reader.readLine()) != null) {
                    lineNumber++;
                    parseLine(file, lineNumber, line);
                }
            } catch (IOException e) {
                printError(file.getName(), 0, e.getMessage());
            }
        }

        printSummary();
    }

    private void parseLine(File file, int lineNumber, String line) {
        String[] parts = line.split("\t", -1);
        if (parts.length != 6) return;

        total++;
        uniqueHashes.add(parts[0]);

        try {
            long size = Long.parseLong(parts[2]);
            totalSize += size;
            if (size < 1_000) sizeBuckets.computeIfPresent("< 1KB", (k, v) -> v + 1);
            else if (size < 1_000_000) sizeBuckets.computeIfPresent("KB", (k, v) -> v + 1);
            else if (size < 1_000_000_000) sizeBuckets.computeIfPresent("MB", (k, v) -> v + 1);
            else if (size < 1_000_000_000_000L) sizeBuckets.computeIfPresent("GB", (k, v) -> v + 1);
            else sizeBuckets.computeIfPresent("TB", (k, v) -> v + 1);
        } catch (NumberFormatException e) {
            printError(file.getName(), lineNumber, "Invalid size value");
        }

        String mime = parts[3];
        mimeCounts.put(mime, mimeCounts.getOrDefault(mime, 0) + 1);

        try {
            LocalDateTime ts = LocalDateTime.parse(parts[1]);
            if (oldest == null || ts.isBefore(oldest)) oldest = ts;
            if (newest == null || ts.isAfter(newest)) newest = ts;
        } catch (DateTimeParseException e) {
            printError(file.getName(), lineNumber, "Invalid timestamp");
        }
    }

    private void printSummary() {
        System.out.println("Meta Summary:");
        System.out.printf("  Total entries     : %,d%n", total);
        System.out.printf("  Unique hashes     : %,d%n", uniqueHashes.size());
        if (total > 0) {
            int duplicates = total - uniqueHashes.size();
            double percent = 100.0 * duplicates / total;
            System.out.printf("  Duplicated hashes : %,d (%.1f%%)%n", duplicates, percent);
        }
        System.out.printf("  Total size        : %.1f GB%n", totalSize / 1_000_000_000.0);
        if (oldest != null) System.out.printf("  Oldest timestamp  : %s%n", oldest);
        if (newest != null) System.out.printf("  Newest timestamp  : %s%n", newest);

        if (detail) {
            System.out.println("  MIME types (full list):");
            mimeCounts.entrySet().stream()
                    .sorted(Map.Entry.comparingByKey())
                    .forEach(e -> System.out.printf("    %-16s : %,d %s%n", e.getKey(), e.getValue(), e.getValue() == 1 ? "file" : "files"));
        } else {
            System.out.println("  MIME types (by major type):");
            Map<String, Integer> mimeCategories = new TreeMap<>();
            for (Map.Entry<String, Integer> entry : mimeCounts.entrySet()) {
                String full = entry.getKey();
                String category = full.contains("/") ? full.substring(0, full.indexOf('/')) : full;
                mimeCategories.put(category, mimeCategories.getOrDefault(category, 0) + entry.getValue());
            }
            for (Map.Entry<String, Integer> e : mimeCategories.entrySet()) {
                System.out.printf("    %-16s : %,d %s%n", e.getKey(), e.getValue(), e.getValue() == 1 ? "file" : "files");
            }
        }

        if (detail) {
            System.out.println("  Size distribution:");
            sizeBuckets.forEach((k, v) -> System.out.printf("    %-16s : %,d%n", k, v));
        }
    }

    private void printError(String file, int line, String message) {
        System.err.printf("ERROR : %s : line %d : %s%n", file, line, message);
    }

}
