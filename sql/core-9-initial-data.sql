INSERT INTO base_paths (base_path, priority, is_vault)
SELECT base_path,
       ROW_NUMBER() OVER (ORDER BY base_path) AS priority,
       FALSE AS is_vault
FROM (SELECT DISTINCT base_path FROM hashes) d
ON CONFLICT (base_path) DO NOTHING;

update base_paths set priority = 10, is_vault=true  where base_path = '/home/tyler/packrat/vault/secret';
update base_paths set priority = 20, is_vault=false where base_path = '/home/tyler/packrat/vault/unique';
update base_paths set priority = 30, is_vault=false where base_path = '/home/tyler/packrat/vault/mail-files';
update base_paths set priority = 40, is_vault=false where base_path = '/media/tyler/red';
update base_paths set priority = 50, is_vault=false where base_path = '/media/tyler/green';
update base_paths set priority = 60, is_vault=false where base_path = '/media/tyler/blue';
