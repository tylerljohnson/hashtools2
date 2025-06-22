package hashtools.commands.meta.clean;

import java.io.*;

import picocli.CommandLine.*;

@Command(
        name = "clean",
        description = "Remove stale entries from .meta files whose on-disk properties no longer match",
        mixinStandardHelpOptions = true
)
public class MetaCleanSubCommand implements Runnable {

    @Parameters(index = "0..*", arity = "1..*",
            paramLabel = "FILES...",
            description = "One or more .meta files to clean")
    private File[] metaFiles;

    @Option(names = {"--no-dryrun"}, defaultValue = "true",
            description = "Show entries that would be removed without touching files (default: f)")
    private boolean dryRun;

    @Option(names = {"--verbose"}, negatable = true, defaultValue = "false",
            description = "Log each entry kept or removed (default: false)")
    private boolean verbose;

    @Option(names = {"--full-check"}, negatable = true, defaultValue = "false",
            description = "Also verify size, timestamp, and MIME type (default: existence only)")
    private boolean fullCheck;

    @Option(names = {"--no-progress"}, defaultValue = "false",
            description = "Suppress the in-line progress bar (default: false)")
    private boolean noProgress;

    @Override
    public void run() {
        new MetaCleanProcessor(metaFiles, dryRun, verbose, fullCheck, noProgress).run();
    }
}
