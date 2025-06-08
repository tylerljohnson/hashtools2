package hashtools.processors;

import hashtools.models.*;
import hashtools.utils.*;

import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.stream.*;

public class MetaIntersectProcessor implements Processor {
    private final File file1;
    private final File file2;
    private final BufferedWriter writer;
    private final Set<String> mimeFilter;
    private final boolean view;

    public MetaIntersectProcessor(File file1, File file2, BufferedWriter writer, Set<String> mimeFilter, boolean view) {
        this.file1 = file1;
        this.file2 = file2;
        this.writer = writer;
        this.mimeFilter = mimeFilter != null ? mimeFilter : Collections.emptySet();
        this.view = view;
    }

    @Override
    public void run() {
        try {
            List<MetaItem> list1 = MetaFileUtils.readMetaFile(file1);
            List<MetaItem> list2 = MetaFileUtils.readMetaFile(file2);

            List<MetaItem> intersection = computeIntersection(list1, list2);

            Viewer viewer = view ? new MimeImageViewer() : new NoOpViewer();

            for (MetaItem item : intersection) {
                writer.write(MetaFileUtils.toTsvString(item));
                writer.newLine();
                viewer.view(item);
            }
            writer.flush();
        } catch (IOException e) {
            System.err.printf("ERROR: %s%n", e.getMessage());
        }
    }

    private List<MetaItem> computeIntersection(List<MetaItem> list1, List<MetaItem> list2) {
        Set<String> hashes2 = list2.stream()
                .map(MetaItem::hash)
                .collect(Collectors.toSet());

        return list1.stream()
                .filter(item -> hashes2.contains(item.hash()))
                .filter(item -> {
                    String mime = item.mimeType();
                    if (mime == null) return false;
                    return mimeFilter.isEmpty() || mimeFilter.contains(MimeUtils.getMajorType(mime));
                })
                .collect(Collectors.toList());
    }

    private interface Viewer {
        void view(MetaItem item);
    }

    private static class NoOpViewer implements Viewer {
        @Override
        public void view(MetaItem item) {}
    }

    private static class MimeImageViewer implements Viewer {
        @Override
        public void view(MetaItem item) {
            if (item.basePath() == null || item.filePath() == null) return;

            List<String> command = buildCommand(item);
            if (command == null) {
                //System.err.printf("WARN: No viewer for MIME type %s%n", item.mimeType());
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
//                    "--center",
                    "--grid=1x5",
                    String.format("--title=\"%%f (%%wx%%h)\""),
                    fullPath.toString()
            );
        }

        private void executeCommand(List<String> command) {
            ProcessBuilder pb = new ProcessBuilder(command);
            pb.inheritIO();
            try {
                pb.start().waitFor();
            } catch (IOException e) {
                System.err.printf("ERROR: Failed to run viewer command '%s': %s%n", String.join(" ", command), e.getMessage());
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
    }
}
