-- ==============================================================================
-- CORE SCHEMA OVERVIEW
-- ==============================================================================
-- This script initializes the central 'hashes' table and its supporting views.
--
-- 1. TABLE: hashes
--    - Stores SHA-1 digests, file metadata (size, mime, timestamps), and paths.
--    - Uses a BIGSERIAL id starting at 1,000,001.
--    - Includes a generated 'full_path' for easy querying and path validation.
--
-- ==============================================================================

DROP TABLE IF EXISTS hashes CASCADE;

-- this table stores the meta for the pool of files we want to dedupe
CREATE TABLE hashes
(
    id            BIGSERIAL PRIMARY KEY,                                                    -- artificial primary key
    hash          CHAR(40)                                                        NOT NULL, -- SHA-1 hex, lowercase, of the file contents
    mime_type     TEXT                                                            NOT NULL, -- MIME type of the file, lowercase
    last_modified TIMESTAMP                                                       NOT NULL, -- in local time (CST preferred)
    file_size     BIGINT                                                          NOT NULL, -- bytes
    base_path     TEXT                                                            NOT NULL, -- common root directory (or mount point of device/share)
    file_path     TEXT                                                            NOT NULL, -- relative to base_path
    full_path     TEXT GENERATED ALWAYS AS (base_path || '/' || file_path) STORED NOT NULL, -- absolute path, computed from base_path and file_path
    UNIQUE (full_path)                                                                      -- full_path is required to be unique
);

-- start at a known value
ALTER SEQUENCE hashes_id_seq RESTART WITH 1000001;
