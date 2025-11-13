#!/usr/bin/env bash
#
# load_hashes.bash
# Loads one or more .hashes (TSV) files into the 'hashes' table in PostgreSQL.
#
# Env: PGHOST, PGUSER, PGDATABASE (defaults: cooper, tyler, tyler)
# Usage:
#   ./load_hashes.bash <path-to-file> [<path-to-file> ...]
#   ./load_hashes.bash all.hashes other.hashes
#

set -euo pipefail

PGHOST="${PGHOST:-cooper}"
PGUSER="${PGUSER:-tyler}"
PGDATABASE="${PGDATABASE:-tyler}"

# --- Parse args ---
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <file.hashes> [<file.hashes> ...]" >&2
  exit 1
fi

echo "[*] Target database: $PGDATABASE@$PGHOST"

for HASHFILE in "$@"; do
  if [[ ! -f "$HASHFILE" ]]; then
    echo "WARNING: File not found: $HASHFILE (skipping)" >&2
    continue
  fi

  echo "[*] Importing data from '$HASHFILE'..."
  if ! psql -h "$PGHOST" -U "$PGUSER" -d "$PGDATABASE" \
    -c "\copy hashes(hash,last_modified,file_size,mime_type,base_path,file_path) FROM '${HASHFILE}' WITH (FORMAT CSV, DELIMITER E'\t', HEADER FALSE, ENCODING 'UTF8');"
  then
    echo "ERROR: psql failed while importing '$HASHFILE'." >&2
    exit 1
  fi

  echo "[*] Done. Data loaded from '$HASHFILE'."
done

