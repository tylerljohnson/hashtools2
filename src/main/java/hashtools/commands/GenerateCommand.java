package hashtools.commands;

import hashtools.processors.*;
import picocli.CommandLine.*;

import java.io.*;
import java.util.*;

@Command(
        name = "generate",
        description = "Generate a hashes for a directory and writes the meta to a TSV formated file.",
        mixinStandardHelpOptions = true
)
public class GenerateCommand implements Runnable {

    @Option(names = {"-s", "--silent"},
            negatable = true,
            description = "Suppress console output (use --no-silent to enable)")
    private boolean silent;

    @Parameters(index = "0",
            description = "Root directory to scan")
    private File rootDir;

    @Option(names = {"-t", "--threads"},
            description = "Number of threads (default: ${DEFAULT-VALUE})")
    private int threadCount = Runtime.getRuntime().availableProcessors();

    @Option(names = {"-q", "--queue-size"},
            description = "Queue capacity for backpressure (default: ${DEFAULT-VALUE})")
    private int queueSize = GenerateMetaProcessor.DEFAULT_QUEUE_SIZE;

    @Option(names = {"-b", "--batch-size"},
            description = "Lines to batch per write (default: ${DEFAULT-VALUE})")
    private int batchSize = GenerateMetaProcessor.DEFAULT_BATCH_SIZE;

    @Option(names = {"-o", "--output"},
            description = "Output a .meta file, which is TSV with comments (default: <timestamp>.meta)")
    private File outputFile;

    @Option(names = {"-i", "--include"},
            description = "Include files by MIME type (e.g., 'image', 'text'). Multiple filters can be specified.")
    private Set<String> includeTypeFilter = Collections.emptySet();

    @Override
    public void run() {
        try {
            new GenerateMetaProcessor(
                    rootDir,
                    outputFile,
                    threadCount,
                    queueSize,
                    batchSize,
                    silent,
                    includeTypeFilter
            ).run();
        } catch (Exception e) {
            throw new RuntimeException("Unable to generate meta file: " + e.getMessage(), e);
        }
    }

}
