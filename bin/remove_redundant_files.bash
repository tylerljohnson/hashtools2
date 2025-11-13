#!/usr/bin/env bash
#
# remove_redundant_files.bash
#
# Default: dry-run (no deletions). Use --force to delete.
# Optional: --prefix <path> to restrict by full_path prefix.
# Optional: --sync-db to delete matching rows from the hashes table after FS reconciliation.
#
# Symbols per row:
#   🔎 <hash> <mime>                 (would remove; dry-run, file exists)
#   ⚠️  <hash> <mime> (missing file)  (dry-run: DB row stale; no changes)
#   ✅ <hash> <mime>                 (removed file; DB row removed if --sync-db)
#   ⚠️  <hash> <mime> (missing file)  (force: DB row removed if --sync-db)
#   ❌ <hash> <mime> (reason)         (failed remove; DB row kept)
#
# Env: PGHOST, PGUSER, PGDATABASE
set -euo pipefail

# --- Config (env-overridable) ---
PGHOST="${PGHOST:-cooper}"
PGUSER="${PGUSER:-tyler}"
PGDATABASE="${PGDATABASE:-tyler}"

GREEN='\033[0;32m'; RED='\033[0;31m'; RESET='\033[0m'

FORCE=false
SYNC_DB=false
PREFIX_FILTER=""

usage() {
  cat >&2 <<USAGE
Usage: $0 [--force] [--sync-db] [--prefix <path>]

  --force      Actually delete files (default is dry-run).
  --sync-db    After deletions, remove corresponding rows from the 'hashes' table.
  --prefix P   Only operate on rows whose full_path starts with P.

Env:
  PGHOST, PGUSER, PGDATABASE (defaults: cooper, tyler, tyler)
USAGE
  exit 1
}

# --- Parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)   FORCE=true; shift ;;
    --sync-db) SYNC_DB=true; shift ;;
    --prefix)
      [[ $# -ge 2 ]] || { echo "ERROR: --prefix requires a value" >&2; usage; }
      PREFIX_FILTER="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "ERROR: Unknown arg: $1" >&2; usage ;;
  esac
done

# --- Logging ---
LOG_TS="$(date +%Y%m%d_%H%M%S)"
LOGFILE="redundant_removal_${LOG_TS}.log"
OK_PATHS="deleted_full_paths_${LOG_TS}.txt"   # paths to delete from DB (files removed OR missing; only used in --force)

MODE=$([[ $FORCE == true ]] && echo "REAL-DELETION" || echo "DRY-RUN")
echo "[*] Mode: $MODE"
echo "[*] Log file: $LOGFILE"
[[ $FORCE == true ]] && echo "[*] Removed/Orphan path list (for DB sync): $OK_PATHS"
[[ -n "$PREFIX_FILTER" ]] && echo "[*] Prefix filter: $PREFIX_FILTER"

{
  echo "===== $(date) ====="
  echo "Mode: $MODE"
  [[ -n "$PREFIX_FILTER" ]] && echo "Prefix: $PREFIX_FILTER"
} >> "$LOGFILE"

# --- Build SQL ---
if [[ -n "$PREFIX_FILTER" ]]; then
  esc_prefix="${PREFIX_FILTER//\'/\'\'}"
  SQL="SELECT mime_type, hash, full_path FROM files_redundant WHERE full_path LIKE '${esc_prefix}%';"
else
  SQL="SELECT mime_type, hash, full_path FROM files_redundant;"
fi

# Only create/reset OK_PATHS when we might actually use it (force mode).
$FORCE && : > "$OK_PATHS" || true

# --- Execute query and process results ---
psql -h "$PGHOST" -U "$PGUSER" -d "$PGDATABASE" -At -F $'\t' -c "$SQL" |
while IFS=$'\t' read -r mime hash path; do
  [[ -z "${hash:-}" && -z "${mime:-}" && -z "${path:-}" ]] && continue

  if [[ "$FORCE" == false ]]; then
    # DRY-RUN: detect state, no changes
    if [[ -f "$path" ]]; then
      echo "🔎 ${hash} ${mime}	${path} (would remove)"
      echo "DRY ${hash} ${mime} ${path}" >> "$LOGFILE"
    else
      echo -e "⚠️  ${hash} ${mime} (missing file; DB row stale)"
      echo "DRY-WARN ${hash} ${mime} ${path} (missing; stale DB row)" >> "$LOGFILE"
    fi
    continue
  fi

  # FORCE: actually reconcile
  if [[ -f "$path" ]]; then
    if rm -- "$path"; then
      echo -e "${GREEN}✅${RESET} ${hash} ${mime}"
      echo "OK  ${hash} ${mime} ${path}" >> "$LOGFILE"
      printf '%s\n' "$path" >> "$OK_PATHS"
    else
      echo -e "${RED}❌${RESET} ${hash} ${mime} (failed to remove)"
      echo "ERR ${hash} ${mime} ${path} (failed to remove)" >> "$LOGFILE"
    fi
  else
    # File missing -> DB stale. Warn and queue row for DB deletion (if --sync-db).
    echo -e "⚠️  ${hash} ${mime} (missing file; removing stale DB row if --sync-db)"
    echo "WARN ${hash} ${mime} ${path} (missing; stale DB row)" >> "$LOGFILE"
    printf '%s\n' "$path" >> "$OK_PATHS"
  fi
done

# --- Optional DB sync ---
if [[ "$FORCE" == true && "$SYNC_DB" == true ]]; then
  if [[ -s "$OK_PATHS" ]]; then
    echo "[*] Syncing DB rows for ${PGDATABASE} using $OK_PATHS ..."
    psql -h "$PGHOST" -U "$PGUSER" -d "$PGDATABASE" <<SQL
BEGIN;
CREATE TEMP TABLE to_delete(full_path text);
\copy to_delete FROM '$OK_PATHS' WITH (FORMAT text)
DELETE FROM hashes h USING to_delete t WHERE h.full_path = t.full_path;
ANALYZE hashes;
COMMIT;
SQL
    echo "[*] DB sync complete."
  else
    echo "[*] No paths to sync into DB."
  fi
else
  if [[ "$FORCE" == true && "$SYNC_DB" == false ]]; then
    echo "[*] Skipped DB sync (use --sync-db to remove rows for deleted/missing files)."
  fi
fi

echo "[*] Done. See $LOGFILE"
