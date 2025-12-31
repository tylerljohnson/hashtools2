-- list total size in SI units of primary files for each mime type category
select  c.category,
        CASE
            WHEN sum(p.length) < 1000       THEN to_char(sum(p.length)::numeric, 'FM9999999990.0') || ' B'
            WHEN sum(p.length) < 1000^2     THEN to_char(sum(p.length) / 1000.0,      'FM9999999990.0') || ' kB'
            WHEN sum(p.length) < 1000^3     THEN to_char(sum(p.length) / 1000.0^2,    'FM9999999990.0') || ' MB'
            WHEN sum(p.length) < 1000^4     THEN to_char(sum(p.length) / 1000.0^3,    'FM9999999990.0') || ' GB'
            WHEN sum(p.length) < 1000^5     THEN to_char(sum(p.length) / 1000.0^4,    'FM9999999990.0') || ' TB'
            WHEN sum(p.length) < 1000^6     THEN to_char(sum(p.length) / 1000.0^5,    'FM9999999990.0') || ' PB'
            ELSE                        to_char(sum(p.length) / 1000.0^6,    'FM9999999990.0') || ' EB'
            END AS si_pretty
from mime_categories c, files_primary p
where p.mime_type = c.mime_type
group by c.category
order by sum(p.length) desc
;

-- extract the last segment of the base path
SELECT
    c.category
    , p.mime_type, p.length
     , p.file_name, p.file_ext
     , p.base_path, p.file_path, p.full_path
from files_primary p
    ,mime_categories c
where p.mime_type = c.mime_type
and (c.category in ('image', 'audio', 'video', 'media_container')
    or c.category in ('email')
    or c.category in ('archives', 'disk_image')
    or c.category in ('media_support', 'image_support')
    or c.category in ('database')
    --or c.category in ('data', 'other')
    )
;

select distinct category from mime_categories;




-- audio
-- image
-- video
-- media_container
-- media_support
-- image_support

-- archives

-- email
-- document
-- cad_3d
-- spreadsheet
-- calendar
-- diagram
-- presentation
-- ebook
-- text
-- design
-- science
-- project
-- geo

-- database

-- network
-- security
-- executable
-- installer
-- system
-- font
-- script

-- web

-- apple_metadata
-- unknown
-- data
-- other



SELECT
    split_part(regexp_replace(p.file_path, '/+$', ''), '/', -1) AS file_name,
    CASE
        WHEN split_part(regexp_replace(p.file_path, '/+$', ''), '/', -1) = '' THEN NULL
        -- filename starts with '.' -> ignore that first dot when deciding extension
        WHEN split_part(regexp_replace(p.file_path, '/+$', ''), '/', -1) LIKE '.%' THEN
            CASE
                WHEN position('.' in reverse(substr(split_part(regexp_replace(p.file_path, '/+$', ''), '/', -1), 2))) IN (0, 1)
                    THEN NULL
                ELSE lower(split_part(substr(split_part(regexp_replace(p.file_path, '/+$', ''), '/', -1), 2), '.', -1))
                END
        -- normal filename
        ELSE
            CASE
                WHEN position('.' in reverse(split_part(regexp_replace(p.file_path, '/+$', ''), '/', -1))) IN (0, 1)
                    THEN NULL
                ELSE lower(split_part(split_part(regexp_replace(p.file_path, '/+$', ''), '/', -1), '.', -1))
                END
        END AS file_ext
FROM files_primary p;