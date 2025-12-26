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


-- ==================================================
-- Drop and rebuild tables
-- ==================================================


DROP TABLE IF EXISTS hashes CASCADE;

CREATE TABLE hashes
(
    id            BIGSERIAL PRIMARY KEY,
    hash          CHAR(40)                                                        NOT NULL, -- SHA-1 hex
    mime_type     TEXT                                                            NOT NULL,
    last_modified TIMESTAMP                                                       NOT NULL, -- in local time (CST preferred)
    file_size     BIGINT                                                          NOT NULL, -- bytes
    base_path     TEXT                                                            NOT NULL,
    file_path     TEXT                                                            NOT NULL, -- relative to base_path
    full_path     TEXT GENERATED ALWAYS AS (base_path || '/' || file_path) STORED NOT NULL,
    UNIQUE (full_path)
);

ALTER SEQUENCE hashes_id_seq RESTART WITH 1000001;
