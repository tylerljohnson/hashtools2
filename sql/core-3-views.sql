-- ==============================================================================
-- CORE SCHEMA OVERVIEW
-- ==============================================================================
-- This script initializes the central 'hashes' table and its supporting views.
--
-- 3. VIEWS:
--    - Organized by file category (files, media, images, videos, audio).
--    - Each category provides three views:
--        * <base>: All records with an 'id' and 'disposition' (primary vs redundant).
--        * <base>_primary: The oldest unique instance of a file (by hash/mime).
--        * <base>_redundant: Duplicate copies that can be safely archived or deleted.
-- ==============================================================================


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
WITH ranked AS (SELECT id,
                       hash,
                       mime_type,
                       last_modified,
                       file_size                                    AS length,
                       base_path,
                       file_path,
                       full_path,
                       DENSE_RANK() OVER (ORDER BY hash, mime_type) AS group_num,
                       ROW_NUMBER() OVER (
                           PARTITION BY hash, mime_type
                           ORDER BY last_modified ASC, id ASC
                           )                                        AS rn,
                       COUNT(*) OVER (PARTITION BY hash, mime_type) AS grp_size
                FROM hashes)
SELECT id,
       group_num,
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
WITH ranked AS (SELECT id,
                       hash,
                       mime_type,
                       last_modified,
                       file_size                                    AS length,
                       base_path,
                       file_path,
                       full_path,
                       DENSE_RANK() OVER (ORDER BY hash, mime_type) AS group_num,
                       ROW_NUMBER() OVER (
                           PARTITION BY hash, mime_type
                           ORDER BY last_modified ASC, id ASC
                           )                                        AS rn,
                       COUNT(*) OVER (PARTITION BY hash, mime_type) AS grp_size
                FROM hashes
                WHERE mime_type LIKE ANY (ARRAY ['image/%','video/%','audio/%']))
SELECT id,
       group_num,
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
WITH ranked AS (SELECT id,
                       hash,
                       mime_type,
                       last_modified,
                       file_size                                    AS length,
                       base_path,
                       file_path,
                       full_path,
                       DENSE_RANK() OVER (ORDER BY hash, mime_type) AS group_num,
                       ROW_NUMBER() OVER (
                           PARTITION BY hash, mime_type
                           ORDER BY last_modified ASC, id ASC
                           )                                        AS rn,
                       COUNT(*) OVER (PARTITION BY hash, mime_type) AS grp_size
                FROM hashes
                WHERE mime_type LIKE 'image/%')
SELECT id,
       group_num,
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
WITH ranked AS (SELECT id,
                       hash,
                       mime_type,
                       last_modified,
                       file_size                                    AS length,
                       base_path,
                       file_path,
                       full_path,
                       DENSE_RANK() OVER (ORDER BY hash, mime_type) AS group_num,
                       ROW_NUMBER() OVER (
                           PARTITION BY hash, mime_type
                           ORDER BY last_modified ASC, id ASC
                           )                                        AS rn,
                       COUNT(*) OVER (PARTITION BY hash, mime_type) AS grp_size
                FROM hashes
                WHERE mime_type LIKE 'video/%')
SELECT id,
       group_num,
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
WITH ranked AS (SELECT id,
                       hash,
                       mime_type,
                       last_modified,
                       file_size                                    AS length,
                       base_path,
                       file_path,
                       full_path,
                       DENSE_RANK() OVER (ORDER BY hash, mime_type) AS group_num,
                       ROW_NUMBER() OVER (
                           PARTITION BY hash, mime_type
                           ORDER BY last_modified ASC, id ASC
                           )                                        AS rn,
                       COUNT(*) OVER (PARTITION BY hash, mime_type) AS grp_size
                FROM hashes
                WHERE mime_type LIKE 'audio/%')
SELECT id,
       group_num,
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