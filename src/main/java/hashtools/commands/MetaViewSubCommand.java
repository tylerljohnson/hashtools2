// src/main/java/hashtools/commands/MetaViewSubCommand.java
package hashtools.commands;

import hashtools.processors.*;
import picocli.CommandLine.*;

import java.io.*;
import java.util.*;

@Command(
        name = "view",
        description = "Preview items in one or more .meta files grouped by hash and MIME type",
        mixinStandardHelpOptions = true
)
public class MetaViewSubCommand implements Runnable {

    @Parameters(arity = "1..*", paramLabel = "<meta-files>", description = "One or more .meta files to preview")
    private File[] metaFiles;

    @Option(names = "--mime-filter", split = ",",
            description = "Restrict to these major MIME types (e.g. image, video)")
    private Set<String> mimeFilter;

    @Override
    public void run() {
        new MetaViewProcessor(metaFiles, mimeFilter).run();
    }
}
