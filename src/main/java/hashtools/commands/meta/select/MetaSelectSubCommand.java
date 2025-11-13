package hashtools.commands.meta.select;

import picocli.CommandLine.*;

import java.io.*;
import java.util.*;

@Command(
        name = "select",
        description = "Select the best (oldest) version per hash and MIME type among provided meta files",
        mixinStandardHelpOptions = true
)
public class MetaSelectSubCommand implements Runnable {

    @Parameters(
            index       = "0..*",
            arity       = "1..*",
            paramLabel  = "FILES...",
            description = "First file is reference; any additional files are data files to select from"
    )
    private File[] inputFiles;

    @Option(names = "--mime-filter", split = ",",
            description = "Restrict to these major MIME types (e.g. image, video)")
    private Set<String> mimeFilter = Collections.emptySet();

    @Option(names = "--paths",
            description = "Output only the full path of the selected file per group")
    private boolean pathsOnly = false;

    @Option(names = {"--view"}, negatable = true, defaultValue = "false",
            description = "Preview each selected item if it is an image (default: false)")
    private boolean view = false;

    @Option(names = {"--summary"}, negatable = true, defaultValue = "false",
            description = "Print total selected and unselected sizes (default: false)")
    private boolean summary = false;

    @Option(names = "--copy", paramLabel = "DEST_DIR",
            description = "Copy each selected file to this directory, stripping first 3 path segments")
    private File copyDir;

    @Option(names = {"--prune"}, negatable = true, defaultValue = "false",
            description = "Prune (delete) all non-best (more recent) duplicates (default: false)")
    private boolean prune = false;

    @Override
    public void run() {
        // Split out reference vs data
        File referenceFile = inputFiles[0];
        File[] dataFiles;
        if (inputFiles.length > 1) {
            dataFiles = Arrays.copyOfRange(inputFiles, 1, inputFiles.length);
        } else {
            dataFiles = new File[] { referenceFile };
        }

        // Validate --copy target directory if provided
        if (copyDir != null) {
            if (!copyDir.exists() || !copyDir.isDirectory()
                    || !copyDir.canRead()   || !copyDir.canWrite()) {
                System.err.printf(
                        "ERROR: --copy target must be an existing, readable/writable directory: %s%n",
                        copyDir
                );
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
                copyDir,
                prune
        ).run();
    }
}
