-- ------------------------------------------------------------
-- MIME Type Duplication Summary
-- Summarizes per-mime-type duplication statistics,
-- showing counts of primary vs redundant files,
-- total redundant size in human-readable units,
-- and percent duplication by count.
-- ------------------------------------------------------------
SELECT
    mime_type,
    COUNT(*) FILTER (WHERE disposition = 'primary')   AS primary_count,
    COUNT(*) FILTER (WHERE disposition = 'redundant') AS redundant_count,
    CASE
        WHEN COALESCE(SUM(length) FILTER (WHERE disposition='redundant'),0) >= 1e9
            THEN TO_CHAR(
                         COALESCE(SUM(length) FILTER (WHERE disposition='redundant'),0)/1e9,
                         'FM9999990.00') || ' GB'
        WHEN COALESCE(SUM(length) FILTER (WHERE disposition='redundant'),0) >= 1e6
            THEN TO_CHAR(
                         COALESCE(SUM(length) FILTER (WHERE disposition='redundant'),0)/1e6,
                         'FM9999990.00') || ' MB'
        WHEN COALESCE(SUM(length) FILTER (WHERE disposition='redundant'),0) >= 1e3
            THEN TO_CHAR(
                         COALESCE(SUM(length) FILTER (WHERE disposition='redundant'),0)/1e3,
                         'FM9999990.00') || ' KB'
        ELSE TO_CHAR(
                     COALESCE(SUM(length) FILTER (WHERE disposition='redundant'),0),
                     'FM9999990.00') || ' B'
        END AS redundant_size,
    TO_CHAR(
            100.0 * COUNT(*) FILTER (WHERE disposition = 'redundant')
                / NULLIF(COUNT(*), 0),
            'FM999990.00'
    ) || '%' AS pct_duplication
FROM files
GROUP BY mime_type
ORDER BY COALESCE(SUM(length) FILTER (WHERE disposition='redundant'),0) DESC;