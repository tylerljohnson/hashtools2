package hashtools.commands.meta.view;

import hashtools.commands.*;
import hashtools.models.*;
import hashtools.utils.*;
import hashtools.viewers.*;

import java.io.*;
import java.util.*;
import java.util.stream.*;

public class MetaViewProcessor implements Processor {
    private final File[] metaFiles;
    private final Set<String> mimeFilter;
    private final boolean view;
    private final boolean noUnique;

    public MetaViewProcessor(File[] metaFiles,
                             Set<String> mimeFilter,
                             boolean view,
                             boolean noUnique) {
        this.metaFiles  = metaFiles;
        this.mimeFilter = mimeFilter != null ? mimeFilter : Collections.emptySet();
        this.view       = view;
        this.noUnique   = noUnique;
    }

    @Override
    public void run() {
        // 1) Load all items
        List<MetaItem> allItems = new ArrayList<>();
        for (File f : metaFiles) {
            allItems.addAll(MetaFileUtils.readMetaFile(f));
        }

        // 2) Apply MIME filter
        List<MetaItem> filtered = allItems.stream()
                .filter(item -> mimeFilter.isEmpty()
                        || mimeFilter.contains(MimeUtils.getMajorType(item.mimeType())))
                .collect(Collectors.toList());

        // 3) Group by hash + major MIME type
        Map<String, List<MetaItem>> groups = filtered.stream()
                .collect(Collectors.groupingBy(
                        item -> item.hash() + ":" + MimeUtils.getMajorType(item.mimeType()),
                        LinkedHashMap::new,
                        Collectors.toList()
                ));

        // 4) Preview and list each group
        for (Map.Entry<String,List<MetaItem>> e : groups.entrySet()) {
            List<MetaItem> group = e.getValue();
            if (noUnique && group.size() < 2) {
                // skip groups with less than 2 items when --no-unique
                continue;
            }

            String[] parts = e.getKey().split(":", 2);
            String hash    = parts[0];
            int count      = group.size();

            // a) Header
            MetaItem exemplar = group.get(0);
            String fullMime = exemplar.mimeType();
            System.out.printf("GROUP : %,d : %s : %s%n", count, hash, fullMime);

            // b) Preview if requested
            if (view && MimeUtils.isImage(exemplar.mimeType())) {
                new ImageViewer().view(exemplar);
            }

            // c) Sort & list members
            group.sort(Comparator
                    .comparing(MetaItem::lastModified)
                    .thenComparing(MetaItem::basePath)
                    .thenComparing(MetaItem::filePath)
            );
            for (MetaItem item : group) {
                System.out.printf("  - %s : %s/%s%n",
                        item.lastModified(),
                        item.basePath(),
                        item.filePath());
            }
            System.out.println();
        }

        // 5) Summary
        System.out.println("SUMMARY");
        System.out.printf("  Groups: %d%n", groups.size());
        System.out.printf("  Items : %d%n", filtered.size());
    }
}
