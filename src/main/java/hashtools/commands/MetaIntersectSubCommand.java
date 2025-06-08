package hashtools.commands;

import hashtools.processors.*;
import picocli.CommandLine.*;

import java.io.*;
import java.nio.file.*;
import java.util.*;

@Command(
        name = "intersect",
        description = "Find items common to two .meta files",
        mixinStandardHelpOptions = true
)
public class MetaIntersectSubCommand implements Runnable {

    @Parameters(index = "0", paramLabel = "FILE1", description = "First meta file")
    private File file1;

    @Parameters(index = "1", paramLabel = "FILE2", description = "Second meta file")
    private File file2;

    @Option(names = {"-o", "--output"}, description = "Output file (use '-' for stdout)", defaultValue = "-")
    private File output;

    @Option(names = {"--view"}, negatable = true, description = "View matching images using CLI viewers")
    private boolean view = false;

    @Option(names = "--mime-filter", split = ",", description = "Restrict to specific major MIME types")
    private Set<String> mimeFilter;

    @Override
    public void run() {
        try (BufferedWriter writer = view ? createNullWriter() : createWriter(output)) {
            new MetaIntersectProcessor(file1, file2, writer, mimeFilter, view).run();
        } catch (IOException e) {
            System.err.printf("ERROR: %s%n", e.getMessage());
            System.exit(1);
        }
    }

    private BufferedWriter createWriter(File outputFile) throws IOException {
        if (outputFile.getPath().equals("-")) {
            return new BufferedWriter(new OutputStreamWriter(System.out));
        } else {
            return Files.newBufferedWriter(outputFile.toPath());
        }
    }

    private BufferedWriter createNullWriter() {
        return new BufferedWriter(Writer.nullWriter());
    }
}
