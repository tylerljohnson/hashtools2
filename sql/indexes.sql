-- ===========================
-- Drop and Rebuild Indexes
-- ===========================

-- Drop existing indexes (ignore errors if not present)
DO $$
BEGIN
    EXECUTE 'DROP INDEX IF EXISTS idx_hashes_hash;';
    EXECUTE 'DROP INDEX IF EXISTS idx_hashes_mime_type;';
    EXECUTE 'DROP INDEX IF EXISTS idx_hashes_last_modified;';
    EXECUTE 'DROP INDEX IF EXISTS idx_hashes_bp_hash_mime_time_id;';
    EXECUTE 'DROP INDEX IF EXISTS idx_hashes_hash_mime_time_id;';
END$$;

-- Recreate indexes
CREATE INDEX idx_hashes_hash ON hashes (hash);
CREATE INDEX idx_hashes_mime_type ON hashes (mime_type);
CREATE INDEX idx_hashes_last_modified ON hashes (last_modified);
CREATE INDEX idx_hashes_bp_hash_mime_time_id
  ON hashes (base_path, hash, mime_type, last_modified, id);
CREATE INDEX idx_hashes_hash_mime_time_id
  ON hashes (hash, mime_type, last_modified, id);
