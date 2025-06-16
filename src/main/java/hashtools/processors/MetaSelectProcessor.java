package hashtools.processors;

import hashtools.models.MetaItem;
import hashtools.utils.MetaFileUtils;
import hashtools.utils.MimeUtils;
import hashtools.viewers.ImageViewer;

import java.io.File;
import java.io.IOException;
import java.nio.file.*;
import java.util.*;
import java.util.stream.Collectors;

public class MetaSelectProcessor implements Processor {

    private final File referenceFile;
    private final File[] dataFiles;
    private final Set<String> mimeFilter;
    private final boolean pathsOnly;
    private final boolean view;
    private final File copyDir;
    private final MetaItemSelector selector;

    public MetaSelectProcessor(File referenceFile,
                               File[] dataFiles,
                               Set<String> mimeFilter,
                               boolean pathsOnly,
                               boolean view,
                               File copyDir) {
        this.referenceFile = referenceFile;
        this.dataFiles     = dataFiles;
        this.mimeFilter    = mimeFilter != null ? mimeFilter : Collections.emptySet();
        this.pathsOnly     = pathsOnly;
        this.view          = view;
        this.copyDir       = copyDir;
        this.selector      = new MetaItemSelector();
    }

    @Override
    public void run() {
        // Load reference hashes
        List<MetaItem> refItems = MetaFileUtils.readMetaFile(referenceFile);
        Set<String> refHashes = refItems.stream()
                .map(MetaItem::hash)
                .collect(Collectors.toSet());

        // Load and filter data items
        List<MetaItem> filtered = Arrays.stream(dataFiles)
                .flatMap(f -> MetaFileUtils.readMetaFile(f).stream())
                .filter(i -> refHashes.contains(i.hash()))
                .filter(i -> mimeFilter.isEmpty() || mimeFilter.contains(MimeUtils.getMajorType(i.mimeType())))
                .collect(Collectors.toList());

        // Group by hash and full MIME type
        Map<String, List<MetaItem>> groups = filtered.stream()
                .collect(Collectors.groupingBy(
                        i -> i.hash() + ":" + i.mimeType(),
                        LinkedHashMap::new,
                        Collectors.toList()
                ));

        // Process each group
        for (List<MetaItem> group : groups.values()) {
            MetaItem best = selector.select(group);
            Path original = Paths.get(best.basePath(), best.filePath());

            // Preview if requested
            if (!pathsOnly && view && MimeUtils.isImage(best.mimeType())) {
                new ImageViewer().view(best);
            }

            // Output
            if (pathsOnly) {
                System.out.println(original);
            } else {
                System.out.printf("SELECT : %d : %s : %s%n",
                        group.size(), best.hash(), original);
            }

            // Copy if requested
            if (copyDir != null) {
                if (!Files.exists(original) || !Files.isReadable(original)) {
                    System.err.printf("ERROR: Source not accessible: %s%n", original);
                } else {
                    Path rel = original;
                    if (rel.getNameCount() > 3) {
                        rel = rel.subpath(3, rel.getNameCount());
                    }
                    Path dest = copyDir.toPath().resolve(rel);
                    try {
                        Files.createDirectories(dest.getParent());
                        Files.copy(original, dest,
                                StandardCopyOption.REPLACE_EXISTING,
                                StandardCopyOption.COPY_ATTRIBUTES);
                    } catch (IOException e) {
                        System.err.printf("ERROR copying %s → %s: %s%n",
                                original, dest, e.getMessage());
                    }
                }
            }
        }
    }

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
