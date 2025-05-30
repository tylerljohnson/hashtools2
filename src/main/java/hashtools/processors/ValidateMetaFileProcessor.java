package hashtools.processors;

import java.io.*;

public class ValidateMetaFileProcessor implements Processor {
    private File file;
    public ValidateMetaFileProcessor(File file) {
        super();
        this.file = file;
    }

    @Override
    public void run() {
        if (!file.exists()) {
            throw new RuntimeException("File does not exist: " + file.getAbsolutePath());
        }
        if (!file.isFile()) {
            throw new RuntimeException("Not a file: " + file.getAbsolutePath());
        }
        if (!file.canRead()) {
            throw new RuntimeException("File is not readable: " + file.getAbsolutePath());
        }

        // need to read and validate the meta file, it should be a TSV with the correct columns and column types

        try (BufferedReader reader = new BufferedReader(new FileReader(file))) {
            int expectedColumns = 3; // Adjust based on your expected format
            String line;
            int lineNumber = 0;
            while ((line = reader.readLine()) != null) {
                lineNumber++;
                String[] columns = line.split("\t");
                if (columns.length != expectedColumns) {
                    throw new RuntimeException("Invalid meta file format at line " + lineNumber + ": " + line);
                }

                // Validate each column as needed, e.g., check if the first column is a valid hash
                // For simplicity, we assume the first column is a hash and the second is a filename
                // You can add more validation logic here as required

            }
        } catch (IOException e) {
            throw new RuntimeException("Error reading meta file: " + e.getMessage(), e);
        }

    }
}
