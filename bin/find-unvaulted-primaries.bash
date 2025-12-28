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
#
# Example:
#   Show vault_id, primary_last_modified & vault_full_path so we can fix the vault file last update timestamp:
#     ./bin/find-unvaulted-primaries.bash | cut -f 5,8,9
#
# Env:
#   - PGHOST, PGPORT, PGUSER, PGDATABASE env var or ~/.pgpass  (defaults: cooper, 5432, tyler, tyler)
#
# ==============================================================================

VAULT_BASE="${1:-/home/tyler/packrat/vault/secret}"

# Database defaults (mirroring your README)
DB_HOST=${PGHOST:-cooper}
DB_PORT=${PGPORT:-5432}
DB_USER=${PGUSER:-tyler}
DB_NAME=${PGDATABASE:-tyler}

# SQL Logic:
# 1. Get all hashes that have at least one copy in the vault.
# 2. Filter the 'images_primary' view for rows NOT in that vault path.
# 3. Join them to see which primary files are "missing" from the vault
#    despite the vault having the data.
SQL_QUERY=$(cat <<EOF
WITH joined AS (
  SELECT h.*, bp.is_vault, bp.priority
  FROM hashes h
  JOIN base_paths bp USING (base_path)
),
oldest AS (
  SELECT DISTINCT ON (hash, mime_type)
    hash, mime_type,
    id AS oldest_id,
    full_path AS oldest_full_path,
    last_modified AS oldest_last_modified,
    is_vault AS oldest_is_vault
  FROM joined
  ORDER BY hash, mime_type, last_modified ASC, priority ASC, id ASC
),
vault_pick AS (
  SELECT DISTINCT ON (hash, mime_type)
    hash, mime_type,
    id AS vault_id,
    full_path AS vault_full_path,
    last_modified AS vault_last_modified
  FROM joined
  WHERE is_vault
  ORDER BY hash, mime_type, priority ASC, id ASC
)
SELECT
  o.hash,
  o.mime_type,
  o.oldest_id,
  o.oldest_full_path,
  to_char(o.oldest_last_modified, 'YYYY-MM-DD HH24:MI:SS') AS target_last_modified,
  v.vault_id,
  v.vault_full_path,
  to_char(v.vault_last_modified, 'YYYY-MM-DD HH24:MI:SS') AS vault_last_modified,
  (EXTRACT(EPOCH FROM (v.vault_last_modified - o.oldest_last_modified)))::bigint AS drift_seconds
FROM oldest o
JOIN vault_pick v USING (hash, mime_type)
WHERE o.oldest_is_vault = FALSE
  AND v.vault_last_modified > o.oldest_last_modified
ORDER BY drift_seconds DESC, o.hash, o.mime_type;
EOF
)

 psql \
      --host="$DB_HOST" \
      --port="$DB_PORT" \
      --dbname="$DB_NAME" \
      --username="$DB_USER" \
      --no-align \
      --field-separator=$'\t' \
      --pset="pager=off" \
      --pset="footer=off" \
      --command="$SQL_QUERY"
