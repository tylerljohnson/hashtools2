package hashtools.commands.meta;

import hashtools.commands.meta.clean.*;
import hashtools.commands.meta.intersect.*;
import hashtools.commands.meta.purge.*;
import hashtools.commands.meta.select.*;
import hashtools.commands.meta.split.*;
import hashtools.commands.meta.summary.*;
import hashtools.commands.meta.validate.*;
import hashtools.commands.meta.view.*;
import picocli.CommandLine.*;

@Command(
        name = "meta",
        description = "Meta file tools: post-process, inspect, filter, and validate .meta files",
        subcommands = {
            MetaValidateSubCommand.class,
            MetaSummarySubCommand.class,
            MetaSplitSubCommand.class,
            MetaIntersectSubCommand.class,
            MetaPurgeSubCommand.class,
            MetaViewSubCommand.class,
            MetaSelectSubCommand.class,
            MetaCleanSubCommand.class,
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
