package hashtools.commands.meta.split;

import hashtools.commands.*;
import picocli.CommandLine.*;

import java.io.*;
import java.util.*;

@Command(
    name = "split",
    description = "Split .meta file by MIME type into separate files.",
    mixinStandardHelpOptions = true
)
public class MetaSplitSubCommand implements Runnable {

    @Parameters(index = "0", description = "The input .meta file")
    private File inputFile;

    @Option(names = {"-o", "--output"}, description = "Output directory (default: current directory)")
    private File outDir = new File(".");

    @Option(names = {"-p", "--prefix"}, description = "Prefix for output files")
    private String prefix;

    @Option(names = {"--mime-filter"}, description = "Restrict to MIME types (e.g. image, video, application)")
    private Set<String> mimeFilter;

    @Option(names = {"--major-type"}, description = "Split by MIME major type instead of full MIME type")
    private boolean majorType;

    @Override
    public void run() {
        Processor processor = new MetaSplitProcessor(inputFile, outDir, prefix, mimeFilter, majorType);
        processor.run();
    }

}
