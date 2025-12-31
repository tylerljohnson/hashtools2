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

BEGIN;

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
    file_name     TEXT GENERATED ALWAYS AS (file_name_from_path(file_path)) STORED,
    file_ext      TEXT GENERATED ALWAYS AS (file_ext_from_path(file_path)) STORED,
    UNIQUE (full_path)                                                                      -- full_path is required to be unique
);

-- start at a known value
ALTER SEQUENCE hashes_id_seq RESTART WITH 1000001;

-- meta for base paths, which are vaults & what is the priority order
DROP TABLE IF EXISTS base_paths;
CREATE TABLE IF NOT EXISTS base_paths (
    base_path  TEXT PRIMARY KEY,
    priority   INTEGER NOT NULL CHECK (priority > 0),
    is_vault   BOOLEAN NOT NULL DEFAULT FALSE,
    UNIQUE (priority)
    );

-- mime type to category mapping
DROP TABLE IF EXISTS mime_categories;
CREATE TABLE IF NOT EXISTS mime_categories (
   mime_type TEXT PRIMARY KEY,
   category  TEXT NOT NULL
);

COMMIT
