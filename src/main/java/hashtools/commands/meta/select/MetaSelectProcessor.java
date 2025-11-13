package hashtools.commands.meta.select;

import hashtools.commands.*;
import hashtools.models.*;
import hashtools.utils.*;
import hashtools.viewers.*;

import java.io.*;
import java.nio.file.*;
import java.nio.file.attribute.*;
import java.util.*;
import java.util.stream.*;

public class MetaSelectProcessor implements Processor {

    private final File referenceFile;
    private final File[] dataFiles;
    private final Set<String> mimeFilter;
    private final boolean pathsOnly;
    private final boolean view;
    private final boolean summary;
    private final File copyDir;
    private final boolean removeRecent;
    private final MetaItemSelector selector;

    private final Set<MetaItem> selectedItems   = new LinkedHashSet<>();
    private final Set<MetaItem> unselectedItems = new LinkedHashSet<>();

    public MetaSelectProcessor(File referenceFile,
                               File[] dataFiles,
                               Set<String> mimeFilter,
                               boolean pathsOnly,
                               boolean view,
                               boolean summary,
                               File copyDir,
                               boolean prune)
    {
        this.referenceFile  = referenceFile;
        this.dataFiles      = dataFiles;
        this.mimeFilter     = mimeFilter != null ? mimeFilter : Collections.emptySet();
        this.pathsOnly      = pathsOnly;
        this.view           = view;
        this.summary        = summary;
        this.copyDir        = copyDir;
        this.removeRecent   = prune;
        this.selector       = new MetaItemSelector();
    }

    @Override
    public void run() {
        // 1) Load reference items
        List<MetaItem> referenceItems = MetaFileUtils.readMetaFile(referenceFile);
        Set<String> referenceHashes = referenceItems.stream()
                .map(MetaItem::hash)
                .collect(Collectors.toSet());

        // 2) Load data items
        List<MetaItem> dataItems = new ArrayList<>();
        for (File f : dataFiles) {
            dataItems.addAll(MetaFileUtils.readMetaFile(f));
        }

        // 3) Filter by reference and MIME
        List<MetaItem> filtered = dataItems.stream()
                .filter(item -> referenceHashes.contains(item.hash()))
                .filter(item -> mimeFilter.isEmpty() ||
                        mimeFilter.contains(MimeUtils.getMajorType(item.mimeType())))
                .collect(Collectors.toList());

        // 4) Group by hash:mimeType
        Map<String, List<MetaItem>> groups = filtered.stream()
                .collect(Collectors.groupingBy(
                        item -> item.hash() + ":" + item.mimeType(),
                        LinkedHashMap::new,
                        Collectors.toList()
                ));

        long totalSelectedSize = 0L;
        List<Path> toDelete    = new ArrayList<>();

        // 5) Process each group
        for (List<MetaItem> group : groups.values()) {
            MetaItem best = selector.select(group);
            selectedItems.add(best);
            totalSelectedSize += best.fileSize();

            Path original = Paths.get(best.basePath(), best.filePath());

            // Preview if requested
            if (view && MimeUtils.isImage(best.mimeType())) {
                new ImageViewer().view(best);
            }

            // Output
            if (pathsOnly) {
                System.out.println(original);
            } else {
                System.out.printf("SELECT : %d : %s : %s : %s%n",
                        group.size(),
                        best.lastModified(),
                        best.hash(),
                        original);
            }

            // Copy & verify
            if (copyDir != null) {
                copyAndVerify(original);
            }

            // Schedule non-best duplicates for deletion
            if (removeRecent) {
                for (MetaItem item : group) {
                    if (!item.equals(best)) {
                        toDelete.add(Paths.get(item.basePath(), item.filePath()));
                    }
                }
            }
        }

        // 6) Collect unselected items
        unselectedItems.clear();
        filtered.forEach(unselectedItems::add);
        unselectedItems.removeAll(selectedItems);

        // 7) Perform deferred deletions
        if (removeRecent) {
            for (Path p : toDelete) {
                try {
                    boolean removed = Files.deleteIfExists(p);
                    System.out.printf("Deleted %b: %s%n", removed, p);
                } catch (IOException e) {
                    System.err.printf("ERROR deleting %s: %s%n", p, e.getMessage());
                    throw new RuntimeException("Deletion failed, aborting", e);
                }
            }
        }

        // 8) Summary
        if (summary) {
            long totalUnselectedSize = unselectedItems.stream()
                    .mapToLong(MetaItem::fileSize)
                    .sum();
            System.out.printf("Total selected size  : %s%n",
                    SizeUtils.humanReadable(totalSelectedSize));
            System.out.printf("Total unselected size: %s%n",
                    SizeUtils.humanReadable(totalUnselectedSize));
            System.out.printf("Deleted items        : %d%n",
                    toDelete.size());
        }
    }

    private void copyAndVerify(Path original) {
        try {
            if (!Files.exists(original) || !Files.isReadable(original)) {
                throw new RuntimeException("Source not accessible: " + original);
            }
            Path rel  = original.getNameCount() > 3
                    ? original.subpath(3, original.getNameCount())
                    : original.getFileName();
            Path dest = copyDir.toPath().resolve(rel);

            Files.createDirectories(dest.getParent());
            Files.copy(original, dest,
                    StandardCopyOption.REPLACE_EXISTING,
                    StandardCopyOption.COPY_ATTRIBUTES);

            // verify size & timestamp
            long srcSize    = Files.size(original);
            long dstSize    = Files.size(dest);
            FileTime srcTime= Files.getLastModifiedTime(original);
            FileTime dstTime= Files.getLastModifiedTime(dest);

            if (srcSize != dstSize) {
                throw new RuntimeException(String.format(
                        "Copy verification failed for %s → %s: size mismatch (src=%d,dst=%d)",
                        original, dest, srcSize, dstSize));
            }
            if (!srcTime.equals(dstTime)) {
                throw new RuntimeException(String.format(
                        "Copy verification failed for %s → %s: timestamp mismatch (src=%s,dst=%s)",
                        original, dest, srcTime, dstTime));
            }
        } catch (IOException e) {
            throw new RuntimeException(
                    "Error copying file " + original + ": " + e.getMessage(), e);
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
                            .thenComparing(Comparator.comparing(MetaItem::filePath).reversed()))
                    .findFirst()
                    .orElseThrow(() -> new IllegalArgumentException("Cannot select from empty group"));
        }
    }
}
