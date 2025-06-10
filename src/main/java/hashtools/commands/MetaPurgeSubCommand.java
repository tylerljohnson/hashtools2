package hashtools.commands;

import hashtools.processors.MetaPurgeProcessor;
import picocli.CommandLine.*;

import java.io.File;

@Command(
        name = "purge",
        description = "Find items in the target .meta file matching reference and optionally delete them",
        mixinStandardHelpOptions = true
)
public class MetaPurgeSubCommand implements Runnable {

    @Parameters(index = "0", paramLabel = "REFERENCE", description = "Reference .meta file (read-only)")
    private File referenceFile;

    @Parameters(index = "1", paramLabel = "TARGET", description = "Target .meta file to search")
    private File targetFile;

    @Option(names = {"--delete"}, negatable = true,
            description = "Actually delete matched files (default: false)", defaultValue = "false")
    private boolean delete;

    @Option(names = {"--view"}, negatable = true,
            description = "Preview one match per duplicate hash if image (default: false)", defaultValue = "false")
    private boolean view;

    @Option(names = {"--simple"}, description = "Only print file paths of matches (default: false)", defaultValue = "false")
    private boolean simple;

    @Override
    public void run() {
        new MetaPurgeProcessor(referenceFile, targetFile, delete, view, simple).run();
    }
}
