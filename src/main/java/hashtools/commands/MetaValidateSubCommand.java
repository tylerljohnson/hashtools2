package hashtools.commands;

import hashtools.processors.*;
import picocli.CommandLine.*;

import java.io.*;
import java.util.*;

@Command(
        name = "validate",
        description = "Validate .meta files for format and column types.",
        mixinStandardHelpOptions = true
)
public class MetaValidateSubCommand implements Runnable {

    @Parameters(arity = "1..*", paramLabel = "FILES", description = ".meta file(s) to validate")
    private List<File> metaFiles;

    @Override
    public void run() {
        boolean success = MetaValidateProcessor.validate(metaFiles);
        if (!success) {
            System.exit(1);
        }
    }
}
