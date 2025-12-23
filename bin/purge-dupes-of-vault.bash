#!/usr/bin/env bash
#
# purge-dupes-of-vault.bash
#
# Lists duplicates of PRIMARY files that live in the vault base_path
# (/Volumes/vault/secret), using the Postgres `files_primary` and `files`
# views/tables.
#
# Default output (TSV):
#   hash    mime_type   other_full_path
#
# With --all:
#   hash  mime_type  vault_last_modified  dupe_last_modified  deltaDays  other_base_path  other_full_path
#
# With --purge:
#   DRY RUN by default. For each duplicate path (other_full_path), check it and report:
#     other_full_path<TAB>status
#
#   Status values:
#     missing          - path does not exist
#     not-regular      - exists but is not a regular file
#     no-permission    - exists, regular, but not writable
#     would-remove     - (dry run) exists, regular, writable, would be removed with --no-dry-run
#     removed          - actually removed (only when --purge AND --no-dry-run)
#     rm-failed        - rm attempted but failed
#     skipped-in-vault - safety guard: resolved under vault base path, not touched
#
# Env: use ~/.pgpass or
#   PGHOST (default: cooper)
#   PGPORT (default: 5432)
#   PGUSER (default: tyler)
#   PGDATABASE (default: tyler)
#
# Usage:
#   ./purge-dupes-of-vault.bash
#   ./purge-dupes-of-vault.bash --all
#   ./purge-dupes-of-vault.bash --purge
#   ./purge-dupes-of-vault.bash --purge --no-dry-run
#

set -euo pipefail

DB_HOST="${PGHOST:-cooper}"
DB_PORT="${PGPORT:-5432}"
DB_USER="${PGUSER:-tyler}"
DB_DATABASE="${PGDATABASE:-tyler}"

VAULT_BASE="/Volumes/vault/secret"
SHOW_ALL=0
PURGE=0
NO_DRY_RUN=0

print_usage() {
  cat >&2 <<EOF
Usage: $0 [--all] [--purge] [--no-dry-run]

Options:
  -a, --all        Show all columns from the query (full detail).
  -p, --purge      Purge mode (DRY RUN by default).
                   In this mode, the script prints:
                     other_full_path<TAB>status
  --no-dry-run     Only meaningful with --purge.
                   If provided together with --purge, files will actually be removed.
                   Without --no-dry-run, --purge is a dry-run (no deletions).
  -h, --help       Show this help message and exit.

Vault base path is fixed to: $VAULT_BASE
EOF
}

# --- Parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--all)
      SHOW_ALL=1
      shift
      ;;
    -p|--purge)
      PURGE=1
      shift
      ;;
    --no-dry-run)
      NO_DRY_RUN=1
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      print_usage
      exit 1
      ;;
  esac
done

# --- Robustness checks ---

# Ensure psql exists
if ! command -v psql >/dev/null 2>&1; then
  echo "ERROR: psql not found in PATH." >&2
  exit 1
fi

# Warn if vault directory doesn't exist on this host
if [[ ! -d "$VAULT_BASE" ]]; then
  echo "WARNING: Vault base path does not exist on this host: $VAULT_BASE" >&2
fi

# If we're purging, we don't care about --all output formatting
if [[ "$PURGE" -eq 1 ]]; then
  SHOW_ALL=0
fi

# Purge is only "real" if no-dry-run is set
DO_DELETE=0
if [[ "$PURGE" -eq 1 && "$NO_DRY_RUN" -eq 1 ]]; then
  DO_DELETE=1
fi

# Banner for purge mode
if [[ "$PURGE" -eq 1 ]]; then
  if [[ "$DO_DELETE" -eq 1 ]]; then
    echo "[*] purge mode: LIVE (deletions enabled via --no-dry-run)" >&2
  else
    echo "[*] purge mode: DRY RUN (no deletions; status=would-remove)" >&2
  fi
fi

# --- Build SQL with bash interpolation (no psql variables) ---

