#!/usr/bin/env bash
# Simple archive-manager scaffold
# - list mode (default): runs a DB query (psql) to list candidate pairs
# - fix mode (--fix): swaps timestamps for each candidate (safe swap using a temp file)

set -euo pipefail

SCRIPT_NAME=$(basename "$0")
# Database connection defaults (can be overridden via env vars)
# host, database, user, password
DB_HOST="${DB_HOST:-cooper}"
DB_NAME="${DB_NAME:-tyler}"
DB_USER="${DB_USER:-tyler}"
DB_PASS="${DB_PASS:-cometdog}"
ARCHIVE_BASE_PATH="${ARCHIVE_BASE_PATH:-/Volumes/vault/secret}"
PSQL_CMD="${PSQL_CMD:-psql}"

usage() {
  printf "%s - manage archive primary/redundant timestamp issues\n\n" "$SCRIPT_NAME"
  printf "Usage: %s [options]\n" "$SCRIPT_NAME"
  cat <<'EOF'
  --archive-path PATH   # OR set ARCHIVE_BASE_PATH env var
  --format tsv|json     # output format for listing (default: tsv)
  --fix                 # apply fixes (timestamp swap)
  --apply               # actually apply changes (default: dry-run)
  --dry-run             # don't modify anything, show actions (default)
  --force               # skip confirmation prompts
  --update-db           # update DB metadata after fix (optional)
  --help                # show this help

Notes:
  Listing mode requires a working `psql` configured via env (PGHOST/PGUSER/PGDATABASE)
  If you run with --fix, ensure you have filesystem permissions to touch files.
EOF
}

if [[ ${#@} -eq 0 ]]; then
  # continue; default is list (dry-run) mode
  :
fi

# Quick-help shortcut: print usage and exit immediately if first arg is --help or -h
if [[ ${1:-} == "--help" || ${1:-} == "-h" ]]; then
  usage
  exit 0
fi

FORMAT=tsv
DO_FIX=0
# default to dry-run mode
DRY_RUN=1
FORCE=0
UPDATE_DB=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --archive-path) ARCHIVE_BASE_PATH="$2"; shift 2;;
    --format) 
      case "$2" in
        tsv|json) FORMAT="$2";;
        *) echo "Invalid format: $2 (must be tsv or json)" >&2; exit 2;;
      esac
      shift 2
      ;;
    --fix) DO_FIX=1; shift;;
    --apply) DRY_RUN=0; shift;;
    --force) FORCE=1; shift;;
    --update-db) UPDATE_DB=1; shift;;
    --help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 2;;
  esac
done

if [[ -z "$ARCHIVE_BASE_PATH" ]]; then
  echo "ARCHIVE_BASE_PATH not set. Provide --archive-path or set ARCHIVE_BASE_PATH env var." >&2
  exit 2
fi

QUERY=$(cat <<SQL
SELECT f.hash,
       f.mime_type,
       f.base_path as primary_base,
       f.file_path as primary_path,
       f.last_modified as primary_last_modified,
       a.base_path as archive_base,
       a.file_path as archive_path,
       a.last_modified as archive_last_modified
FROM files f
JOIN files a ON a.hash = f.hash
            AND a.mime_type = f.mime_type
            AND a.base_path = __ARCHIVE_BASE_PATH__
            AND a.disposition = 'redundant'
WHERE f.disposition = 'primary'
  AND f.base_path != __ARCHIVE_BASE_PATH__
ORDER BY f.hash, f.mime_type;
SQL
)

run_query() {
  # Use psql if available; otherwise print the query and exit
  if command -v "$PSQL_CMD" >/dev/null 2>&1; then
    # Replace placeholder with a safely-quoted SQL string
    archive_esc=$(printf "%s" "$ARCHIVE_BASE_PATH" | sed "s/'/''/g")
    archive_literal="'$archive_esc'"
    q="${QUERY//__ARCHIVE_BASE_PATH__/$archive_literal}"
    PGPASSWORD="${DB_PASS}" "$PSQL_CMD" -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -A -F $'\t' -c "$q"
  else
    echo "psql not found (or not configured). Query to run:" >&2
    echo
    echo "$QUERY" | sed "s/__ARCHIVE_BASE_PATH__/'$ARCHIVE_BASE_PATH'/g"
    return 2
  fi
}

