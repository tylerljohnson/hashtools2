-- find-vault-primary-dupes.sql
--
-- Purpose:
--   For a given vault base_path, list duplicates of PRIMARY files that live in the vault.
--
-- Definitions:
--   - "Vault" = any row where base_path = :vault_base.
--   - "Primary" = rows from the files_primary view (oldest per (hash, mime_type)).
--
-- Logic:
--   1. Select all primary files in the vault (vault_primary CTE).
--   2. For each vault primary, find matching rows in files with the same (hash, mime_type),
--      where:
--        - The other file is NOT in the vault (f.base_path <> :vault_base).
--        - The other file is not the same physical file (full_path differs).
--   3. Compute deltaDays = (other_last_modified - vault_last_modified) in days.
--   4. Exclude any rows where deltaDays < 0, i.e., where the non-vault copy is OLDER
--      than the vault copy. We only keep same-age or newer duplicates.
--
-- Parameters:
--   :vault_base  - The base_path of the vault (e.g. '/Volumes/vault/secret').
--
-- Output columns:
--   hash               - Content hash of the file.
--   mime_type          - MIME type of the file.
--   vault_last_modified- Timestamp of the primary vault copy.
--   dupe_last_modified - Timestamp of the duplicate (outside the vault).
--   deltaDays          - (dupe_last_modified - vault_last_modified) in days, 6 decimal places.
--   other_base_path    - base_path of the duplicate.
--   other_full_path    - full_path of the duplicate.
--

WITH vault_primary AS (
    SELECT
        hash,
        mime_type,
        base_path,
        file_path,
        full_path,
        last_modified
    FROM files_primary
    WHERE base_path = '/home/tyler/packrat/vault/secret' and mime_type like 'image%'
),
     dupes AS (
         SELECT
             vp.hash,
             vp.mime_type,
             vp.full_path     AS vault_full_path,
             vp.last_modified AS vault_last_modified,
             f.full_path      AS other_full_path,
             f.last_modified  AS other_last_modified,
             f.base_path      AS other_base_path,
             f.disposition    AS other_disposition,
             ROUND(EXTRACT(EPOCH FROM (f.last_modified - vp.last_modified)) / 86400, 6) AS deltaDays
         FROM vault_primary vp
                  JOIN files f
                       ON f.hash = vp.hash
                           AND f.mime_type = vp.mime_type
                           AND f.full_path <> vp.full_path
                           AND f.base_path <> '/home/tyler/packrat/vault/secret'          -- never report vault files as "other"
     )
SELECT
    hash,
    mime_type,
    vault_last_modified,
    other_last_modified AS dupe_last_modified,
    deltaDays,
    other_base_path,
    other_full_path
FROM dupes
WHERE deltaDays >= 0
ORDER BY
    EXTRACT(EPOCH FROM (other_last_modified - vault_last_modified)) DESC,
    hash,
    mime_type;