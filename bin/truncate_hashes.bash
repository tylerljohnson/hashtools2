#!/usr/bin/env bash
#
# truncate_hashes.bash
# Safely truncates the 'hashes' table in the configured PostgreSQL database.
# Asks for confirmation before proceeding.
#
# Env: PGHOST, PGUSER, PGDATABASE (defaults to cooper, tyler, tyler)

set -euo pipefail

PGHOST="${PGHOST:-cooper}"
PGUSER="${PGUSER:-tyler}"
PGDATABASE="${PGDATABASE:-tyler}"

echo "⚠️  WARNING: This will permanently remove all rows from the 'hashes' table in database '$PGDATABASE' on host '$PGHOST'."
read -rp "Type 'yes' to continue: " confirm

if [[ "$confirm" != "yes" ]]; then
  echo "Aborted."
  exit 1
fi

echo "[*] Truncating table 'hashes'..."
psql -h "$PGHOST" -U "$PGUSER" -d "$PGDATABASE" -c "TRUNCATE TABLE hashes RESTART IDENTITY;"

echo "[*] Done. The 'hashes' table has been truncated and sequence reset."
