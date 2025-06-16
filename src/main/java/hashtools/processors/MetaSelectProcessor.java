package hashtools.processors;

import hashtools.models.MetaItem;
import hashtools.utils.MetaFileUtils;
import hashtools.utils.MimeUtils;
import hashtools.utils.SizeUtils;
import hashtools.viewers.ImageViewer;

import java.io.File;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.*;
import java.util.stream.Collectors;

public class MetaSelectProcessor implements Processor {

    private final File referenceFile;
    private final File[] dataFiles;
    private final Set<String> mimeFilter;
    private final boolean pathsOnly;
    private final boolean view;
    private final boolean summary;
    private final MetaItemSelector selector;

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
    }

    @Override
    public void run() {
        // Load reference hashes
        List<MetaItem> refItems = MetaFileUtils.readMetaFile(referenceFile);
        Set<String> refHashes = refItems.stream()
                .map(MetaItem::hash)
                .collect(Collectors.toSet());

        // Load data items
        List<MetaItem> dataItems = new ArrayList<>();
        for (File f : dataFiles) {
            dataItems.addAll(MetaFileUtils.readMetaFile(f));
        }

        // Filter by reference and MIME
        List<MetaItem> filtered = dataItems.stream()
                .filter(i -> refHashes.contains(i.hash()))
                .filter(i -> mimeFilter.isEmpty() || mimeFilter.contains(MimeUtils.getMajorType(i.mimeType())))
                .collect(Collectors.toList());

        // Group by hash and full MIME
        Map<String, List<MetaItem>> groups = filtered.stream()
                .collect(Collectors.groupingBy(
                        i -> i.hash() + ":" + i.mimeType(),
                        LinkedHashMap::new,
                        Collectors.toList()
                ));

        long totalSize = 0L;
        // Process each group
        for (List<MetaItem> group : groups.values()) {
            MetaItem best = selector.select(group);
            Path fullPath = Paths.get(best.basePath(), best.filePath());
            totalSize += best.fileSize();

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

        // Summary
        if (summary) {
            System.out.printf("Total selected size: %s%n", SizeUtils.humanReadable(totalSize));
        }
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
