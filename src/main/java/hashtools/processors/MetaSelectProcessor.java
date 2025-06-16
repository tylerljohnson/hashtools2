package hashtools.processors;

import hashtools.models.*;
import hashtools.utils.*;
import hashtools.viewers.*;

import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.stream.*;

public class MetaSelectProcessor implements Processor {

    private final File referenceFile;
    private final File[] dataFiles;
    private final Set<String> mimeFilter;
    private final boolean pathsOnly;
    private final boolean view;
    private final MetaItemSelector selector;

    public MetaSelectProcessor(File referenceFile,
                               File[] dataFiles,
                               Set<String> mimeFilter,
                               boolean pathsOnly,
                               boolean view) {
        this.referenceFile = referenceFile;
        this.dataFiles = dataFiles;
        this.mimeFilter = mimeFilter != null ? mimeFilter : Collections.emptySet();
        this.pathsOnly = pathsOnly;
        this.view = view;
        this.selector = new MetaItemSelector();
    }

    @Override
    public void run() {
        // Load reference hashes
        List<MetaItem> referenceItems = MetaFileUtils.readMetaFile(referenceFile);
        Set<String> referenceHashes = referenceItems.stream()
                .map(MetaItem::hash)
                .collect(Collectors.toSet());

        // Load data items
        List<MetaItem> dataItems = new ArrayList<>();
        for (File f : dataFiles) {
            dataItems.addAll(MetaFileUtils.readMetaFile(f));
        }

        // Filter by reference hashes and optional MIME filter
        List<MetaItem> filtered = dataItems.stream()
                .filter(item -> referenceHashes.contains(item.hash()))
                .filter(item -> mimeFilter.isEmpty() || mimeFilter.contains(MimeUtils.getMajorType(item.mimeType())))
                .collect(Collectors.toList());

        // Group by hash and full MIME type
        Map<String, List<MetaItem>> groups = filtered.stream()
                .collect(Collectors.groupingBy(
                        item -> item.hash() + ":" + item.mimeType(),
                        LinkedHashMap::new,
                        Collectors.toList()
                ));

        // Select best item per group and output
        for (List<MetaItem> group : groups.values()) {
            MetaItem best = selector.select(group);
            Path fullPath = Paths.get(best.basePath(), best.filePath());

            if (!pathsOnly && view && MimeUtils.isImage(best.mimeType())) {
                new ImageViewer().view(best);
            }

            if (pathsOnly) {
                System.out.println(fullPath);
            } else {
                System.out.printf("SELECT : %d : %s : %s%n",
                        group.size(), best.hash(), fullPath);
            }
        }
    }

    /**
     * Inner class encapsulating selection logic for MetaItem groups.
     */
    private static class MetaItemSelector {
        /**
         * Selects the best MetaItem from the group, sorted by:
         * 1. lastModified ascending (oldest first)
         * 2. basePath descending
         * 3. filePath descending
         */
        public MetaItem select(List<MetaItem> group) {
            return group.stream()
                    .sorted(Comparator
                            .comparing(MetaItem::lastModified)
                            .thenComparing(Comparator.comparing(MetaItem::basePath).reversed())
                            .thenComparing(Comparator.comparing(MetaItem::filePath).reversed())
                    )
                    .findFirst()
                    .orElseThrow(() -> new IllegalArgumentException("Cannot select from empty group"));
        }
    }
}
