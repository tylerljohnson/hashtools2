
# Archive Management Script Design

## Purpose
Design a script to manage a canonical archive location that stores the primary (oldest) version of each unique file.

## Core Concepts

### File Uniqueness
- A file is uniquely identified by the combination of:
  - SHA-1 hash
  - MIME type

### Primary vs Redundant Files
- **Primary File**: For each unique hash+mime_type combination, the file with the strictly oldest last_modified date
- **Redundant Files**: All files with the same hash+mime_type combination but newer timestamps
- All files in the archive location should be primary versions
- If a file in the archive is redundant, it means its primary version exists elsewhere and needs timestamp adjustment

### Archive Location
- There is exactly one archive location in the system
- The archive is identified by an exact `base_path` string match in the `hashes` table
- The script must know this base_path value to identify archive files
- This value must match EXACTLY what was used when generating hashes
- Serves as the canonical storage location for primary files
- Should contain the oldest version of each unique file
- Other `base_path` values in the database represent source/working locations

For example, if files were added to the database using:
```bash
java -jar hashtools2.jar generate /Volumes/archive --output=archive.hashes
```
Then the archive base_path must be exactly `/Volumes/archive` in the script configuration.

## Script Design

A single script (`archive-manager.bash`) that handles both identification and resolution of archive issues. By default, it operates in a read-only mode that lists files requiring attention. When the `--fix` flag is provided, it performs the necessary timestamp adjustments.

### Core Functionality

#### Problem Definition
Find files where:
1. The file is marked as 'primary' (oldest copy)
2. The file is NOT in the archive location
3. A redundant (newer) copy EXISTS in the archive location
4. Both copies have the same hash and mime_type

#### Chosen Query Approach

We use a concise EXISTS-based query to find primary files that have a redundant copy in the archive. This is clear, efficient with proper indexes, and easy to extend with additional filters.

```sql
SELECT *
FROM files f
WHERE f.disposition = 'primary'
  AND f.base_path != :archive_base_path
  AND EXISTS (
    SELECT 1
    FROM files a
    WHERE a.base_path = :archive_base_path
      AND a.hash = f.hash
      AND a.mime_type = f.mime_type
      AND a.disposition = 'redundant'
  );
```

#### Output Format
TSV format with headers:
```
hash    mime_type    primary_path    primary_modified    archive_path    archive_modified
```

The script operates in two modes: list (default) and fix (`--fix`) which performs timestamp synchronization.

#### Required Indexes
```sql
CREATE INDEX IF NOT EXISTS idx_files_hash_mime 
  ON files(hash, mime_type);
CREATE INDEX IF NOT EXISTS idx_files_base_path 
  ON files(base_path);
CREATE INDEX IF NOT EXISTS idx_files_disposition 
  ON files(disposition);
```

### Single-script final design

We consolidate into a single, idempotent `archive-manager.bash` that performs both listing and fix operations. The script uses the timestamp-synchronization strategy for pairs (primary + redundant in archive) and relies on the chosen SQL query to enumerate candidates.

#### Safety and Recovery

High-level safety and recovery measures (kept intentionally high-level here):

- Pre-operation verification: input validation, permission checks, resource and DB connectivity checks.
- Atomic and verifiable operations: each file-pair operation should be testable, reversible, and logged.
- Transactional DB updates: when updating metadata in the database, use transactions and rollbacks on failure.
- Progress tracking and state: record completed operations to support resume and auditing.
- Dry-run mode and confirmation prompts: allow operators to preview changes before applying them.

These measures are described at a high level here; implementation details (exact logging format, progress bar UI, specific rollback commands) are left to the script implementation.

## Implementation Considerations

### Database Integration
- Utilize existing `hashes` table and views
- System recognizes exactly one archive location among all base_paths
- Query structure for finding primary files not in archive:
  ```sql
  SELECT *
  FROM files f
  WHERE f.disposition = 'primary'
    AND f.base_path != :archive_path
    AND EXISTS (
      SELECT 1
      FROM files a
      WHERE a.base_path = :archive_path
        AND a.hash = f.hash
        AND a.mime_type = f.mime_type
        AND a.disposition = 'redundant'
    );
  ```
- Query for finding redundant files incorrectly in archive:
  ```sql
  SELECT *
  FROM files f
  WHERE f.base_path = :archive_path
    AND f.disposition = 'redundant';
  ```

### Safety Features
- Dry-run mode (show proposed changes without executing)
- Verification of file integrity after moves
- Preservation of timestamps and metadata
- Confirmation prompts for significant operations

### Script Parameters
```bash
archive-manager.bash [options]
  --dry-run            # Optional: Show what would be done
  --force              # Optional: Skip confirmation prompts
  --stats              # Optional: Show archive statistics
  --verify             # Optional: Verify archive integrity
```

The archive path is configured through environment variable or config file, not as a command-line parameter, since there is only one archive location in the system.

### Integration Points
- Use `safe-move.bash` for file operations
- Leverage existing views for primary/redundant classification
- Update database after successful moves

## Example Workflow

1. List files needing attention:
   ```bash
   # Basic listing
   ./archive-manager.bash
   
   # Detailed listing with statistics
   ./archive-manager.bash --format=json --stats
   ```

2. Review and fix issues:
   ```bash
   # Show what would be fixed
   ./archive-manager.bash --fix --dry-run
   
   # Fix issues with confirmation prompts
   ./archive-manager.bash --fix
   
   # Fix issues without prompts
   ./archive-manager.bash --fix --force
   ```

3. Verify changes:
   ```bash
   # Check that no issues remain
   ./archive-manager.bash --stats
   ```

The archive is identified by its exact base_path value from the database:
```bash
# Must match exactly what was used when generating hashes
export ARCHIVE_BASE_PATH=/Volumes/archive  # This value appears in hashes.base_path
```

## Future Enhancements
- Archive space management
- Automatic periodic verification
- Archive replication support
- Batch operation mode for large archives
- Integration with backup systems
