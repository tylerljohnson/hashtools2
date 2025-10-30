-- ===========================
-- Drop and Rebuild Hashes Table
-- ===========================

DROP TABLE IF EXISTS hashes CASCADE;

CREATE TABLE hashes (
   id             BIGSERIAL PRIMARY KEY,
   hash           CHAR(40)           NOT NULL,   -- SHA-1 hex
   mime_type      TEXT               NOT NULL,
   last_modified  TIMESTAMP          NOT NULL,   -- in local time (CST preferred)
   file_size      BIGINT             NOT NULL,   -- bytes
   base_path      TEXT               NOT NULL,
   file_path      TEXT               NOT NULL,   -- relative to base_path
   full_path      TEXT GENERATED ALWAYS AS (base_path || '/' || file_path) STORED NOT NULL,
   UNIQUE (full_path)
);
