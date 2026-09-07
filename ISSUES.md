# Code Quality Issues

This document records maintainability, reliability, and cleanup findings from a
source review. It is not a release plan; priorities indicate the recommended
order for addressing the items.

## Priority definitions

- **P1:** Security, data-integrity, or reliability risk that should be addressed
  before regular use or expansion.
- **P2:** Important correctness or maintainability issue that increases future
  cost and should be scheduled soon.
- **P3:** Cleanup or simplification with lower immediate risk.

## Findings

1. **P1 — Move database configuration and credentials out of source.**
   `DbConsistencyProcessor` embeds the host, username, and plaintext password,
   unlike the shell scripts that use `PG*` variables. Read environment variables
   or use PostgreSQL service configuration, remove the secret from history, and
   rotate it.
   - `src/main/java/hashtools/commands/db/clean/DbConsistencyProcessor.java:26`

2. **P1 — Bound generator work and fail consistently on writer errors.**
   The fixed thread pool has an unbounded task queue, so the configured metadata
   queue does not limit memory during discovery. Writer exceptions are logged but
   not propagated, leaving workers able to block forever on the metadata queue.
   Use bounded submission or a semaphore, share fatal failures between workers,
   and cancel/shut down all executors on failure.
   - `src/main/java/hashtools/commands/generate/GenerateMetaProcessor.java:77`
   - `src/main/java/hashtools/commands/generate/GenerateMetaProcessor.java:188`

3. **P1 — Add automated tests.**
   The project has no test sources. Add temporary-directory integration tests for
   `generate`, `validate`, and `split`, plus dry-run coverage for any command or
   script that can delete files or database rows.

4. **P2 — Remove obsolete, unused code.**
   `TrashUtils`, `ValidateMetaFileProcessor`, `Config.cwd()`, and
   `MAX_RUNTIME_HOURS` have no callers. `ValidateMetaFileProcessor` also checks
   an obsolete three-column metadata format. Remove them, or integrate and test
   them if they remain planned features.
   - `src/main/java/hashtools/utils/TrashUtils.java:6`
   - `src/main/java/hashtools/commands/meta/view/ValidateMetaFileProcessor.java:7`
   - `src/main/java/hashtools/commands/generate/GenerateMetaProcessor.java:272`
   - `src/main/java/hashtools/commands/db/clean/DbConsistencyProcessor.java:34`

5. **P2 — Centralize metadata parsing and validation.**
   Several processors parse TSV records independently. In particular, summary
   silently drops lines with the wrong number of columns, while `MetaFileUtils`
   owns the canonical file format. Expose a shared streaming parser and make all
   consumers report malformed records consistently.
   - `src/main/java/hashtools/commands/meta/summary/MetaSummaryProcessor.java:57`
   - `src/main/java/hashtools/utils/MetaFileUtils.java:30`

6. **P2 — Match `meta select` filtering to its `(hash, mime_type)` grouping.**
   Reference metadata is filtered by hash only, then data is grouped by hash and
   MIME type. Build reference keys from both values so files with the same bytes
   but different MIME classifications are not selected unexpectedly.
   - `src/main/java/hashtools/commands/meta/select/MetaSelectProcessor.java:53`
   - `src/main/java/hashtools/commands/meta/select/MetaSelectProcessor.java:71`

7. **P3 — Make generator configuration immutable and separate process exit from processing.**
   `Config` is mutable even though it represents input settings, and processing
   methods call `System.exit`. Convert configuration to an immutable record and
   let the CLI translate exceptions or result codes into process exit status.
   This makes unit and integration testing substantially easier.
   - `src/main/java/hashtools/commands/generate/GenerateMetaProcessor.java:127`
   - `src/main/java/hashtools/commands/generate/GenerateMetaProcessor.java:251`

8. **P3 — Report actual purge results.**
   `meta purge` reports all matches as deleted even in dry-run mode or after a
   failed deletion. Track and display matched, deleted, missing, and failed
   counts separately.
   - `src/main/java/hashtools/commands/meta/purge/MetaPurgeProcessor.java:102`

9. **P3 — Resolve ShellCheck findings and simplify shell preview routing.**
   `safe-move.bash` has array/glob expansion warnings, preview helpers reference
   variables ShellCheck considers unset, and the later `image/svg+xml` case is
   unreachable because `image/*` matches first. Remove redundant branches and
   make function inputs explicit.
   - `bin/safe-move.bash:41`
   - `bin/preview_helpers.bash:21`
   - `bin/preview.bash:269`

## Feature Gaps

1. **P1 — Configurable database connectivity.**
   Centralize `PG*` environment-variable or PostgreSQL service-file support for
   every Java command and shell script. The consistency command embeds connection
   details, while script defaults are inconsistent.
   - `src/main/java/hashtools/commands/db/clean/DbConsistencyProcessor.java:26`
   - `bin/truncate_hashes_table.bash:12`

2. **P1 — Recoverable deletion workflow.**
   Add a shared quarantine, deletion manifest, confirmation step, rollback path,
   and coordinated filesystem/database handling for destructive operations.

3. **P1 — Database migrations.**
   Replace destructive schema initialization with versioned migrations, upgrade
   checks, and backup preflight behavior.
   - `sql/core-2-tables.sql:15`

4. **P2 — Incremental scanning.**
   Add a persistent scan cache keyed by path, size, modification time, and digest
   so repeated scans do not hash every unchanged file.

5. **P2 — More complete scan filters.**
   Support include/exclude path globs, ignored directories, extension filters,
   size limits, and an explicit symlink policy in addition to major MIME filters.
   - `src/main/java/hashtools/commands/generate/GenerateCommand.java:39`

6. **P2 — Configurable digests and metadata versioning.**
   Add SHA-256 support and an explicit metadata schema/version and digest
   algorithm field, rather than treating SHA-1 as an implicit fixed format.
   - `src/main/java/hashtools/utils/DigestUtils.java:10`

7. **P2 — Safe import and scan provenance.**
   Add pre-import validation, a staging/import report, idempotent upsert behavior,
   scan-run provenance, and actionable conflict handling.
   - `bin/load_hashes.bash:35`

8. **P2 — General duplicate-query CLI.**
   Provide supported CLI queries for duplicate groups by path, size, MIME
   category, age, and base-path priority instead of relying on fixed SQL and
   machine-specific scripts.

9. **P3 — Complete media-preview support.**
   Expose consistent image, audio, and video preview behavior through the Java
   CLI instead of relying on shell helpers for non-image media.
   - `src/main/java/hashtools/viewers/ImageViewer.java:28`

10. **P3 — Executable vault-repair workflow.**
    Implement or remove the obsolete command names in `bin/TODO.txt`, including
    `fix-unvaulted-primaries.bash` and `viewById.bash`.
    - `bin/TODO.txt:14`

11. **P3 — Machine-independent vault configuration.**
    Replace fixed vault paths with a configuration file or consistent command
    arguments for every vault-aware script and SQL query.
    - `bin/purge-dupes-of-vault.bash:48`

12. **P3 — CI and reproducible test fixtures.**
    Add automated tests and a small fixture corpus/database so Java, SQL, and
    shell workflows can be verified together.
