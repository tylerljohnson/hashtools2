package hashtools.commands;

import hashtools.processors.*;
import picocli.CommandLine.*;

import java.io.*;

@Command(
        name = "validate",
        description = "Validate a meta file",
        mixinStandardHelpOptions = true
)
public class MetaValidateSubCommand implements Runnable {

    @Parameters(paramLabel = "<file>", description = "The meta file to validate")
    File file;

    @Override
    public void run() {
        try {
            new ValidateMetaFileProcessor(file).run();

            System.out.println("Meta file is valid: " + file.getAbsolutePath());
        } catch (Exception e) {
            throw new RuntimeException("Unable to hash file: " + e.getMessage(), e);
        }
    }
}
