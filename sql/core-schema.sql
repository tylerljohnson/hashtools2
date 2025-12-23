

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


-- ==================================================
-- Drop & Rebuild Views (renamed, simplified)
-- Naming pattern: <base>, <base>_primary, <base>_redundant
-- Bases: files (all), media (image+video+audio), images, videos, audio
-- ==================================================


-- Drop old/new views defensively
DROP VIEW IF EXISTS
    files, files_primary, files_redundant,
    media, media_primary, media_redundant,
    images, images_primary, images_redundant,
    videos, videos_primary, videos_redundant,
    audio, audio_primary, audio_redundant,
    CASCADE;

-- Base: files (all MIME types)
CREATE OR REPLACE VIEW files AS
WITH ranked AS (SELECT hash,
                       mime_type,
                       last_modified,
                       file_size                                    AS length,
                       base_path,
                       file_path,
                       full_path,
                       DENSE_RANK() OVER (ORDER BY hash, mime_type) AS group_num,
                       ROW_NUMBER() OVER (
                           PARTITION BY hash, mime_type
                           ORDER BY last_modified, id
                           )                                        AS rn,
                       COUNT(*) OVER (PARTITION BY hash, mime_type) AS grp_size
                FROM hashes)
SELECT group_num,
       hash,
       last_modified,
       mime_type,
       length,
       base_path,
       file_path,
       full_path,
       CASE WHEN rn = 1 THEN 'primary' ELSE 'redundant' END AS disposition
FROM ranked;

CREATE OR REPLACE VIEW files_primary AS
SELECT *
FROM files
WHERE disposition = 'primary';

CREATE OR REPLACE VIEW files_redundant AS
SELECT *
FROM files
WHERE disposition = 'redundant';

-- Base: media (image/% OR video/% OR audio/%)
CREATE OR REPLACE VIEW media AS
WITH ranked AS (SELECT hash,
                       mime_type,
                       last_modified,
                       file_size                                    AS length,
                       base_path,
                       file_path,
                       full_path,
                       DENSE_RANK() OVER (ORDER BY hash, mime_type) AS group_num,
                       ROW_NUMBER() OVER (
                           PARTITION BY hash, mime_type
                           ORDER BY last_modified, id
                           )                                        AS rn,
                       COUNT(*) OVER (PARTITION BY hash, mime_type) AS grp_size
                FROM hashes
                WHERE mime_type LIKE ANY (ARRAY ['image/%','video/%','audio/%']))
SELECT group_num,
       hash,
       last_modified,
       mime_type,
       length,
       base_path,
       file_path,
       full_path,
       CASE WHEN rn = 1 THEN 'primary' ELSE 'redundant' END AS disposition
FROM ranked;

CREATE OR REPLACE VIEW media_primary AS
SELECT *
FROM media
WHERE disposition = 'primary';

CREATE OR REPLACE VIEW media_redundant AS
SELECT *
FROM media
WHERE disposition = 'redundant';

-- Base: images (image/%)
CREATE OR REPLACE VIEW images AS
WITH ranked AS (SELECT hash,
                       mime_type,
                       last_modified,
                       file_size                                    AS length,
                       base_path,
                       file_path,
                       full_path,
                       DENSE_RANK() OVER (ORDER BY hash, mime_type) AS group_num,
                       ROW_NUMBER() OVER (
                           PARTITION BY hash, mime_type
                           ORDER BY last_modified, id
                           )                                        AS rn,
                       COUNT(*) OVER (PARTITION BY hash, mime_type) AS grp_size
                FROM hashes
                WHERE mime_type LIKE 'image/%')
SELECT group_num,
       hash,
       last_modified,
       mime_type,
       length,
       base_path,
       file_path,
       full_path,
       CASE WHEN rn = 1 THEN 'primary' ELSE 'redundant' END AS disposition
FROM ranked;

CREATE OR REPLACE VIEW images_primary AS
SELECT *
FROM images
WHERE disposition = 'primary';

CREATE OR REPLACE VIEW images_redundant AS
SELECT *
FROM images
WHERE disposition = 'redundant';

-- Base: videos (video/%)
CREATE OR REPLACE VIEW videos AS
WITH ranked AS (SELECT hash,
                       mime_type,
                       last_modified,
                       file_size                                    AS length,
                       base_path,
                       file_path,
                       full_path,
                       DENSE_RANK() OVER (ORDER BY hash, mime_type) AS group_num,
                       ROW_NUMBER() OVER (
                           PARTITION BY hash, mime_type
                           ORDER BY last_modified, id
                           )                                        AS rn,
                       COUNT(*) OVER (PARTITION BY hash, mime_type) AS grp_size
                FROM hashes
                WHERE mime_type LIKE 'video/%')
SELECT group_num,
       hash,
       last_modified,
       mime_type,
       length,
       base_path,
       file_path,
       full_path,
       CASE WHEN rn = 1 THEN 'primary' ELSE 'redundant' END AS disposition
FROM ranked;

CREATE OR REPLACE VIEW videos_primary AS
SELECT *
FROM videos
WHERE disposition = 'primary';

CREATE OR REPLACE VIEW videos_redundant AS
SELECT *
FROM videos
WHERE disposition = 'redundant';

-- Base: audio (audio/%)
CREATE OR REPLACE VIEW audio AS
WITH ranked AS (SELECT hash,
                       mime_type,
                       last_modified,
                       file_size                                    AS length,
                       base_path,
                       file_path,
                       full_path,
                       DENSE_RANK() OVER (ORDER BY hash, mime_type) AS group_num,
                       ROW_NUMBER() OVER (
                           PARTITION BY hash, mime_type
                           ORDER BY last_modified, id
                           )                                        AS rn,
                       COUNT(*) OVER (PARTITION BY hash, mime_type) AS grp_size
                FROM hashes
                WHERE mime_type LIKE 'audio/%')
SELECT group_num,
       hash,
       last_modified,
       mime_type,
       length,
       base_path,
       file_path,
       full_path,
       CASE WHEN rn = 1 THEN 'primary' ELSE 'redundant' END AS disposition
FROM ranked;

CREATE OR REPLACE VIEW audio_primary AS
SELECT *
FROM audio
WHERE disposition = 'primary';

CREATE OR REPLACE VIEW audio_redundant AS
SELECT *
FROM audio
WHERE disposition = 'redundant';
