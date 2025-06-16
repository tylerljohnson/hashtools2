package hashtools.commands;

import hashtools.processors.*;

import java.io.*;
import java.util.*;

import picocli.CommandLine.*;

@Command(
        name = "select",
        description = "Select the best (oldest) version per hash and MIME type among provided meta files",
        mixinStandardHelpOptions = true
)
public class MetaSelectSubCommand implements Runnable {

    @Parameters(index = "0", paramLabel = "REFERENCE",
            description = "Reference .meta file containing hashes to select")
    private File referenceFile;

    @Parameters(index = "1..*", paramLabel = "DATA...",
            description = "One or more data .meta files to search")
    private File[] dataFiles;

    @Option(names = "--mime-filter", split = ",",
            description = "Restrict to these major MIME types (e.g. image, video)")
    private Set<String> mimeFilter = Collections.emptySet();

    @Option(names = "--paths",
            description = "Output only the full path of the selected file per group")
    private boolean pathsOnly = false;

    @Option(names = {"--view", "--no-view"}, negatable = true,
            description = "Preview each selected item if it is an image (default: false)", defaultValue = "false")
    private boolean view = false;

    @Option(names = {"--summary", "--no-summary"}, negatable = true,
            description = "Print total selected and unselected sizes (default: false)", defaultValue = "false")
    private boolean summary = false;

    @Option(names = "--copy", paramLabel = "DEST_DIR",
            description = "Copy each selected file to this directory, stripping first 3 path segments")
    private File copyDir;

    @Override
    public void run() {
        // Validate copy directory if provided
        if (copyDir != null) {
            if (!copyDir.exists() || !copyDir.isDirectory() || !copyDir.canRead() || !copyDir.canWrite()) {
                System.err.printf("ERROR: --copy target must be an existing, readable/writable directory: %s%n", copyDir);
                System.exit(1);
            }
        }

        new MetaSelectProcessor(
                referenceFile,
                dataFiles,
                mimeFilter,
                pathsOnly,
                view,
                summary,
                copyDir
        ).run();
    }
}
