package hashtools.commands.db;

import hashtools.commands.db.clean.DbConsistencySubCommand;
import picocli.CommandLine.Command;
import picocli.CommandLine.Model;
import picocli.CommandLine.Spec;

@Command(
        name = "db",
        description = "db command",
        subcommands = {
            DbConsistencySubCommand.class
        },
        mixinStandardHelpOptions = true,
        usageHelpAutoWidth = true
)
public class DbCommand implements Runnable {
    @Spec
    Model.CommandSpec spec;
    @Override
    public void run() {
        spec.commandLine().usage(System.out);
    }
}
