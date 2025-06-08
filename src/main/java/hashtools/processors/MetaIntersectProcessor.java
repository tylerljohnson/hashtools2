package hashtools.processors;

import hashtools.models.*;
import hashtools.utils.*;

import java.io.*;
import java.util.*;
import java.util.stream.*;

public class MetaIntersectProcessor implements Processor {
    private final File file1;
    private final File file2;
    private final BufferedWriter writer;
    private final Set<String> mimeFilter;

    public MetaIntersectProcessor(File file1, File file2, BufferedWriter writer, Set<String> mimeFilter) {
        this.file1 = file1;
        this.file2 = file2;
        this.writer = writer;
        this.mimeFilter = mimeFilter != null ? mimeFilter : Collections.emptySet();
    }

    @Override
    public void run() {
        try {
            List<MetaItem> list1 = MetaFileUtils.readMetaFile(file1);
            List<MetaItem> list2 = MetaFileUtils.readMetaFile(file2);

            Set<String> hashes2 = list2.stream()
                    .map(MetaItem::hash)
                    .collect(Collectors.toSet());

            List<MetaItem> intersection = list1.stream()
                    .filter(item -> hashes2.contains(item.hash()))
                    .filter(item -> mimeFilter.isEmpty() || mimeFilter.contains(MimeUtils.getMajorType(item.mimeType())))
                    .collect(Collectors.toList());

            for (MetaItem item : intersection) {
                writer.write(MetaFileUtils.toTsvString(item));
                writer.newLine();
            }
            writer.flush();
        } catch (IOException e) {
            System.err.printf("ERROR: %s%n", e.getMessage());
        }
    }
}
