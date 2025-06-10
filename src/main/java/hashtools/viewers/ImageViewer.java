package hashtools.viewers;

import hashtools.models.*;
import hashtools.utils.*;

import java.io.*;
import java.nio.file.*;
import java.util.*;

public class ImageViewer implements MetaItemViewer {
    @Override
    public void view(MetaItem item) {
        if (item.basePath() == null || item.filePath() == null) return;

        List<String> command = buildCommand(item);
        if (command == null) {
            //System.err.printf("WARN: No viewers for MIME type %s%n", item.mimeType());
            return;
        }

        executeCommand(command);
    }

    private List<String> buildCommand(MetaItem item) {
        String mime = item.mimeType();
        if (mime == null) return null;

        String major = MimeUtils.getMajorType(mime);
        switch (major) {
            case "image":
                return buildImageCommand(item);
            default:
                return null;
        }
    }

    private List<String> buildImageCommand(MetaItem item) {
        Path fullPath = Path.of(item.basePath(), item.filePath());
        return List.of(
                "timg",
                "--grid=1x5",
                "--loops=1",
                "--title=(%wx%h)",
                fullPath.toString()
        );
    }

    private void executeCommand(List<String> command) {
        ProcessBuilder pb = new ProcessBuilder(command);
        pb.inheritIO();
        try {
            pb.start().waitFor();
        } catch (IOException e) {
            System.err.printf("ERROR: Failed to run viewers command '%s': %s%n", String.join(" ", command), e.getMessage());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
