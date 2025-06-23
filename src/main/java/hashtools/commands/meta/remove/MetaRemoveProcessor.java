package hashtools.commands.meta.remove;

import hashtools.commands.*;
import hashtools.models.*;
import hashtools.utils.*;

import java.io.*;
import java.nio.file.*;
import java.time.*;
import java.time.format.*;
import java.util.*;
import java.util.stream.*;

/**
 * Processor for the "meta remove" subcommand.
 *
 * For each provided target file or directory, it locates the corresponding
 * MetaItem(s) in the reference meta file, then logs all other entries sharing
 * the same hash and MIME type for removal.  Entries not found in the meta
 * file are logged with status NO_META.  When debug=true, prints detailed
 * grouping info to stdout.
 */
public class MetaRemoveProcessor implements Processor {

    private static final DateTimeFormatter LOG_FMT =
            DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss");

    private enum RemovalStatus { NO_META, DELETE, NOT_FOUND }

    private final File   referenceMeta;
    private final File[] targets;
    private final boolean debug;
    private final boolean info = false; // always print info messages

    /**
     * @param referenceMeta  the .meta file to read entries from
     * @param targets        one-or-more absolute files or directories to process
     * @param debug          if true, print debug info about grouping and matching
     */
    public MetaRemoveProcessor(File referenceMeta, File[] targets, boolean debug) {
        this.referenceMeta = referenceMeta;
        this.targets       = targets;
        this.debug         = debug;
    }

    @Override
    public void run() {
        // 1) Load and index
        debug("Loading reference meta: %s", referenceMeta);
        List<MetaItem> items = MetaFileUtils.readMetaFile(referenceMeta);

        debug("Read %,d entries from meta", items.size());
        Map<Path,MetaItem> index = indexByPath(items);

        debug("Built index with %,d paths", index.size());

        // 2) Discover target files
        debug("Discovering target files...");
        Set<Path> allTargets = collectAllTargetFiles();
        info("Found %,d target file(s)", allTargets.size());

        // 3) Match targets in the index
        Set<MetaItem> matchedEntries = new LinkedHashSet<>();
        List<String>  noMetaLines    = new ArrayList<>();

        for (Path path : allTargets) {
            debug("Looking up path: %s", path);
            MetaItem entry = index.get(path);
            if (entry != null) {
                if (debug) {
                    String key = entry.hash() + ":" + entry.mimeType();
                    debug(" → Matched meta entry, key=%s", key);
                }
                matchedEntries.add(entry);
            } else {
                debug(" → No meta entry for %s", path);
                noMetaLines.add(formatLogLine(RemovalStatus.NO_META, path));
            }
        }
        info("Matched %,d entries in meta", matchedEntries.size());

        // 4) Collect all other entries in each matched key’s group
        debug("Collecting removal candidates...");
        Set<MetaItem> toRemove = collectToRemove(items, matchedEntries);
        debug("Collected %,d entries to remove", toRemove.size());

        // 5) Write logs
        Path logPath = Paths.get(System.getProperty("user.home"), "bin", "meta-remove.log");
        debug("Writing log to %s", logPath);
        writeLogLines(logPath, noMetaLines, toRemove);

        // 6) Summary
        printSummary(matchedEntries.size(), toRemove.size(), logPath);
    }

    /** Indexes meta items by their absolute normalized filesystem path. */
    private Map<Path,MetaItem> indexByPath(List<MetaItem> items) {
        return items.stream().collect(Collectors.toMap(
                it -> Paths.get(it.basePath(), it.filePath())
                        .toAbsolutePath().normalize(),
                it -> it
        ));
    }

    /** Walks each target (file or directory) and collects all regular files. */
    private Set<Path> collectAllTargetFiles() {
        Set<Path> paths = new LinkedHashSet<>();
        for (File target : targets) {
            Path p = target.toPath().toAbsolutePath().normalize();
            try (Stream<Path> walk = Files.isDirectory(p) ? Files.walk(p) : Stream.of(p)) {
                walk.filter(Files::isRegularFile)
                        .map(Path::normalize)
                        .forEach(paths::add);
            } catch (IOException e) {
                throw new RuntimeException("Failed to walk target " + p, e);
            }
        }
        return paths;
    }

    /** Groups by hash:MIME and gathers all entries except the matched ones. */
    private Set<MetaItem> collectToRemove(List<MetaItem> items,
                                          Set<MetaItem> matchedEntries) {
        Map<String,List<MetaItem>> groups = items.stream()
                .collect(Collectors.groupingBy(
                        it -> it.hash() + ":" + it.mimeType(),
                        LinkedHashMap::new,
                        Collectors.toList()
                ));

        Set<MetaItem> toRemove = new LinkedHashSet<>();
        for (MetaItem matched : matchedEntries) {
            String key = matched.hash() + ":" + matched.mimeType();
            List<MetaItem> group = groups.getOrDefault(key, List.of());

            if (debug) {
                debug("key=%s → group size=%d", key, group.size());
                for (MetaItem member : group) {
                    debug("   member: %s/%s", member.basePath(), member.filePath());
                }
            }

            for (MetaItem member : group) {
                toRemove.add(member);
            }
        }
        return toRemove;
    }

    /** Formats a log line: timestamp, status, hash, mimetype and file path. */
    private String formatLogLine(RemovalStatus status, MetaItem item) {
        return String.format(
                "%s\t%s\t%s\t%s\t%s%n",
                LocalDateTime.now().format(LOG_FMT),
                status.name().toLowerCase(),
                item.hash(),
                item.mimeType(),
                Paths.get(item.basePath(), item.filePath())
        );
    }
    private String formatLogLine(RemovalStatus status, Path path) {
        return String.format(
                "%s\t%s\t%s%n",
                LocalDateTime.now().format(LOG_FMT),
                status.name().toLowerCase(),
                path.toAbsolutePath().normalize()
        );
    }

    /** Appends all NO_META and removal entries to the log file. */
    private void writeLogLines(Path logPath,
                               List<String> noMetaLines,
                               Set<MetaItem> toRemove) {
        try {
            Files.createDirectories(logPath.getParent());
        } catch (IOException e) {
            throw new RuntimeException("Failed to create log directory", e);
        }

        try (BufferedWriter writer = Files.newBufferedWriter(
                logPath,
                StandardOpenOption.CREATE,
                StandardOpenOption.APPEND)) {

            for (String line : noMetaLines) {
                writer.write(line);
                writer.newLine();
            }
            for (MetaItem it : toRemove) {
                Path p = Paths.get(it.basePath(), it.filePath());
                RemovalStatus status = Files.exists(p) && Files.isRegularFile(p)
                        ? RemovalStatus.DELETE
                        : RemovalStatus.NOT_FOUND;
                writer.write(formatLogLine(status, it));
                writer.newLine();
            }
        } catch (IOException e) {
            throw new RuntimeException("Failed to write log file " + logPath, e);
        }
    }

    /** Prints a concise summary of matched and to-remove counts. */
    private void printSummary(int matchedCount,
                              int removeCount,
                              Path logPath) {
        info("SUMMARY: Matched: %d  ToRemove: %d  Logged → %s", matchedCount, removeCount, logPath);
    }

    private void info(String format, Object ... args) {
        if (info) {
            out("info", format, args);
        }
    }
    private void debug(String format, Object ... args) {
        if (debug) {
            out("debug", format, args);
        }
    }
    private void out(String level, String format, Object ... args) {
        System.out.printf("[%s] %s%n", level.toUpperCase(), String.format(format, args));
    }

}
