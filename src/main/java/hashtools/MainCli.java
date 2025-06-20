package hashtools;

import hashtools.commands.generate.*;
import hashtools.commands.meta.*;
import hashtools.utils.*;
import picocli.*;
import picocli.CommandLine.*;

import java.io.*;
import java.util.concurrent.*;

@Command(
    name = "hashtools",
    description = "A CLI tool for generating file metadata.",
    mixinStandardHelpOptions = true,
    versionProvider = ManifestVersionProvider.class,
    subcommands = {
        GenerateCommand.class,
        MetaCommand.class,
    }
)
public class MainCli implements Callable<Integer> {

    public static final String DOCS_TXT_RESOURCE_PATH = "/docs.txt";
    @Option(names = "--docs", description = "Show project and command documentation.")
    private boolean docsRequested;

    @Override
    public Integer call() throws Exception {
        if (docsRequested) {
            return printDocs();
        }

        CommandLine.usage(this, System.out);
        return ExitCode.OK;
    }

    private int printDocs() {
        try (InputStream in = getClass().getResourceAsStream(DOCS_TXT_RESOURCE_PATH);
             BufferedReader reader = in == null ? null : new BufferedReader(new InputStreamReader(in))) {
            if (reader == null) {
                System.err.println("Documentation not found.");
                return ExitCode.ERROR;
            }
            reader.lines().forEach(System.err::println);
        } catch (IOException e) {
            System.err.println("Error reading documentation: " + e.getMessage());
            return ExitCode.ERROR;
        }
        return ExitCode.OK;
    }

    public static void main(String[] args) {
        CommandLine cli = new CommandLine(new MainCli());

        cli.setExecutionExceptionHandler(new ShortErrorHandler());
        cli.setColorScheme(Help.defaultColorScheme(Help.Ansi.ON));
        cli.setUsageHelpAutoWidth(true);

        if (args.length == 0) {
            cli.usage(System.out);
            System.exit(ExitCode.OK);
        }

        int exitCode = cli.execute(args);
        System.exit(exitCode);
    }

    static class ShortErrorHandler implements IExecutionExceptionHandler {
        @Override
        public int handleExecutionException(Exception ex, CommandLine cmd, ParseResult parseResult) {
            cmd.getErr().println(cmd.getColorScheme().errorText("ERROR: " + ex.getMessage()));
            if (cmd.isUsageHelpRequested() || cmd.isVersionHelpRequested()) {
                return cmd.getCommandSpec().exitCodeOnUsageHelp();
            }
            cmd.usage(cmd.getErr(), cmd.getColorScheme());
            return cmd.getCommandSpec().exitCodeOnExecutionException();
        }
    }

}
