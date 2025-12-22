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

# SQL Logic:
# 1. Get all hashes that have at least one copy in the vault.
# 2. Filter the 'images_primary' view for rows NOT in that vault path.
# 3. Join them to see which primary files are "missing" from the vault
#    despite the vault having the data.
SQL_QUERY=$(cat <<EOF
WITH vault_hashes AS (
    SELECT DISTINCT hash
    FROM images
    WHERE base_path = '$VAULT_BASE'
)
SELECT
    ip.hash,
    ip.full_path AS primary_location,
    ip.last_modified AS primary_time,
    i_vault.full_path AS vault_copy_location,
    i_vault.disposition AS vault_copy_status
FROM images_primary ip
JOIN vault_hashes vh ON ip.hash = vh.hash
JOIN images i_vault ON i_vault.hash = vh.hash AND i_vault.base_path = '$VAULT_BASE'
WHERE ip.base_path <> '$VAULT_BASE'
ORDER BY ip.last_modified ASC;
EOF
)

echo "Searching for primary images not in vault: $VAULT_BASE"
echo "----------------------------------------------------------------"

psql -h "$DB_HOST" -d "$DB_NAME" -U "$DB_USER" -c "$SQL_QUERY"