package hashtools.commands;

import hashtools.processors.*;
import picocli.CommandLine.*;

import java.io.*;
import java.nio.charset.*;
import java.util.*;

@Command(
        name = "intersect",
        description = "Find common entries by hash from two meta files",
        mixinStandardHelpOptions = true
)
public class MetaIntersectSubCommand implements Runnable {

    @Parameters(arity = "2", paramLabel = "<meta-files>", description = "Exactly two .meta files to compare")
    private List<File> inputFiles;

    @Option(names = {"-o", "--output"}, paramLabel = "<output>", description = "Path to output meta file, or '-' for stdout", defaultValue = "-")
    private String output;

    @Option(names = "--mime-filter", paramLabel = "<type>", split = ",", description = "Filter by MIME major types (e.g. image, video)")
    private Set<String> mimeFilter;

    @Override
    public void run() {
        try (BufferedWriter writer = new BufferedWriter(new OutputStreamWriter(
                "-".equals(output) ? System.out : new FileOutputStream(output), StandardCharsets.UTF_8))) {

            MetaIntersectProcessor processor = new MetaIntersectProcessor(
                    inputFiles.get(0),
                    inputFiles.get(1),
                    writer,
                    mimeFilter
            );
            processor.run();
        } catch (IOException e) {
            System.err.printf("ERROR: %s%n", e.getMessage());
        }
    }
}
