-- =============================================
-- Drop & Rebuild Views (renamed, simplified)
-- Naming pattern: <base>, <base>_primary, <base>_redundant
-- Bases: files (all), media (image+video+audio), images, videos, audio
-- =============================================

-- Drop old/new views defensively
DROP VIEW IF EXISTS
  -- New names
  files, files_primary, files_redundant,
  media, media_primary, media_redundant,
  images, images_primary, images_redundant,
  videos, videos_primary, videos_redundant,
  audio,  audio_primary,  audio_redundant,
  -- Old dedupe names
  hashes_dedupe, hashes_dedupe_dupes,
  hashes_dedupe_media, hashes_dedupe_media_dupes,
  hashes_dedupe_images, hashes_dedupe_images_dupes,
  hashes_dedupe_videos, hashes_dedupe_videos_dupes,
  hashes_dedupe_audio,  hashes_dedupe_audio_dupes,
  -- Old mime filter views
  hashes_media, hashes_images, hashes_videos, hashes_audio
CASCADE;

-- =========================================================
-- Base: files (all MIME types)
-- =========================================================
CREATE OR REPLACE VIEW files AS
WITH ranked AS (
  SELECT
    hash,
    mime_type,
    last_modified,
    file_size AS length,
    full_path,
    DENSE_RANK() OVER (ORDER BY hash, mime_type) AS group_num,
    ROW_NUMBER() OVER (
      PARTITION BY hash, mime_type
      ORDER BY last_modified ASC, id ASC
    ) AS rn,
    COUNT(*) OVER (PARTITION BY hash, mime_type) AS grp_size
  FROM hashes
)
SELECT
  group_num, hash, last_modified, mime_type, length, full_path,
  CASE WHEN rn = 1 THEN 'primary' ELSE 'redundant' END AS disposition
FROM ranked;

CREATE OR REPLACE VIEW files_primary AS
SELECT * FROM files WHERE disposition = 'primary';

CREATE OR REPLACE VIEW files_redundant AS
SELECT * FROM files WHERE disposition = 'redundant';

-- =========================================================
-- Base: media (image/% OR video/% OR audio/%)
-- =========================================================
CREATE OR REPLACE VIEW media AS
WITH ranked AS (
  SELECT
    hash,
    mime_type,
    last_modified,
    file_size AS length,
    full_path,
    DENSE_RANK() OVER (ORDER BY hash, mime_type) AS group_num,
    ROW_NUMBER() OVER (
      PARTITION BY hash, mime_type
      ORDER BY last_modified ASC, id ASC
    ) AS rn,
    COUNT(*) OVER (PARTITION BY hash, mime_type) AS grp_size
  FROM hashes
  WHERE mime_type LIKE ANY (ARRAY['image/%','video/%','audio/%'])
)
SELECT
  group_num, hash, last_modified, mime_type, length, full_path,
  CASE WHEN rn = 1 THEN 'primary' ELSE 'redundant' END AS disposition
FROM ranked;

CREATE OR REPLACE VIEW media_primary AS
SELECT * FROM media WHERE disposition = 'primary';

CREATE OR REPLACE VIEW media_redundant AS
SELECT * FROM media WHERE disposition = 'redundant';

-- =========================================================
-- Base: images (image/%)
-- =========================================================
CREATE OR REPLACE VIEW images AS
WITH ranked AS (
  SELECT
    hash,
    mime_type,
    last_modified,
    file_size AS length,
    full_path,
    DENSE_RANK() OVER (ORDER BY hash, mime_type) AS group_num,
    ROW_NUMBER() OVER (
      PARTITION BY hash, mime_type
      ORDER BY last_modified ASC, id ASC
    ) AS rn,
    COUNT(*) OVER (PARTITION BY hash, mime_type) AS grp_size
  FROM hashes
  WHERE mime_type LIKE 'image/%'
)
SELECT
  group_num, hash, last_modified, mime_type, length, full_path,
  CASE WHEN rn = 1 THEN 'primary' ELSE 'redundant' END AS disposition
FROM ranked;

CREATE OR REPLACE VIEW images_primary AS
SELECT * FROM images WHERE disposition = 'primary';

CREATE OR REPLACE VIEW images_redundant AS
SELECT * FROM images WHERE disposition = 'redundant';

-- =========================================================
-- Base: videos (video/%)
-- =========================================================
CREATE OR REPLACE VIEW videos AS
WITH ranked AS (
  SELECT
    hash,
    mime_type,
    last_modified,
    file_size AS length,
    full_path,
    DENSE_RANK() OVER (ORDER BY hash, mime_type) AS group_num,
    ROW_NUMBER() OVER (
      PARTITION BY hash, mime_type
      ORDER BY last_modified ASC, id ASC
    ) AS rn,
    COUNT(*) OVER (PARTITION BY hash, mime_type) AS grp_size
  FROM hashes
  WHERE mime_type LIKE 'video/%'
)
SELECT
  group_num, hash, last_modified, mime_type, length, full_path,
  CASE WHEN rn = 1 THEN 'primary' ELSE 'redundant' END AS disposition
FROM ranked;

CREATE OR REPLACE VIEW videos_primary AS
SELECT * FROM videos WHERE disposition = 'primary';

CREATE OR REPLACE VIEW videos_redundant AS
SELECT * FROM videos WHERE disposition = 'redundant';

-- =========================================================
-- Base: audio (audio/%)
-- =========================================================
CREATE OR REPLACE VIEW audio AS
WITH ranked AS (
  SELECT
    hash,
    mime_type,
    last_modified,
    file_size AS length,
    full_path,
    DENSE_RANK() OVER (ORDER BY hash, mime_type) AS group_num,
    ROW_NUMBER() OVER (
      PARTITION BY hash, mime_type
      ORDER BY last_modified ASC, id ASC
    ) AS rn,
    COUNT(*) OVER (PARTITION BY hash, mime_type) AS grp_size
  FROM hashes
  WHERE mime_type LIKE 'audio/%'
)
SELECT
  group_num, hash, last_modified, mime_type, length, full_path,
  CASE WHEN rn = 1 THEN 'primary' ELSE 'redundant' END AS disposition
FROM ranked;

CREATE OR REPLACE VIEW audio_primary AS
SELECT * FROM audio WHERE disposition = 'primary';

CREATE OR REPLACE VIEW audio_redundant AS
SELECT * FROM audio WHERE disposition = 'redundant';
