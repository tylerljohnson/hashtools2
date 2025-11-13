package hashtools.commands.meta.summary;

import picocli.CommandLine.*;

import java.io.*;
import java.util.*;

@Command(
    name = "summary",
    description = "Generate a summary report of one or more .meta files.",
    mixinStandardHelpOptions = true
)
public class MetaSummarySubCommand implements Runnable {

    @Parameters(arity = "1..*", paramLabel = "FILES", description = ".meta file(s) to summarize")
    private List<File> metaFiles;

    @Option(names = {"--detail"}, description = "Show full MIME list and size breakdown")
    private boolean detail = false;

    @Override
    public void run() {
        MetaSummaryProcessor.detail = detail;
        MetaSummaryProcessor processor = new MetaSummaryProcessor(metaFiles);
        processor.run();
    }

}
