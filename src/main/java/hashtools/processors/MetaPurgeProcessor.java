package hashtools.processors;

import hashtools.models.*;
import hashtools.utils.*;
import hashtools.utils.SizeUtils;
import hashtools.viewers.*;

import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.stream.*;

public class MetaPurgeProcessor implements Processor {

    private final File referenceFile;
    private final File targetFile;
    private final boolean delete;
    private final boolean view;
    private final boolean simple;
    private final Set<String> mimeFilter;

    public MetaPurgeProcessor(File referenceFile, File targetFile, boolean delete, boolean view, boolean simple, Set<String> mimeFilter) {
        this.referenceFile = referenceFile;
        this.targetFile = targetFile;
        this.delete = delete;
        this.view = view;
        this.simple = simple;
        this.mimeFilter = mimeFilter != null ? mimeFilter : Collections.emptySet();
    }

    @Override
    public void run() {
        // Load items
        List<MetaItem> refItems = MetaFileUtils.readMetaFile(referenceFile);
        List<MetaItem> tgtItems = MetaFileUtils.readMetaFile(targetFile);

        // Build reference hash set
        Set<String> refHashes = refItems.stream()
                .map(MetaItem::hash)
                .collect(Collectors.toSet());

        // Partition target items
        List<MetaItem> retained = new ArrayList<>();
        Map<String,List<MetaItem>> grouped = new LinkedHashMap<>();
        for (MetaItem item : tgtItems) {
            String hash = item.hash();
            // Filter by reference and optional mime
            if (refHashes.contains(hash) && (mimeFilter.isEmpty() || mimeFilter.contains(MimeUtils.getMajorType(item.mimeType())))) {
                grouped.computeIfAbsent(hash, h -> new ArrayList<>()).add(item);
            } else {
                retained.add(item);
            }
        }

        long bytesSaved = 0L;
        int refCount = refHashes.size();
        int matchedCount = 0;

        // Process each group
        for (Map.Entry<String, List<MetaItem>> e : grouped.entrySet()) {
            String hash = e.getKey();
            List<MetaItem> items = e.getValue();
            int count = items.size();
            matchedCount += count;

            if (!simple) {
                System.out.printf("MATCH : %s\t%,d%n", hash, count);
            }
            // View primary if requested
            if (view && MimeUtils.isImage(items.get(0).mimeType())) {
                new ImageViewer().view(items.get(0));
            }
            // Print each path
            for (MetaItem it : items) {
                if (simple) {
                    System.out.println(Paths.get(it.basePath(), it.filePath()));
                } else {
                    System.out.printf("  - %s%n", it.filePath());
                }
                bytesSaved += it.fileSize();
                if (delete) {
                    deleteFile(it);
                }
            }
            if (!simple) {
                System.out.println();
            }
        }

        // Summary
        if (!simple) {
            System.out.println("\nSUMMARY");
            System.out.printf("  Matched    : %d item(s) from %s using %d reference hash(es)%n",
                    matchedCount, targetFile.getName(), refCount);
            System.out.printf("  Deleted    : %d file(s)%n", matchedCount);
            System.out.printf("  Retained   : %d entry(ies)%n", retained.size());
            System.out.printf("  Space Saved: %s%n", SizeUtils.humanReadable(bytesSaved));
        }
    }

    private void deleteFile(MetaItem item) {
        try {
            Path p = Paths.get(item.basePath(), item.filePath());
            boolean removed = Files.deleteIfExists(p);
            if (!simple) System.out.printf("Deleted: %b %s%n", removed, p);
        } catch (IOException e) {
            System.err.printf("Failed to delete %s: %s%n", item.filePath(), e.getMessage());
        }
    }

}
