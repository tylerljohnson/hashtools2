#!/bin/bash

# ==============================================================================
# find-unvaulted-primaries.bash
#
# Purpose:
#   Identifies "Primary" images that are currently located OUTSIDE the vault,
#   even though a "Redundant" copy of that same image exists INSIDE the vault.
#
# Usage:
#   ./bin/find-unvaulted-primaries.bash [/path/to/vault/base]
# ==============================================================================

VAULT_BASE="${1:-/home/tyler/packrat/vault/secret}"

# Database defaults (mirroring your README)
DB_HOST=${PGHOST:-cooper}
DB_NAME=${PGDATABASE:-tyler}
DB_USER=${PGUSER:-tyler}
DB_PWD=${PGPASSWPRD:-cometdog}

# SQL Logic:
# 1. Get all hashes that have at least one copy in the vault.
# 2. Filter the 'images_primary' view for rows NOT in that vault path.
# 3. Join them to see which primary files are "missing" from the vault
#    despite the vault having the data.
SQL_QUERY=$(cat <<EOF
WITH vault_hashes AS (
    SELECT DISTINCT hash
    FROM files
    WHERE base_path = '$VAULT_BASE'
)
SELECT
    ip.hash,
    ip.mime_type,
    ip.length as size_bytes,
    ROUND(EXTRACT(EPOCH FROM (i_vault.last_modified - ip.last_modified)) / 86400.0, 6) AS delta_days,
    i_vault.id as vault_id,
    ip.id as primary_id,
    ip.last_modified as primary_last_modified,
    i_vault.last_modified as vault_last_modified,
    '"' || ip.full_path || '"' AS primary_full_path,
    '"' || i_vault.full_path || '"' AS vault_full_path
FROM
    images_primary ip
        JOIN vault_hashes vh ON ip.hash = vh.hash
        JOIN images i_vault
             ON i_vault.hash = vh.hash
                 AND i_vault.base_path = '$VAULT_BASE'
WHERE
    ip.base_path <> '$VAULT_BASE'
  AND (i_vault.last_modified - ip.last_modified) > interval '0'
ORDER BY
    EXTRACT(EPOCH FROM (i_vault.last_modified - ip.last_modified))
;
EOF
)

echo "Searching for primary images not in vault: $VAULT_BASE"
echo "----------------------------------------------------------------"

psql -h "$DB_HOST" -d "$DB_NAME" -U "$DB_USER" -c "$SQL_QUERY"s