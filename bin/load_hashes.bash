#!/usr/bin/env bash
#
# load_hashes.bash
# Loads one or more .hashes (TSV) files into the 'hashes' table in PostgreSQL.
#
# Usage:
#   ./load_hashes.bash <path-to-file> [<path-to-file> ...]
#   ./load_hashes.bash all.hashes other.hashes
#
# Env: PGHOST, PGPORT, PGUSER, PGDATABASE (defaults: cooper, 5432, tyler, tyler) or use ~/.pgpass
#

set -euo pipefail

DB_HOST="${PGHOST:-cooper}"
DB_PORT="${PGPORT:-5432}"
DB_USER="${PGUSER:-tyler}"
DB_DATABASE="${PGDATABASE:-tyler}"

# --- Parse args ---
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <file.hashes> [<file.hashes> ...]" >&2
  exit 1
fi

echo "[*] Target database: $DB_DATABASE@$DB_HOST"

for HASHFILE in "$@"; do
  if [[ ! -f "$HASHFILE" ]]; then
    echo "WARNING: File not found: $HASHFILE (skipping)" >&2
    continue
  fi

  echo "[*] Importing data from '$HASHFILE'..."
  if ! psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_DATABASE" \
    -c "\copy hashes(hash,last_modified,file_size,mime_type,base_path,file_path) FROM '${HASHFILE}' WITH (FORMAT CSV, DELIMITER E'\t', HEADER FALSE, ENCODING 'UTF8');"
  then
    echo "ERROR: psql failed while importing '$HASHFILE'." >&2
    exit 1
  fi

  echo "[*] Done. Data loaded from '$HASHFILE'."
done

