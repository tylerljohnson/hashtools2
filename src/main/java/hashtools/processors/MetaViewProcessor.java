package hashtools.processors;

import hashtools.models.*;
import hashtools.utils.*;
import hashtools.viewers.*;

import java.io.*;
import java.util.*;
import java.util.stream.*;

public class MetaViewProcessor implements Processor {
    private final File[] metaFiles;
    private final Set<String> mimeFilter;

    public MetaViewProcessor(File[] metaFiles, Set<String> mimeFilter) {
        this.metaFiles = metaFiles;
        this.mimeFilter = mimeFilter != null ? mimeFilter : Collections.emptySet();
    }

    @Override
    public void run() {
        // Load all items from provided meta files
        List<MetaItem> allItems = new ArrayList<>();
        for (File f : metaFiles) {
            allItems.addAll(MetaFileUtils.readMetaFile(f));
        }

        // Apply MIME-filter if specified
        List<MetaItem> filtered = allItems.stream()
                .filter(item -> mimeFilter.isEmpty() || mimeFilter.contains(MimeUtils.getMajorType(item.mimeType())))
                .collect(Collectors.toList());

        // Group by hash and major MIME type
        Map<String, List<MetaItem>> groups = filtered.stream()
                .collect(Collectors.groupingBy(
                        item -> item.hash() + ":" + MimeUtils.getMajorType(item.mimeType()),
                        LinkedHashMap::new,
                        Collectors.toList()
                ));

        // Preview and list each group
        for (Map.Entry<String, List<MetaItem>> entry : groups.entrySet()) {
            String[] parts = entry.getKey().split(":", 2);
            String hash = parts[0];
            List<MetaItem> group = entry.getValue();
            int count = group.size();

            // Print group header: count, hash, full MIME type
            MetaItem exemplar = group.get(0);
            String fullMime = exemplar.mimeType();
            System.out.printf("GROUP : %,d : %s : %s%n", count, hash, fullMime);

            // Preview exemplar if image
            if (MimeUtils.isImage(exemplar.mimeType())) {
                new ImageViewer().view(exemplar);
            }

            // List all file paths
            for (MetaItem item : group) {
                System.out.printf("  - %s%n", item.filePath());
            }
            System.out.println();
        }

        // Summary
        int totalGroups = groups.size();
        int totalItems = filtered.size();
        System.out.println("SUMMARY");
        System.out.printf("  Groups: %d%n", totalGroups);
        System.out.printf("  Items : %d%n", totalItems);
    }
}
