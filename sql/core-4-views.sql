-- ==============================================================================
-- CORE SCHEMA OVERVIEW
-- ==============================================================================
-- This script initializes the central 'hashes' table and its supporting views.
--
-- 3. VIEWS:
-- ==============================================================================

BEGIN;

CREATE OR REPLACE VIEW files AS
WITH joined AS (
    SELECT
        h.id,
        h.hash,
        h.mime_type,
        h.last_modified,
        h.file_size AS length,
        h.base_path,
        h.file_path,
        h.full_path,
        bp.priority,
        bp.is_vault
    FROM hashes h
             JOIN base_paths bp
                  ON bp.base_path = h.base_path
),
     ranked AS (
         SELECT
             *,
             DENSE_RANK() OVER (ORDER BY hash, mime_type) AS group_num,
             ROW_NUMBER() OVER (
                 PARTITION BY hash, mime_type
                 ORDER BY last_modified ASC, priority ASC, id ASC
                 ) AS rn,
             COUNT(*) OVER (PARTITION BY hash, mime_type) AS grp_size
         FROM joined
     )
SELECT
    id,
    group_num,
    hash,
    last_modified,
    mime_type,
    length,
    base_path,
    file_path,
    full_path,
    is_vault,
    priority,
    CASE WHEN rn = 1 THEN 'primary' ELSE 'redundant' END AS disposition
FROM ranked;

CREATE OR REPLACE VIEW files_primary AS
SELECT *
FROM files
WHERE disposition = 'primary';

-- redundant files
CREATE OR REPLACE VIEW files_redundant AS
SELECT *
FROM files
WHERE disposition = 'redundant';

-- vault timestamp drift work-queue
CREATE OR REPLACE VIEW vault_timestamp_drift AS
WITH joined AS (
    SELECT h.*, bp.is_vault, bp.priority
    FROM hashes h
             JOIN base_paths bp USING (base_path)
),
     oldest AS (
         SELECT DISTINCT ON (hash, mime_type)
             hash, mime_type,
             id AS oldest_id,
             full_path AS oldest_full_path,
             last_modified AS oldest_last_modified,
             is_vault AS oldest_is_vault
         FROM joined
         ORDER BY hash, mime_type, last_modified ASC, priority ASC, id ASC
     ),
     vault_pick AS (
         SELECT DISTINCT ON (hash, mime_type)
             hash, mime_type,
             id AS vault_id,
             full_path AS vault_full_path,
             last_modified AS vault_last_modified,
             priority AS vault_priority
         FROM joined
         WHERE is_vault
         ORDER BY hash, mime_type, priority ASC, id ASC
     )
SELECT
    o.hash,
    o.mime_type,
    o.oldest_full_path,
    o.oldest_last_modified AS target_last_modified,
    v.vault_id,
    v.vault_full_path,
    v.vault_last_modified,
    (EXTRACT(EPOCH FROM (v.vault_last_modified - o.oldest_last_modified)))::bigint AS drift_seconds
FROM oldest o
         JOIN vault_pick v USING (hash, mime_type)
WHERE o.oldest_is_vault = FALSE
  AND v.vault_last_modified > o.oldest_last_modified;

COMMIT;
