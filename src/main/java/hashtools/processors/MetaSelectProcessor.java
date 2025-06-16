package hashtools.processors;

import hashtools.models.*;
import hashtools.utils.*;
import hashtools.viewers.*;

import java.io.*;
import java.nio.file.*;
import java.nio.file.attribute.*;
import java.util.*;
import java.util.stream.Collectors;

public class MetaSelectProcessor implements Processor {

    private final File referenceFile;
    private final File[] dataFiles;
    private final Set<String> mimeFilter;
    private final boolean pathsOnly;
    private final boolean view;
    private final boolean summary;
    private final File copyDir;
    private final MetaItemSelector selector;

    // Track selected and unselected items
    private Set<MetaItem> selectedItems = new LinkedHashSet<>();
    private Set<MetaItem> unselectedItems = new LinkedHashSet<>();

    public MetaSelectProcessor(File referenceFile,
                               File[] dataFiles,
                               Set<String> mimeFilter,
                               boolean pathsOnly,
                               boolean view,
                               boolean summary,
                               File copyDir) {
        this.referenceFile = referenceFile;
        this.dataFiles = dataFiles;
        this.mimeFilter = mimeFilter != null ? mimeFilter : Collections.emptySet();
        this.pathsOnly = pathsOnly;
        this.view = view;
        this.summary = summary;
        this.copyDir = copyDir;
        this.selector = new MetaItemSelector();
    }

    @Override
    public void run() {
        // Load reference hashes
        List<MetaItem> referenceItems = MetaFileUtils.readMetaFile(referenceFile);
        Set<String> referenceHashes = referenceItems.stream()
                .map(MetaItem::hash)
                .collect(Collectors.toSet());

        // Load all data items
        List<MetaItem> dataItems = new ArrayList<>();
        for (File f : dataFiles) {
            dataItems.addAll(MetaFileUtils.readMetaFile(f));
        }

        // Filter by reference and MIME filter
        List<MetaItem> filtered = dataItems.stream()
                .filter(item -> referenceHashes.contains(item.hash()))
                .filter(item -> mimeFilter.isEmpty() || mimeFilter.contains(MimeUtils.getMajorType(item.mimeType())))
                .collect(Collectors.toList());

        selectedItems.clear();

        // Group by hash:mimeType
        Map<String, List<MetaItem>> groups = filtered.stream()
                .collect(Collectors.groupingBy(
                        item -> item.hash() + ":" + item.mimeType(),
                        LinkedHashMap::new,
                        Collectors.toList()
                ));

        long totalSelectedSize = 0L;

        // Process each group
        for (List<MetaItem> group : groups.values()) {
            MetaItem best = selector.select(group);
            selectedItems.add(best);
            totalSelectedSize += best.fileSize();

            Path original = Paths.get(best.basePath(), best.filePath());

            // Preview if requested
            if (!pathsOnly && view && MimeUtils.isImage(best.mimeType())) {
                new ImageViewer().view(best);
            }

            // Output
            if (pathsOnly) {
                System.out.println(original);
            }

            // Copy & verify
            if (copyDir != null) {
                if (!Files.exists(original) || !Files.isReadable(original)) {
                    throw new RuntimeException("Source file not accessible: " + original);
                }
                Path rel = original;
                if (rel.getNameCount() > 3) rel = rel.subpath(3, rel.getNameCount());
                Path dest = copyDir.toPath().resolve(rel);
                try {
                    Files.createDirectories(dest.getParent());
                    Files.copy(original, dest, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.COPY_ATTRIBUTES);
                    // Verify size
                    long srcSize = Files.size(original);
                    long dstSize = Files.size(dest);
                    FileTime srcTime = Files.getLastModifiedTime(original);
                    FileTime dstTime = Files.getLastModifiedTime(dest);
                    if (srcSize != dstSize) {
                        throw new RuntimeException(String.format(
                                "Copy verification failed for %s -> %s: size mismatch (src=%d,dst=%d)",
                                original, dest, srcSize, dstSize));
                    }
                    if (!srcTime.equals(dstTime)) {
                        throw new RuntimeException(String.format(
                                "Copy verification failed for %s -> %s: timestamp mismatch (src=%s,dst=%s)",
                                original, dest, srcTime, dstTime));
                    }
                } catch (IOException e) {
                    throw new RuntimeException("Error copying file " + original + " to " + dest + ": " + e.getMessage(), e);
                }
            }
        }

        // Determine unselected items
        unselectedItems.clear();
        unselectedItems.addAll(filtered);
        unselectedItems.removeAll(selectedItems);

        // Summary
        if (summary) {
            long totalUnselectedSize = unselectedItems.stream().mapToLong(MetaItem::fileSize).sum();
            System.out.printf("Total selected size  : %s%n", SizeUtils.humanReadable(totalSelectedSize));
            System.out.printf("Total unselected size: %s%n", SizeUtils.humanReadable(totalUnselectedSize));
        }
    }

    public Set<MetaItem> getSelectedItems() {
        return Collections.unmodifiableSet(selectedItems);
    }

    public Set<MetaItem> getUnselectedItems() {
        return Collections.unmodifiableSet(unselectedItems);
    }

    private static class MetaItemSelector {
        MetaItem select(List<MetaItem> group) {
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
