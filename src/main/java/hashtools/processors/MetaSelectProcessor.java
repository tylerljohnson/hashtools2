// src/main/java/hashtools/processors/MetaSelectProcessor.java
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
    private final File copyDir;        // may be null
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
        // 1) load reference hashes
        List<MetaItem> refItems = MetaFileUtils.readMetaFile(referenceFile);
        Set<String> refHashes = refItems.stream()
                .map(MetaItem::hash)
                .collect(Collectors.toSet());

        // 2) load all data items
        List<MetaItem> dataItems = new ArrayList<>();
        for (File f : dataFiles) {
            dataItems.addAll(MetaFileUtils.readMetaFile(f));
        }

        // 3) filter by reference & mime
        List<MetaItem> filtered = dataItems.stream()
                .filter(i -> refHashes.contains(i.hash()))
                .filter(i -> mimeFilter.isEmpty() ||
                        mimeFilter.contains(MimeUtils.getMajorType(i.mimeType())))
                .collect(Collectors.toList());

        // 4) group by hash:mimeType
        Map<String,List<MetaItem>> groups = filtered.stream()
                .collect(Collectors.groupingBy(
                        i -> i.hash() + ":" + i.mimeType(),
                        LinkedHashMap::new, Collectors.toList()
                ));

        // 5) for each group, select & output (and maybe copy)
        for (List<MetaItem> group : groups.values()) {
            MetaItem best = selector.select(group);
            Path original = Paths.get(best.basePath(), best.filePath());

            // preview
            if (!pathsOnly && view && MimeUtils.isImage(best.mimeType())) {
                new ImageViewer().view(best);
            }

            // output
            if (pathsOnly) {
                System.out.println(original);
            } else {
                System.out.printf("SELECT : %d : %s : %s%n",
                        group.size(), best.hash(), original);
            }

            // copy
            if (copyDir != null) {
                // strip first 3 segments
                Path rel = original;
                if (rel.getNameCount() > 3) {
                    rel = rel.subpath(3, rel.getNameCount());
                }
                Path dest = copyDir.toPath().resolve(rel);
                try {
                    Files.createDirectories(dest.getParent());
                    Files.copy(original, dest, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.COPY_ATTRIBUTES);
                    //System.out.printf("COPIED: %s → %s%n", original, dest);
                } catch (IOException e) {
                    System.err.printf("ERROR copying %s → %s: %s%n",
                            original, dest, e.getMessage());
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
                    .orElseThrow(() -> new IllegalArgumentException("Empty group"));
        }
    }
}
