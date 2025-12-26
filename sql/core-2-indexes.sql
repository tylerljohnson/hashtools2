-- ==============================================================================
-- CORE SCHEMA OVERVIEW
-- ==============================================================================
-- This script initializes the central 'hashes' table and its supporting views.
--
-- 2. INDEXES:
--    - Optimized for hash lookups, MIME-type filtering, and date sorting.
--    - Includes covering indexes to support high-performance window functions.
--
-- ==============================================================================

-- ==================================================
-- Drop and Rebuild Indexes
-- ==================================================


-- Drop existing indexes (ignore errors if not present)
DO
$$
    BEGIN
        EXECUTE 'DROP INDEX IF EXISTS idx_hashes_hash;';
        EXECUTE 'DROP INDEX IF EXISTS idx_hashes_mime_type;';
        EXECUTE 'DROP INDEX IF EXISTS idx_hashes_last_modified;';
        EXECUTE 'DROP INDEX IF EXISTS idx_hashes_bp_hash_mime_time_id;';
        EXECUTE 'DROP INDEX IF EXISTS idx_hashes_hash_mime_time_id;';
        EXECUTE 'DROP INDEX IF EXISTS idx_hashes_covering_window;';
    END
$$;

CREATE INDEX idx_hashes_hash ON hashes (hash);
CREATE INDEX idx_hashes_mime_type ON hashes (mime_type);
CREATE INDEX idx_hashes_last_modified ON hashes (last_modified);
CREATE INDEX idx_hashes_bp_hash_mime_time_id
    ON hashes (base_path, hash, mime_type, last_modified, id);
CREATE INDEX idx_hashes_hash_mime_time_id
    ON hashes (hash, mime_type, last_modified, id);
CREATE INDEX idx_hashes_covering_window
    ON hashes (hash, mime_type, last_modified, id, file_size, full_path);
