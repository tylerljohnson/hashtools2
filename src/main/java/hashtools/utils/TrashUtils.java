package hashtools.utils;

import java.io.*;
import java.nio.file.*;

public class TrashUtils {
    private TrashUtils() {
        throw new UnsupportedOperationException("Utility class cannot be instantiated");
    }

    public static boolean moveToTrash(Path path) {
        if (!Files.exists(path)) {
            System.err.printf("WARN: File not found: %s%n", path);
            return false;
        }

        try {
            String os = System.getProperty("os.name").toLowerCase();

            Process process;
            if (os.contains("mac")) {
                // macOS: move to ~/.Trash/
                Path trashPath = Paths.get(System.getProperty("user.home"), ".Trash", path.getFileName().toString());
                Files.move(path, trashPath, StandardCopyOption.REPLACE_EXISTING);
                return true;

            } else if (os.contains("linux")) {
                // Linux GNOME-based (gio trash)
                process = new ProcessBuilder("gio", "trash", path.toString())
                        .redirectErrorStream(true)
                        .start();
                int exitCode = process.waitFor();
                return exitCode == 0;

            } else {
                System.err.printf("ERROR: Trash not supported on this OS: %s%n", os);
                return false;
            }

        } catch (IOException | InterruptedException e) {
            System.err.printf("ERROR: Failed to move to trash: %s%n", e.getMessage());
            return false;
        }
    }
}
