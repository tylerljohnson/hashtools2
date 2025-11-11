-- Summarize files with disposition = 'redundant' by hash and mime_type, showing the
-- file count and total size formatted in binary units (B, KiB, MiB, GiB, TiB).
-- Size thresholds are based on powers of two (2^10, 2^20, 2^30, 2^40) and values
-- are truncated to one decimal place so they stay in the 1.0–999.9 range per unit.
WITH sized AS (
    SELECT
        hash,
        mime_type,
        COUNT(*)    AS file_count,
        SUM(length) AS bytes
    FROM files
    WHERE disposition = 'redundant'
    GROUP BY
        hash,
        mime_type
)
SELECT
    hash,
    mime_type,
    file_count,
    CASE
        WHEN bytes < (2::numeric ^ 10)        THEN trunc(bytes::numeric / (2::numeric ^  0), 1)::text || ' B'
        WHEN bytes < (2::numeric ^ 10) * 1000 THEN trunc(bytes::numeric / (2::numeric ^ 10), 1)::text || ' KiB'
        WHEN bytes < (2::numeric ^ 20) * 1000 THEN trunc(bytes::numeric / (2::numeric ^ 20), 1)::text || ' MiB'
        WHEN bytes < (2::numeric ^ 30) * 1000 THEN trunc(bytes::numeric / (2::numeric ^ 30), 1)::text || ' GiB'
        ELSE trunc(bytes::numeric / (2::numeric ^ 40), 1)::text || ' TiB'
        END AS size_binary
FROM sized
ORDER BY bytes DESC
;