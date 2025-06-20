package hashtools.commands.meta.view;

import hashtools.commands.Processor;
import picocli.CommandLine.*;

import java.io.File;
import java.util.Collections;
import java.util.Set;

@Command(
        name = "view",
        description = "Preview items in one or more .meta files, grouped by hash and MIME type",
        mixinStandardHelpOptions = true
)
public class MetaViewSubCommand implements Runnable {

    @Parameters(index = "0..*", arity = "1..*",
            paramLabel = "FILES...",
            description = "One or more .meta files to view")
    private File[] metaFiles;

    @Option(names = "--mime-filter", split = ",",
            description = "Restrict to these major MIME types (e.g. image, video)")
    private Set<String> mimeFilter = Collections.emptySet();

    @Option(names = {"--view"}, defaultValue = "false",
            description = "Preview one exemplar image per group (default: false)")
    private boolean view = false;

    @Override
    public void run() {
        new MetaViewProcessor(metaFiles, mimeFilter, view).run();
    }
}