# Common CTE part
read -r -d '' SQL_COMMON <<SQL || true
WITH vault_primary AS (
    SELECT
        hash,
        mime_type,
        base_path,
        file_path,
        full_path,
        last_modified
    FROM files_primary
    WHERE base_path = '$VAULT_BASE'
),
dupes AS (
    SELECT
        vp.hash,
        vp.mime_type,
        vp.full_path     AS vault_full_path,
        vp.last_modified AS vault_last_modified,
        f.full_path      AS other_full_path,
        f.last_modified  AS other_last_modified,
        f.base_path      AS other_base_path,
        f.disposition    AS other_disposition,
        ROUND(EXTRACT(EPOCH FROM (f.last_modified - vp.last_modified)) / 86400, 6) AS deltaDays
    FROM vault_primary vp
    JOIN files f
      ON f.hash = vp.hash
     AND f.mime_type = vp.mime_type
     AND f.full_path <> vp.full_path
     AND f.base_path <> '$VAULT_BASE'          -- never report vault files as "other"
)
SQL

# Full-column SELECT (for --all)
read -r -d '' SQL_FULL <<'SQL' || true
SELECT
    hash,
    mime_type,
    vault_last_modified,
    other_last_modified AS dupe_last_modified,
    deltaDays,
    other_base_path,
    other_full_path
FROM dupes
WHERE deltaDays >= 0
ORDER BY
    EXTRACT(EPOCH FROM (other_last_modified - vault_last_modified)) DESC,
    hash,
    mime_type;
SQL

# Short SELECT (default, and for purge)
read -r -d '' SQL_SHORT <<'SQL' || true
SELECT
    hash,
    mime_type,
    other_full_path
FROM dupes
WHERE deltaDays >= 0
ORDER BY
    EXTRACT(EPOCH FROM (other_last_modified - vault_last_modified)) DESC,
    hash,
    mime_type;
SQL

if [[ "$SHOW_ALL" -eq 1 ]]; then
  SQL="${SQL_COMMON}
${SQL_FULL}"
else
  SQL="${SQL_COMMON}
${SQL_SHORT}"
fi

if [[ "$PURGE" -eq 0 ]]; then
  # Normal listing mode
  psql \
    -h "$DB_HOST" \
    -p "$DB_PORT" \
    -U "$DB_USER" \
    -d "$DB_DATABASE" \
    -X \
    --tuples-only \
    --no-align \
    -F $'\t' \
    -c "$SQL"

  echo "Done." >&2
else
  # Purge mode: stream psql output into while loop via a pipe
  psql \
    -h "$DB_HOST" \
    -p "$DB_PORT" \
    -U "$DB_USER" \
    -d "$DB_DATABASE" \
    -X \
    --tuples-only \
    --no-align \
    -F $'\t' \
    -c "$SQL" \
  | {
      removed=0
      would_remove=0
      missing=0
      not_regular=0
      no_permission=0
      rm_failed=0
      skipped_in_vault=0

      while IFS=$'\t' read -r hash mime other_full_path; do
        # Skip empty lines defensively
        if [[ -z "${other_full_path:-}" ]]; then
          continue
        fi

        status=""

        # Hard safety: never touch anything under the vault base path
        case "$other_full_path" in
          "$VAULT_BASE"|"$VAULT_BASE"/*)
            status="skipped-in-vault"
            skipped_in_vault=$((skipped_in_vault+1))
            printf '%s\t%s\n' "$other_full_path" "$status"
            continue
            ;;
        esac

        if [[ ! -e "$other_full_path" ]]; then
          status="missing"
          missing=$((missing+1))
        elif [[ ! -f "$other_full_path" ]]; then
          status="not-regular"
          not_regular=$((not_regular+1))
        elif [[ ! -w "$other_full_path" ]]; then
          status="no-permission"
          no_permission=$((no_permission+1))
        elif [[ "$DO_DELETE" -eq 1 ]]; then
          # Real delete
          if rm -f -- "$other_full_path"; then
            status="removed"
            removed=$((removed+1))
          else
            status="rm-failed"
            rm_failed=$((rm_failed+1))
          fi
        else
          # Dry-run delete
          status="would-remove"
          would_remove=$((would_remove+1))
        fi

        # Progress: path<TAB>status
        printf '%s\t%s\n' "$other_full_path" "$status"
      done

      # Summary goes to stderr
      echo "[*] Summary:" >&2
      echo "    removed=$removed would_remove=$would_remove missing=$missing not_regular=$not_regular no_permission=$no_permission rm_failed=$rm_failed skipped_in_vault=$skipped_in_vault" >&2
      echo "Done." >&2
    }
fi
