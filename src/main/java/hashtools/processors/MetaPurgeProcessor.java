package hashtools.processors;

import hashtools.models.*;
import hashtools.utils.*;
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

    public MetaPurgeProcessor(File referenceFile, File targetFile, boolean delete, boolean view, boolean simple) {
        this.referenceFile = referenceFile;
        this.targetFile = targetFile;
        this.delete = delete;
        this.view = view;
        this.simple = simple;
    }

    @Override
    public void run() {
        try {
            List<MetaItem> referenceItems = MetaFileUtils.readMetaFile(referenceFile);
            List<MetaItem> targetItems = MetaFileUtils.readMetaFile(targetFile);

            Set<String> referenceHashes = referenceItems.stream()
                    .map(MetaItem::hash)
                    .collect(Collectors.toSet());

            List<MetaItem> retained = new ArrayList<>();
            List<MetaItem> removed = new ArrayList<>();

            Map<String, List<MetaItem>> groupedMatches = new LinkedHashMap<>();
            for (MetaItem item : targetItems) {
                if (referenceHashes.contains(item.hash())) {
                    groupedMatches.computeIfAbsent(item.hash(), k -> new ArrayList<>()).add(item);
                } else {
                    retained.add(item);
                }
            }

            long bytesSaved = 0;
            for (Map.Entry<String, List<MetaItem>> entry : groupedMatches.entrySet()) {
                String hash = entry.getKey();
                List<MetaItem> items = entry.getValue();

                if (!simple) {
                    System.out.printf("MATCH  : %s\t%,d%n", hash, items.size());
                }
                if (view && MimeUtils.isImage(items.get(0).mimeType())) {
                    new ImageViewer().view(items.get(0));
                }
                for (MetaItem item : items) {
                    if (simple) {
                        System.out.println(Paths.get(item.basePath(), item.filePath()));
                    } else {
                        System.out.printf("  - %s%n", item.filePath());
                    }
                }
                if (!simple) {
                    System.out.println();
                }
                for (MetaItem item : items) {
                    removed.add(item);
                    bytesSaved += item.fileSize();
                    if (delete) {
                        deleteFile(item);
                    }
                }
            }

            if (delete) {
                Path backupPath = MetaFileUtils.backupMetaFile(targetFile);
                MetaFileUtils.writeMetaFile(targetFile.toPath(), retained);
                if (!simple) {
                    System.out.printf("Backed up target to %s%n", backupPath);
                }
            }

            if (!simple) {
                System.out.println("\nSUMMARY");
                System.out.printf("  Matched    : %d item(s) from %s using %d reference hash(es)%n",
                        removed.size(), targetFile.getName(), referenceHashes.size());
                System.out.printf("  Deleted    : %d file(s)%n", removed.size());
                System.out.printf("  Retained   : %d entry(ies)%n", retained.size());
                System.out.printf("  Space Saved: %s%n", SizeUtils.humanReadable(bytesSaved));
            }
        } catch (IOException e) {
            throw new RuntimeException("Failed to purge meta file: " + e.getMessage(), e);
        }
    }

    private void deleteFile(MetaItem item) {
        try {
            Path path = Paths.get(item.basePath(), item.filePath());
            Files.deleteIfExists(path);
            System.out.printf("Deleted: %s%n", item.filePath());
        } catch (IOException e) {
            System.err.printf("Failed to delete %s: %s%n", item.filePath(), e.getMessage());
        }
    }
}
