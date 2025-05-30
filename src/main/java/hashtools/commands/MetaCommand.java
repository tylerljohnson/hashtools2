package hashtools.commands;

import picocli.*;
import picocli.CommandLine.*;

@Command(
        name = "meta",
        description = "Commands to manage meta files.",
        mixinStandardHelpOptions = true,
        subcommands = {
            MetaValidateSubCommand.class,
        }
)
public class MetaCommand implements Runnable {
    @Override
    public void run() {
        CommandLine.usage(this, System.out);
    }
}