confirm() {
  if [[ $FORCE -eq 1 ]]; then
    return 0
  fi
  read -r -p "Proceed? [y/N] " resp
  case "${resp,,}" in
    y|yes) return 0;;
    *) return 1;;
  esac
}

do_swap_timestamps() {
   local primary_path="$1" archive_path="$2"
   [[ -f "$primary_path" ]] || { echo "Primary missing: $primary_path"; return 1; }
   [[ -f "$archive_path" ]] || { echo "Archive missing: $archive_path"; return 1; }

   #echo "BEFORE:"
   #local fmt="%Y-%m-%d-%H:%M:%S"
   #stat -f "  primary: %Sm (mtime)  %Sa (atime)  %Sc (ctime)  %SB (birth)" -t "$fmt" "$primary_path"
   #stat -f "  archive: %Sm (mtime)  %Sa (atime)  %Sc (ctime)  %SB (birth)" -t "$fmt" "$archive_path"

   if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
     echo "DRY-RUN: would swap times."
     return 0
   fi

   local tmp
   tmp=$(mktemp) || return 1
   trap 'rm -f "$tmp"' RETURN

   touch -r "$archive_path" "$tmp"          || return 1
   touch -r "$primary_path" "$archive_path" || return 1
   touch -r "$tmp" "$primary_path"          || return 1

   #echo "AFTER:"
   #stat -f "  primary: %Sm (mtime)  %Sa (atime)  %Sc (ctime)  %SB (birth)" -t "$fmt" "$primary_path"
   #stat -f "  archive: %Sm (mtime)  %Sa (atime)  %Sc (ctime)  %SB (birth)" -t "$fmt" "$archive_path"
}

process_rows() {
  local rows
  rows=$(run_query) || return $?

  # psql with -A -F '\t' prints rows as tab-separated. Parse each line.
  while IFS=$'\t' read -r hash mime primary_base primary_path primary_ts archive_base archive_path archive_ts; do
    # skip empty lines
    [[ -z "$hash" ]] && continue
    
    # Timestamps come directly from database
    primary_ts="${primary_ts:-N/A}"
    archive_ts="${archive_ts:-N/A}"
    
    if [[ "$FORMAT" == "json" ]]; then
      printf '{\n'
      printf '  "hash": "%s",\n' "$hash"
      printf '  "mime_type": "%s",\n' "$mime"
      printf '  "primary": {\n'
      printf '    "timestamp": "%s",\n' "$primary_ts"
      printf '    "base_path": "%s",\n' "$primary_base"
      printf '    "path": "%s"\n' "$primary_path"
      printf '  },\n'
      printf '  "archive": {\n'
      printf '    "timestamp": "%s",\n' "$archive_ts"
      printf '    "base_path": "%s",\n' "$archive_base"
      printf '    "path": "%s"\n' "$archive_path"
      printf '  }\n'
      printf '}\n'
    else
      # First line: hash and mime type
      printf 'detail:\t%s\t%s\n' "$hash" "$mime"
      # Second line: primary file info with DB timestamp
      printf 'primary:\t%s\t%s\t%s\n' "$primary_ts" "$primary_base" "$primary_path"
      # Third line: archive file info with DB timestamp
      printf 'archive:\t%s\t%s\t%s\n' "$archive_ts" "$archive_base" "$archive_path"
      # Blank line separator
      echo
    fi

    if [[ $DO_FIX -eq 1 ]]; then
      # Construct full paths by combining base_path and file_path
      local primary_full_path="$primary_base/$primary_path"
      local archive_full_path="$archive_base/$archive_path"

      if [[ $DRY_RUN -eq 0 ]]; then
        echo "About to swap timestamps for: $primary_full_path <-> $archive_full_path"
        confirm || { echo "Skipping (not confirmed)"; continue; }
      fi
      do_swap_timestamps "$primary_full_path" "$archive_full_path" || echo "Failed to swap for $primary_full_path"
      if [[ $UPDATE_DB -eq 1 ]]; then
        echo "NOTE: --update-db requested but DB update not implemented in this scaffold."
      fi
    fi
  done <<< "$rows"
}

main() {
  if [[ $DO_FIX -eq 1 ]]; then
    echo "Running in FIX mode"$( [[ $DRY_RUN -eq 1 ]] && echo " (dry-run)" )
  else
    echo "Listing candidates (archive: $ARCHIVE_BASE_PATH)"
  fi
  process_rows
}

main
