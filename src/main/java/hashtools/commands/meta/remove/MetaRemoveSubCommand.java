// src/main/java/hashtools/commands/meta/remove/MetaRemoveSubCommand.java
package hashtools.commands.meta.remove;

import picocli.CommandLine.*;

import java.io.File;

@Command(
        name = "remove",
        description = "Log (or later delete) all .meta entries matching the hash+MIME of given files or directories",
        mixinStandardHelpOptions = true
)
public class MetaRemoveSubCommand implements Runnable {

    @Option(names = "--reference-meta", required = true, paramLabel = "META_FILE",
            description = "Reference .meta file to read entries from")
    private File referenceMeta;

    @Parameters(index = "0..*", arity = "1..*", paramLabel = "TARGET...",
            description = "One or more absolute paths (file or directory) whose hash+MIME group's other entries will be removed")
    private File[] targets;

    @Option(names = "--debug", defaultValue = "false",
            description = "Print debug information about grouping and matching (default: false)")
    private boolean debug = false;

    @Override
    public void run() {
        new MetaRemoveProcessor(referenceMeta, targets, debug).run();
    }
}
