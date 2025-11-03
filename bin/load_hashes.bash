#!/usr/bin/env bash
#
# load_hashes.bash
# Loads a .hashes (TSV) file into the 'hashes' table in PostgreSQL.
#
# Env: PGHOST, PGUSER, PGDATABASE (defaults: cooper, tyler, tyler)
# Usage:
#   ./load_hashes.bash <path-to-file>
#   ./load_hashes.bash all.hashes
#

set -euo pipefail

PGHOST="${PGHOST:-cooper}"
PGUSER="${PGUSER:-tyler}"
PGDATABASE="${PGDATABASE:-tyler}"

# --- Parse args ---
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <file.hashes>" >&2
  exit 1
fi

HASHFILE="$1"

if [[ ! -f "$HASHFILE" ]]; then
  echo "ERROR: File not found: $HASHFILE" >&2
  exit 1
fi

echo "[*] Target database: $PGDATABASE@$PGHOST"

# --- Load the data ---
echo "[*] Importing data..."
psql -h "$PGHOST" -U "$PGUSER" -d "$PGDATABASE" -c "\copy hashes(hash,last_modified,file_size,mime_type,base_path,file_path) FROM '${HASHFILE}' WITH (FORMAT CSV, DELIMITER E'\t', HEADER FALSE, ENCODING 'UTF8');"

echo "[*] Done. Data loaded from '$HASHFILE'."
