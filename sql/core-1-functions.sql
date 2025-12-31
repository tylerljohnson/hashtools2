
-- Helper: basename of file_path (trim trailing slashes, then take last '/'-segment)
CREATE OR REPLACE FUNCTION public.file_name_from_path(p_path text)
    RETURNS text
    LANGUAGE sql
    IMMUTABLE
    STRICT
    PARALLEL SAFE
AS $$
SELECT split_part(regexp_replace(p_path, '/+$', ''), '/', -1)
$$;

-- Helper: lowercase extension from file_path basename
-- Rules:
--   - extension must be after the last '/'
--   - if basename starts with '.', ignore that first '.' when determining extension
CREATE OR REPLACE FUNCTION public.file_ext_from_path(p_path text)
    RETURNS text
    LANGUAGE sql
    IMMUTABLE
    STRICT
    PARALLEL SAFE
AS $$
WITH x AS (
    SELECT public.file_name_from_path(p_path) AS fn
)
SELECT
    CASE
        WHEN fn = '' THEN NULL

        WHEN fn LIKE '.%' THEN
            CASE
                WHEN position('.' in reverse(substr(fn, 2))) IN (0, 1) THEN NULL
                ELSE lower(split_part(substr(fn, 2), '.', -1))
                END

        ELSE
            CASE
                WHEN position('.' in reverse(fn)) IN (0, 1) THEN NULL
                ELSE lower(split_part(fn, '.', -1))
                END
        END
FROM x
$$;
