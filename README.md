# hashtools2

`hashtools2` generates SHA-1 metadata for directory trees and provides tools to
inspect metadata, identify duplicate files, and load the results into PostgreSQL
for analysis.

## Requirements

- Java 21 or newer
- Maven, to build from source
- PostgreSQL and `psql` for database workflows

The Java application uses Picocli 4.7.7, Apache Tika 3.2.3, SLF4J 2.0.17, and
the PostgreSQL JDBC driver.

## Build

```bash
mvn clean package
```

The executable shaded JAR is written to `target/hashtools2.jar`.

## CLI usage

```bash
java -jar target/hashtools2.jar --help
java -jar target/hashtools2.jar generate --help
java -jar target/hashtools2.jar meta --help
```

Generate metadata for a directory:

```bash
java -jar target/hashtools2.jar generate /path/to/directory --output=/tmp/library.meta
```

The root argument must be a directory. If the output file is inside the scanned
directory, it is excluded from the generated metadata.

Validate and summarize generated metadata:

```bash
java -jar target/hashtools2.jar meta validate /tmp/library.meta
java -jar target/hashtools2.jar meta summary /tmp/library.meta
```

The `meta` command also provides `split`, `intersect`, `purge`, `view`,
`select`, `clean`, and `remove` subcommands. Use each command's `--help` before
using it, especially commands with deletion or copy options.

## Metadata format

Metadata files are UTF-8 tab-separated records with no header:

| Column | Type | Description |
| --- | --- | --- |
| `hash` | String | Lowercase 40-character SHA-1 digest |
| `lastModified` | String | UTC ISO-8601 instant, such as `2026-09-07T21:30:35Z` |
| `fileSize` | Long | File size in bytes |
| `mimeType` | String | Detected MIME type |
| `basePath` | String | Absolute scan-root path |
| `filePath` | String | Relative path from `basePath` |

Tabs, carriage returns, and newlines are not supported in paths. Relative paths
must be nonempty, cannot start with `/`, and cannot contain `.` or `..` path
segments. Legacy metadata with local-time timestamps must be regenerated before
it can pass validation.

## Database setup

The project assumes an empty database. Set the connection variables for the
shell scripts and `psql` commands:

```bash
export PGHOST=cooper
export PGPORT=5432
export PGUSER=tyler
export PGDATABASE=tyler
```

Create the schema and reference data in this order:

```bash
psql -v ON_ERROR_STOP=1 -f sql/core-1-functions.sql
psql -v ON_ERROR_STOP=1 -f sql/core-2-tables.sql
psql -v ON_ERROR_STOP=1 -f sql/core-3-indexes.sql
psql -v ON_ERROR_STOP=1 -f sql/core-4-views.sql
psql -v ON_ERROR_STOP=1 -f sql/core-8-load-data-mime_categories.sql
```

Load one or more metadata files, then register their base paths and validate the
resulting data:

```bash
./bin/load_hashes.bash /tmp/library.meta
psql -v ON_ERROR_STOP=1 -f sql/core-7-load-data-base_paths.sql
psql -v ON_ERROR_STOP=1 -f sql/core-9-data-validation.sql
```

The `hashes` table stores the file metadata and enforces lowercase SHA-1 hashes,
nonnegative file sizes, timezone-aware timestamps, and valid metadata paths.
Its `full_path` column is generated from `base_path` and `file_path`.

The available views are:

- `files`: all tracked files with duplicate disposition and base-path metadata
- `files_primary`: the oldest entry for each `(hash, mime_type)` group
- `files_redundant`: remaining entries in each duplicate group
- `vault_timestamp_drift`: vault records whose timestamp is newer than the
  oldest matching copy

Most shell scripts use the `PGHOST`, `PGPORT`, `PGUSER`, and `PGDATABASE`
variables. The Java `db consistency` command currently has separate connection
configuration in its source and should be reviewed before use.

## Shell scripts

- `load_hashes.bash`: imports metadata into `hashes`
- `remove_redundant_files.bash`: reports redundant files by default; `--force`
  deletes files and `--sync-db` then removes their database rows
- `purge-dupes-of-vault.bash`: reports duplicates of a fixed vault path; its
  `--purge --no-dry-run` combination permanently deletes matching files
- `delete_hashes_from_missing_rows.bash`: removes database rows listed in
  `missing_rows_*.tsv`; use `--dry-run` first
- `truncate_hashes_table.bash`: empties the `hashes` table and resets its ID
  sequence
- `safe-move.bash`: moves regular files while preserving timestamps and
  metadata where supported
- `vault_timestamp_drift_fix.bash` and
  `update_last_modified_timestamps.bash`: reconcile filesystem and database
  timestamps

`gen-hashes.bash` contains machine-specific paths and a user-home JAR location;
edit it before running it. Preview scripts may require optional local tools such
as `timg`, `ffmpeg`, or `chafa`.

## Safety

Start with dry-run or reporting modes. `meta purge --delete`, `meta select
--prune`, `remove_redundant_files.bash --force`, and
`purge-dupes-of-vault.bash --purge --no-dry-run` can permanently remove files.
Review their output and ensure backups exist before executing them.

## Tests

The project currently has no automated test sources. Build verification runs
with:

```bash
mvn test
```
