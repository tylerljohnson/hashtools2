-- ==============================================================================
-- indexes.sql
--
-- Purpose:
--   Drops prior/legacy indexes (if present) and recreates the recommended index
--   set for the current schema:
--     - hashes + files/vault_timestamp_drift view windowing
--     - base_paths vault selection by priority
--     - common access patterns (time-range scans, per-base_path work)
--
-- Notes:
--   - The UNIQUE(full_path) constraint on hashes already creates an index.
--   - base_paths PRIMARY KEY (base_path) already creates an index.
-- ==============================================================================

BEGIN;

-- ------------------------------------------------------------------------------
-- Drop legacy/redundant indexes (safe no-ops if they don't exist)
-- ------------------------------------------------------------------------------

DROP INDEX IF EXISTS base_paths_is_vault_idx;
DROP INDEX IF EXISTS idx_hashes_hash;
DROP INDEX IF EXISTS idx_hashes_mime_type;
DROP INDEX IF EXISTS idx_hashes_last_modified;
DROP INDEX IF EXISTS idx_hashes_bp_hash_mime_time_id;
DROP INDEX IF EXISTS idx_hashes_hash_mime_time_id;
DROP INDEX IF EXISTS idx_hashes_covering_window;

-- If you created other variants over time, add them here:
-- DROP INDEX IF EXISTS idx_hashes_window;
-- DROP INDEX IF EXISTS idx_hashes_basepath_window;
-- DROP INDEX IF EXISTS idx_base_paths_vault_priority;

-- ------------------------------------------------------------------------------
-- Create recommended indexes
-- ------------------------------------------------------------------------------

-- 1) Core windowing support for both views:
--    PARTITION BY (hash, mime_type) with ORDER BY (last_modified, id)
--    INCLUDE covers the columns frequently projected by the views.
CREATE INDEX IF NOT EXISTS idx_hashes_window
    ON hashes (hash, mime_type, last_modified, id)
    INCLUDE (file_size, base_path, file_path, full_path);

-- 2) Fast selection of vault base_paths in priority order
CREATE INDEX IF NOT EXISTS idx_base_paths_vault_priority
    ON base_paths (is_vault, priority, base_path);

-- 3) Common access pattern: time-range scans
CREATE INDEX IF NOT EXISTS idx_hashes_last_modified
    ON hashes (last_modified);

-- 4) Common access pattern: queries constrained to a specific base_path
CREATE INDEX IF NOT EXISTS idx_hashes_basepath_window
    ON hashes (base_path, hash, mime_type, last_modified, id);

-- 5) Common access pattern: queries constrained to a specific mime_type
CREATE INDEX mime_category_category_idx ON mime_category (category);

COMMIT;