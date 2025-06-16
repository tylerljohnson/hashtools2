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
    private final boolean summary;
    private final MetaItemSelector selector;

    // Tracks items that were selected as the best match
    private Set<MetaItem> selectedItems;
    // Tracks items that were not selected
    private Set<MetaItem> unselectedItems;

    public MetaSelectProcessor(File referenceFile,
                               File[] dataFiles,
                               Set<String> mimeFilter,
                               boolean pathsOnly,
                               boolean view,
                               boolean summary) {
        this.referenceFile = referenceFile;
        this.dataFiles = dataFiles;
        this.mimeFilter = mimeFilter != null ? mimeFilter : Collections.emptySet();
        this.pathsOnly = pathsOnly;
        this.view = view;
        this.summary = summary;
        this.selector = new MetaItemSelector();
        this.selectedItems = new LinkedHashSet<>();
        this.unselectedItems = new LinkedHashSet<>();
    }

    @Override
    public void run() {
        // Load reference items
        List<MetaItem> referenceItems = MetaFileUtils.readMetaFile(referenceFile);
        Set<String> referenceHashes = referenceItems.stream()
                .map(MetaItem::hash)
                .collect(Collectors.toSet());

        // Load data items
        List<MetaItem> dataItems = new ArrayList<>();
        for (File f : dataFiles) {
            dataItems.addAll(MetaFileUtils.readMetaFile(f));
        }

        // Filter by reference hashes and MIME filter
        List<MetaItem> filtered = dataItems.stream()
                .filter(item -> referenceHashes.contains(item.hash()))
                .filter(item -> mimeFilter.isEmpty() || mimeFilter.contains(MimeUtils.getMajorType(item.mimeType())))
                .collect(Collectors.toList());

        selectedItems.clear();

        // Group by hash and full MIME type
        Map<String, List<MetaItem>> groups = filtered.stream()
                .collect(Collectors.groupingBy(
                        item -> item.hash() + ":" + item.mimeType(),
                        LinkedHashMap::new,
                        Collectors.toList()
                ));

        long totalSize = 0L;
        // Process each group
        for (List<MetaItem> group : groups.values()) {
            MetaItem best = selector.select(group);
            selectedItems.add(best);
            totalSize += best.fileSize();

            Path fullPath = Paths.get(best.basePath(), best.filePath());

            // Preview if requested
            if (!pathsOnly && view && MimeUtils.isImage(best.mimeType())) {
                new ImageViewer().view(best);
            }

            // Output
            if (pathsOnly) {
                System.out.println(fullPath);
            } else {
                System.out.printf("SELECT : %d : %s : %s%n",
                        group.size(), best.hash(), fullPath);
            }
        }

        // Determine unselected items for future use
        unselectedItems.clear();
        unselectedItems.addAll(filtered);
        unselectedItems.removeAll(selectedItems);

        // Summary
        if (summary) {
            long unselectedSize = unselectedItems.stream()
                    .mapToLong(MetaItem::fileSize)
                    .sum();

            System.out.printf("Total selected size  : %s%n", SizeUtils.humanReadable(totalSize));
            System.out.printf("Total unselected size: %s%n", SizeUtils.humanReadable(unselectedSize));
        }
    }

    /**
     * @return an unmodifiable set of items selected as the best matches
     */
    public Set<MetaItem> getSelectedItems() {
        return Collections.unmodifiableSet(selectedItems);
    }

    /**
     * @return an unmodifiable set of items that were not selected
     */
    public Set<MetaItem> getUnselectedItems() {
        return Collections.unmodifiableSet(unselectedItems);
    }

    /**
     * Inner class encapsulating selection logic for MetaItem groups.
     */
    private static class MetaItemSelector {
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
