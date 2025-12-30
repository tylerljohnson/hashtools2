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
from mime_category c, files_primary p
where p.mime_type = c.mime_type
group by c.category
order by sum(p.length) desc
;

-- extract the last segment of the base path
SELECT split_part(regexp_replace(base_path, '/+$', ''), '/', -1) AS base_name
     , base_path, file_path
from files_primary
;