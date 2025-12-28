-- core-90-data-validation.sql
-- Read-only health checks and data validations for the hashes/base_paths schema.
-- Run with: psql --set=ON_ERROR_STOP=1 -f core-90-data-validation.sql

-- 1) base_path ending with '/' or file_path starting with '/'
SELECT 'base_or_file_path_slash_issues' AS check_name, COUNT(*) AS problem_count
FROM hashes
WHERE base_path LIKE '%/' OR file_path LIKE '/%';

-- Sample rows (if any)
SELECT id, base_path, file_path, full_path
FROM hashes
WHERE base_path LIKE '%/' OR file_path LIKE '/%'
ORDER BY id
LIMIT 50;

-- 2) base_path values present in hashes but missing from base_paths
SELECT 'missing_base_paths' AS check_name, COUNT(*) AS problem_count
FROM (
  SELECT DISTINCT base_path FROM hashes
  EXCEPT
  SELECT base_path FROM base_paths
) t;

-- Sample missing base_paths
SELECT DISTINCT base_path
FROM hashes
WHERE base_path NOT IN (SELECT base_path FROM base_paths)
ORDER BY base_path
LIMIT 50;

-- 3) invalid or malformed hash values (non-lower-hex or wrong length)
SELECT 'invalid_hash_format' AS check_name, COUNT(*) AS problem_count
FROM hashes
WHERE hash !~ '^[0-9a-f]{40}$' OR hash IS NULL;

-- Sample malformed hashes
SELECT id, hash
FROM hashes
WHERE hash !~ '^[0-9a-f]{40}$' OR hash IS NULL
ORDER BY id
LIMIT 50;

-- 4) negative or NULL file sizes
SELECT 'negative_or_null_file_size' AS check_name, COUNT(*) AS problem_count
FROM hashes
WHERE file_size IS NULL OR file_size < 0;

SELECT id, file_size
FROM hashes
WHERE file_size IS NULL OR file_size < 0
ORDER BY id
LIMIT 50;

-- 5) full_path mismatches vs normalized concatenation (rtrim/ltrim)
SELECT 'full_path_mismatch' AS check_name, COUNT(*) AS problem_count
FROM hashes
WHERE full_path IS DISTINCT FROM (rtrim(base_path, '/') || '/' || ltrim(file_path, '/'));

SELECT id, base_path, file_path, full_path,
       (rtrim(base_path, '/') || '/' || ltrim(file_path, '/')) AS expected_full_path
FROM hashes
WHERE full_path IS DISTINCT FROM (rtrim(base_path, '/') || '/' || ltrim(file_path, '/'))
ORDER BY id
LIMIT 50;

-- 6) duplicate full_path entries (should be prevented by UNIQUE constraint)
SELECT 'duplicate_full_path' AS check_name, COUNT(*) AS problem_count
FROM (
  SELECT full_path, COUNT(*) AS ct
  FROM hashes
  GROUP BY full_path
  HAVING COUNT(*) > 1
) t;

-- Sample duplicates (if any)
SELECT full_path, COUNT(*) AS ct
FROM hashes
GROUP BY full_path
HAVING COUNT(*) > 1
ORDER BY ct DESC
LIMIT 50;

-- 7) base_paths priority duplicates (UNIQUE(priority) expected)
SELECT 'duplicate_base_path_priority' AS check_name, COUNT(*) AS problem_count
FROM (
  SELECT priority, COUNT(*) AS ct
  FROM base_paths
  GROUP BY priority
  HAVING COUNT(*) > 1
) t;

SELECT priority, array_agg(base_path) AS base_paths
FROM base_paths
GROUP BY priority
HAVING COUNT(*) > 1
LIMIT 50;

-- 8) base_paths marked as vault but with no referenced hashes (possible stale entry)
SELECT 'vault_base_paths_without_files' AS check_name, COUNT(*) AS problem_count
FROM base_paths bp
WHERE bp.is_vault
  AND NOT EXISTS (SELECT 1 FROM hashes h WHERE h.base_path = bp.base_path);

SELECT bp.base_path
FROM base_paths bp
WHERE bp.is_vault
  AND NOT EXISTS (SELECT 1 FROM hashes h WHERE h.base_path = bp.base_path)
ORDER BY bp.base_path
LIMIT 50;

-- 9) rows in hashes that are not visible through the files view (usually due to missing base_paths)
SELECT 'hashes_not_in_files_view' AS check_name, COUNT(*) AS problem_count
FROM hashes h
WHERE NOT EXISTS (SELECT 1 FROM files f WHERE f.id = h.id);

SELECT h.id, h.base_path, h.file_path, h.full_path
FROM hashes h
WHERE NOT EXISTS (SELECT 1 FROM files f WHERE f.id = h.id)
ORDER BY h.id
LIMIT 50;

-- 10) sequence check: ensure serial sequence for hashes.id is ahead of max(id)
DO $$
DECLARE
  seq_name text;
  seq_last bigint;
  max_id bigint;
BEGIN
  seq_name := pg_get_serial_sequence('hashes', 'id');
  IF seq_name IS NULL THEN
    RAISE NOTICE 'No serial sequence found for hashes.id';
    RETURN;
  END IF;
  EXECUTE format('SELECT last_value FROM %s', seq_name) INTO seq_last;
  SELECT max(id) INTO max_id FROM hashes;
  RAISE NOTICE 'sequence=%; last_value=%; max(id)=%', seq_name, seq_last, max_id;
  IF seq_last <= COALESCE(max_id, 0) THEN
    RAISE WARNING 'sequence last_value (% ) <= max(id) (% ) - consider running ALTER SEQUENCE ... RESTART WITH ...', seq_last, max_id;
  ELSE
    RAISE NOTICE 'sequence looks healthy';
  END IF;
END$$;

-- 11) Quick health: counts by disposition from files view
SELECT 'files_view_summary' AS check_name, COUNT(*) FILTER (WHERE disposition = 'primary') AS primaries,
       COUNT(*) FILTER (WHERE disposition = 'redundant') AS redundants,
       COUNT(*) AS total_rows
FROM files;

-- End of checks
```
