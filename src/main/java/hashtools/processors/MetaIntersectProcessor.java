package hashtools.processors;

import hashtools.models.*;
import hashtools.utils.*;
import hashtools.viewers.*;

import java.io.*;
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

            MetaItemViewer metaItemViewer = view ? new ImageViewer() : new NoOpMetaItemViewer();

            for (MetaItem item : intersection) {
                writer.write(MetaFileUtils.toTsvString(item));
                writer.newLine();
                metaItemViewer.view(item);
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

}
