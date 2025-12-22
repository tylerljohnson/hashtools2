#!/usr/bin/env bash
#
# delete_hashes_from_missing_rows.bash
#
# PURPOSE:
#   Fast deletion of rows from Postgres table "hashes" by importing IDs from
#   missing_rows_*.tsv into a TEMP table, then deleting via JOIN:
#     1) \copy IDs into TEMP table
#     2) DELETE ... USING temp table
#
# REQUIREMENTS:
#   - psql in PATH
#   - Auth via PGPASSWORD env var or ~/.pgpass
#

set -euo pipefail

# -----[ Credentials / Connection ]-----
PGHOST="${PGHOST:-cooper}"
PGUSER="${PGUSER:-tyler}"
PGDATABASE="${PGDATABASE:-tyler}"
PGPORT="${PGPORT:-5432}"

# -----[ Options ]-----
DIR="."
DRY_RUN=0
VACUUM_AFTER=0

usage() {
  cat <<'EOF'
Usage:
  delete_hashes_from_missing_rows.bash [--dir PATH] [--dry-run] [--vacuum]

Options:
  --dir PATH    Directory to scan for missing_rows_*.tsv (default: .)
  --dry-run     Do not delete; only report how many rows would be deleted
  --vacuum      Run VACUUM (ANALYZE) hashes after each file (can be slow)

Environment:
  PGHOST, PGPORT, PGUSER, PGDATABASE, PGPASSWORD (or ~/.pgpass)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) DIR="${2:?missing value for --dir}"; shift 2;;
    --dry-run) DRY_RUN=1; shift;;
    --vacuum) VACUUM_AFTER=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "ERROR: unknown arg: $1" >&2; usage; exit 2;;
  esac
done

command -v psql >/dev/null 2>&1 || { echo "ERROR: psql not found in PATH" >&2; exit 1; }

shopt -s nullglob
files=( "$DIR"/missing_rows_*.tsv )
shopt -u nullglob

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No files found: $DIR/missing_rows_*.tsv" >&2
  exit 0
fi

psql_base=( psql -X -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" )

detect_header() {
  local f="$1"
  local first
  first="$(head -n 1 "$f" | awk -F $'\t' '{print $1}')"
  first="$(printf '%s' "$first" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [[ ! "$first" =~ ^[0-9]+$ ]]
}

count_bad_first_col_rows() {
  local f="$1"
  local has_header="$2"

  if [[ "$has_header" -eq 1 ]]; then
    tail -n +2 "$f"
  else
    cat "$f"
  fi | awk -F'\t' '
    {
      id=$1
      gsub(/\r/, "", id)
      gsub(/^[ \t]+|[ \t]+$/, "", id)
      if (id !~ /^[0-9]+$/) bad++
    }
    END { print (bad+0) }
  '
}

stream_good_ids() {
  local f="$1"
  local has_header="$2"

  if [[ "$has_header" -eq 1 ]]; then
    tail -n +2 "$f"
  else
    cat "$f"
  fi | awk -F'\t' '
    {
      id=$1
      gsub(/\r/, "", id)
      gsub(/^[ \t]+|[ \t]+$/, "", id)
      if (id ~ /^[0-9]+$/) print id
    }
  '
}

echo "# host=$PGHOST port=$PGPORT user=$PGUSER db=$PGDATABASE"
echo "# dir=$DIR dry_run=$DRY_RUN vacuum_after=$VACUUM_AFTER"
echo

for f in "${files[@]}"; do
  if [[ ! -s "$f" ]]; then
    echo "==> Skipping empty file: $f"
    continue
  fi

  has_header=0
  if detect_header "$f"; then
    has_header=1
  fi

  bad_count="$(count_bad_first_col_rows "$f" "$has_header")"

  echo "==> Processing: $f"
  echo "    header=$has_header bad_first_col_rows=$bad_count"

  (
    # IMPORTANT:
    # After \copy ... FROM STDIN, psql enters COPY mode immediately.
    # So the *next* bytes must be the data (IDs), and then \. to end COPY.
    cat <<'SQL'
BEGIN;

CREATE TEMP TABLE tmp_delete_ids (
  id bigint PRIMARY KEY
) ON COMMIT DROP;

\copy tmp_delete_ids(id) FROM STDIN WITH (FORMAT text);
SQL

    # COPY DATA (IDs only)
    stream_good_ids "$f" "$has_header"

    # End COPY
    printf '%s\n' '\.'

    # Now it's safe to send normal SQL again
    cat <<SQL
ANALYZE tmp_delete_ids;

SELECT COUNT(*) AS loaded_ids FROM tmp_delete_ids;

$(if [[ "$DRY_RUN" -eq 1 ]]; then
  cat <<'SQL2'
SELECT COUNT(*) AS would_delete
FROM hashes h
JOIN tmp_delete_ids t ON t.id = h.id;
SQL2
else
  cat <<'SQL2'
DELETE FROM hashes h
USING tmp_delete_ids t
WHERE h.id = t.id;
SQL2
fi)

COMMIT;
SQL

    if [[ "$VACUUM_AFTER" -eq 1 && "$DRY_RUN" -eq 0 ]]; then
      cat <<'SQLV'
VACUUM (ANALYZE) hashes;
SQLV
    fi
  ) | "${psql_base[@]}"

  echo
done

echo "Done."
