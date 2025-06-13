package hashtools.processors;

import java.io.*;
import java.nio.file.*;
import java.util.*;

public class MetaValidateProcessor implements Processor {

    private final List<File> metaFiles;
    private boolean hasErrors = false;

    public MetaValidateProcessor(List<File> metaFiles) {
        this.metaFiles = metaFiles;
    }

    @Override
    public void run() {
        for (File file : metaFiles) {
            if (!file.exists() || !file.isFile()) {
                System.err.printf("ERROR: %s does not exist or is not a regular file.%n", file);
                hasErrors = true;
                continue;
            }

            try (BufferedReader reader = Files.newBufferedReader(file.toPath())) {
                String line;
                int lineNum = 0;
                while ((line = reader.readLine()) != null) {
                    lineNum++;
                    String[] parts = line.split("\t", -1);
                    if (parts.length != 6) {
                        printError(file, lineNum, String.format("Malformed line - expected 6 tab-separated columns but found %d.", parts.length));
                        hasErrors = true;
                        continue;
                    }
                    if (!isValidSha1(parts[0])) {
                        printError(file, lineNum, String.format("Invalid SHA-1 hash format in column 1: '%s'", parts[0]));
                        hasErrors = true;
                    }
                    if (!isLong(parts[2])) {
                        printError(file, lineNum, String.format("Invalid file size in column 3 (expected long): '%s'", parts[2]));
                        hasErrors = true;
                    }
                }
            } catch (IOException e) {
                System.err.printf("ERROR reading %s: %s%n", file.getName(), e.getMessage());
                hasErrors = true;
            }
        }

        if (!hasErrors) {
            System.out.println("All files validated successfully.");
        }
    }

    public boolean isSuccessful() {
        return !hasErrors;
    }

    private boolean isValidSha1(String s) {
        return s != null && s.matches("^[a-fA-F0-9]{40}$");
    }

    private boolean isLong(String s) {
        try {
            Long.parseLong(s);
            return true;
        } catch (NumberFormatException e) {
            return false;
        }
    }

    public static boolean validate(List<File> metaFiles) {
        MetaValidateProcessor processor = new MetaValidateProcessor(metaFiles);
        processor.run();
        return processor.isSuccessful();
    }

    private void printError(File file, int lineNum, String message) {
        System.err.printf("ERROR : %s : line %d : %s%n", file.getName(), lineNum, message);
    }

}
