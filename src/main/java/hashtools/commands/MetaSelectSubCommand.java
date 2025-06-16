package hashtools.commands;

import hashtools.processors.MetaSelectProcessor;
import picocli.CommandLine.*;

import java.io.File;
import java.util.Collections;
import java.util.Set;

@Command(
        name = "select",
        description = "Select the oldest version per hash and MIME type among provided meta files",
        mixinStandardHelpOptions = true
)
public class MetaSelectSubCommand implements Runnable {

    @Parameters(index = "0", paramLabel = "REFERENCE", description = "Reference .meta file containing hashes to select")
    private File referenceFile;

    @Parameters(index = "1..*", paramLabel = "DATA...", description = "One or more data .meta files to search")
    private File[] dataFiles;

    @Option(names = "--mime-filter", split = ",",
            description = "Restrict to these major MIME types (e.g. image, video)")
    private Set<String> mimeFilter = Collections.emptySet();

    @Option(names = "--paths", description = "Output only the full path of the selected file per group")
    private boolean pathsOnly = false;

    @Option(names = {"--view"}, negatable = true,
            description = "Preview each selected item if it is an image")
    private boolean view = false;

    @Option(names = "--summary", description = "Print total size of selected files in human-readable format (default: false)")
    private boolean summary = false;

    @Override
    public void run() {
        new MetaSelectProcessor(
                referenceFile,
                dataFiles,
                mimeFilter,
                pathsOnly,
                view,
                summary
        ).run();
    }
}