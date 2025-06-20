package hashtools.commands.meta.purge;

import picocli.CommandLine.*;

import java.io.*;
import java.util.*;

@Command(
    name = "purge",
    description = "Find items in target .meta file matching reference and optionally delete their files",
    mixinStandardHelpOptions = true
)
public class MetaPurgeSubCommand implements Runnable {

    @Parameters(index = "0", paramLabel = "REFERENCE", description = "Reference .meta file (read-only)")
    private File referenceFile;

    @Parameters(index = "1", paramLabel = "TARGET", description = "Target .meta file to search for matches")
    private File targetFile;

    @Option(names = {"--delete"}, negatable = true, description = "Actually delete matched files (default: false)", defaultValue = "false")
    private boolean delete;

    @Option(names = {"--view"}, negatable = true, description = "Preview one match per duplicate hash if image (default: false)", defaultValue = "false")
    private boolean view;

    @Option(names = {"--simple"}, description = "Only print file paths to be removed (default: false)", defaultValue = "false")
    private boolean simple;

    @Option(names = "--mime-filter", split = ",", description = "Restrict purge to items with these major MIME types (e.g. image, video)")
    private Set<String> mimeFilter;

    @Override
    public void run() {
        new MetaPurgeProcessor(referenceFile, targetFile, delete, view, simple, mimeFilter).run();
    }

}
