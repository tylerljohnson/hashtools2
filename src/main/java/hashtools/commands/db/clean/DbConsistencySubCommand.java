package hashtools.commands.db.clean;

import picocli.CommandLine.Command;

@Command(
        name = "consistency",
        description = "Remove stale db rows from database",
        mixinStandardHelpOptions = true
)
public class DbConsistencySubCommand implements Runnable {

    @Override
    public void run() { new DbConsistencyProcessor().run(); }
}
