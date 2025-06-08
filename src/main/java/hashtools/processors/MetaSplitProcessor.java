package hashtools.processors;

import java.io.*;
import java.nio.file.*;
import java.util.*;

public class MetaSplitProcessor implements Processor {

    private final File inputFile;
    private final File outDir;
    private final String prefix;
    private final Set<String> mimeFilter;
    private final boolean splitByMajorType;

    public MetaSplitProcessor(File inputFile, File outDir, String prefix, Set<String> mimeFilter, boolean splitByMajorType) {
        this.inputFile = inputFile;
        this.outDir = outDir;
        this.prefix = prefix != null ? prefix : stripExtension(inputFile.getName());
        this.mimeFilter = mimeFilter != null ? mimeFilter : Collections.emptySet();
        this.splitByMajorType = splitByMajorType;
    }

    @Override
    public void run() {
        if (!inputFile.exists() || !inputFile.isFile()) {
            System.err.printf("ERROR: %s is not a valid file.%n", inputFile);
            return;
        }

        if (!outDir.exists() && !outDir.mkdirs()) {
            System.err.printf("ERROR: Could not create output directory %s%n", outDir);
            return;
        }

        Map<String, BufferedWriter> writers = new HashMap<>();

        try (BufferedReader reader = Files.newBufferedReader(inputFile.toPath())) {
            String line;
            int lineNumber = 0;
            while ((line = reader.readLine()) != null) {
                lineNumber++;
                processLine(line, lineNumber, writers);
            }
        } catch (IOException | UncheckedIOException e) {
            System.err.printf("ERROR: %s%n", e.getMessage());
        } finally {
            try {
                closeAll(writers);
            } catch (IOException e) {
                System.err.printf("ERROR closing writers: %s%n", e.getMessage());
            }
        }
    }

    private void processLine(String line, int lineNumber, Map<String, BufferedWriter> writers) {
        String[] parts = line.split("\t", -1);
        if (parts.length != 6) {
            printError(inputFile.getName(), lineNumber, "Invalid format - expected 6 tab-separated columns");
            return;
        }

        String mime = parts[3];
        String type = mime.contains("/") ? mime.substring(0, mime.indexOf('/')) : mime;

        if (!mimeFilter.isEmpty() && !mimeFilter.contains(type)) {
            return;
        }

        String key = splitByMajorType ? type : sanitizeMime(mime);
        try (BufferedWriter w = getOrCreateWriter(writers, key)) {
            w.write(line);
            w.newLine();
        } catch (IOException e) {
            printError(inputFile.getName(), lineNumber, "Failed to write line: " + e.getMessage());
        }
    }

    private BufferedWriter getOrCreateWriter(Map<String, BufferedWriter> writers, String key) throws IOException {
        if (writers.containsKey(key)) {
            return writers.get(key);
        }
        Path outPath = outDir.toPath().resolve(prefix + "_" + key + ".meta");
        BufferedWriter writer = Files.newBufferedWriter(outPath);
        writers.put(key, writer);
        return writer;
    }

    private void closeAll(Map<String, BufferedWriter> writers) throws IOException {
        IOException first = null;
        for (Map.Entry<String, BufferedWriter> entry : writers.entrySet()) {
            try {
                entry.getValue().close();
            } catch (IOException e) {
                if (first == null) first = e;
                System.err.printf("ERROR closing writer for %s: %s%n", entry.getKey(), e.getMessage());
            }
        }
        if (first != null) throw first;
    }

    private void printError(String file, int line, String message) {
        System.err.printf("ERROR : %s : line %d : %s%n", file, line, message);
    }

    private String sanitizeMime(String mime) {
        return mime.replaceAll("[^a-zA-Z0-9]+", "_");
    }

    private String stripExtension(String name) {
        int dot = name.lastIndexOf('.');
        return (dot > 0) ? name.substring(0, dot) : name;
    }
}
