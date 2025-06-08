package hashtools.utils;

import hashtools.models.*;

import java.io.*;
import java.nio.file.*;
import java.time.*;
import java.time.format.*;
import java.util.*;

public class MetaFileUtils {

    public static final int EXPECTED_META_PROPERTIES = 6;

    private MetaFileUtils() {}

    // Converts a FileItem to a TSV formatted string.
    public static String toTsvString(MetaItem r) {
        return String.join("\t",
                r.hash(),
                r.lastModified(),
                String.valueOf(r.fileSize()),
                r.mimeType(),
                r.basePath(),
                r.filePath());
    }

    // Parses a TSV formatted string into a FileItem.
    public static MetaItem fromTsvString(String line) {
        String[] parts = line.split("\t");
        if (parts.length != EXPECTED_META_PROPERTIES) {
            throw new IllegalArgumentException("Invalid TSV format: " + line);
        }
        return new MetaItem(parts[0], parts[1], Long.parseLong(parts[2]), parts[3], parts[4], parts[5]);
    }

    // Reads a meta file from the given path and returns a list of FileItem objects.
    public static List<MetaItem> readMetaFile(Path path) {
        return readMetaFile(path.toFile());
    }

    // Reads a meta file from the given file and returns a list of FileItem objects.
    public static List<MetaItem> readMetaFile(File file) {
        List<MetaItem> items = new ArrayList<>();

        if (!file.exists() || !file.isFile() || !file.canRead()) {
            throw new RuntimeException("Invalid meta file: " + file.getAbsolutePath());
        }

        try (BufferedReader reader = new BufferedReader(new FileReader(file))) {
            String line;
            while ((line = reader.readLine()) != null) {
                String[] parts = line.split("\t");
                if (parts.length != EXPECTED_META_PROPERTIES) {
                    throw new RuntimeException("Invalid meta file format: " + line);
                }
                MetaItem item = new MetaItem(parts[0], parts[1], Long.parseLong(parts[2]), parts[3], parts[4], parts[5]);
                items.add(item);
            }
        } catch (IOException e) {
            throw new RuntimeException("Error reading meta file: " + e.getMessage(), e);
        }
        return items;
    }

    private static final DateTimeFormatter TIMESTAMP_FORMAT = DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss");

    public static Path backupMetaFile(File file) throws IOException {
        if (file == null || !file.exists()) {
            throw new IllegalArgumentException("Cannot backup: file is null or does not exist.");
        }

        Path originalPath = file.toPath();
        String timestamp = LocalDateTime.now().format(TIMESTAMP_FORMAT);
        String backupName = originalPath.getFileName().toString() + "." + timestamp + ".bak";

        Path backupPath = originalPath.resolveSibling(backupName);
        return Files.copy(originalPath, backupPath, StandardCopyOption.COPY_ATTRIBUTES);
    }

    public static void writeMetaFile(Path outputPath, List<MetaItem> items) throws IOException {
        try (BufferedWriter writer = Files.newBufferedWriter(outputPath)) {
            for (MetaItem item : items) {
                writer.write(toTsvString(item));
                writer.newLine();
            }
        }
    }
}
