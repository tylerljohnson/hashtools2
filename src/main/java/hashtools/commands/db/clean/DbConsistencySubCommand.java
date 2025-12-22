package hashtools.commands.db.clean;

import picocli.CommandLine;
import picocli.CommandLine.Command;

@Command(
        name = "consistency",
        description = "Remove stale db rows from database",
        mixinStandardHelpOptions = true
)
public class DbConsistencySubCommand implements Runnable {

    @CommandLine.Option(names = {"-d", "--delete"},
            negatable = true,
            defaultValue = "false",
            description = "Delete the stale db rows as they are found")
    private boolean deleteRows;

    @Override
    public void run() { new DbConsistencyProcessor(deleteRows).run(); }
}
