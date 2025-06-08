package hashtools.commands;

import picocli.CommandLine.*;

@Command(
        name = "meta",
        description = "Meta file tools: post-process, inspect, filter, and validate .meta files",
        subcommands = {
            MetaValidateSubCommand.class,
        },
        mixinStandardHelpOptions = true,
        usageHelpAutoWidth = true
)
public class MetaCommand implements Runnable {

    @Spec
    Model.CommandSpec spec;

    @Override
    public void run() {
        spec.commandLine().usage(System.out);
    }
}
