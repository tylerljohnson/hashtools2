
-- Helper: basename of file_path (trim trailing slashes, then take last '/'-segment)

BEGIN;

CREATE OR REPLACE FUNCTION file_name_from_path(p_path text)
    RETURNS text
    LANGUAGE sql
    IMMUTABLE
    STRICT
    PARALLEL SAFE
AS $$
    -- regexp_replace handles trailing slashes
-- split_part with -1 index requires PostgreSQL 14+
SELECT split_part(regexp_replace(p_path, '/+$', ''), '/', -1)
$$;

-- Helper: lowercase extension from file_path basename
-- Rules:
--   - extension must be after the last '/'
--   - if basename starts with '.', ignore that first '.' when determining extension
--   - returns NULL if no extension is found
CREATE OR REPLACE FUNCTION file_ext_from_path(p_path text)
    RETURNS text
    LANGUAGE sql
    IMMUTABLE
    STRICT
    PARALLEL SAFE
AS $$
WITH x AS (
    SELECT file_name_from_path(p_path) AS fn
)
SELECT
    CASE
        -- No filename or filename is just '.'
        WHEN fn = '' OR fn = '.' THEN NULL

        -- If filename starts with '.', check for another '.' in the remainder
        WHEN fn LIKE '.%' THEN
            CASE
                WHEN position('.' in substr(fn, 2)) > 0 THEN lower(split_part(fn, '.', -1))
                ELSE NULL
                END

        -- Standard case: return part after last '.', or NULL if no '.' exists
        ELSE
            CASE
                WHEN position('.' in fn) > 0 THEN lower(split_part(fn, '.', -1))
                ELSE NULL
                END
        END
FROM x
$$;

COMMIT
