#!/usr/bin/env bash
#
# vault_timestamp_drift_fix.bash
#
# Purpose:
#   Interactive exception handler for vault timestamp drift.
#   For each (hash, mime_type) group where the oldest copy is NOT in a vault but a
#   vault copy exists, present choices:
#     1) Make vault inherit the group's oldest last_modified (FS + DB)
#     2) Remove the non-vault oldest file + delete its DB row
#     s) Skip (do nothing, continue)
#     q) Quit (do nothing for this row, exit immediately)
#
# Defaults:
#   host=cooper port=5432 user=tyler db=tyler
#
# Safety:
#   By default, this script does NOT modify anything (preview mode).
#   Use --commit to actually apply filesystem + DB changes.
#
# Tooling:
#   --install-tools runs preview-tooling.bash (report mode) and exits.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CHECK_TOOLCHAIN="${SCRIPT_DIR}/preview-tooling.bash"
PREVIEW="${SCRIPT_DIR}/preview.bash"

# -------------------------------
# Defaults / args
# -------------------------------
PGHOST="${PGHOST:-cooper}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-tyler}"
PGDATABASE="${PGDATABASE:-tyler}"

COMMIT=false
FORCE_DELETE=false
INSTALL_TOOLS=false

usage() {
  cat <<'EOF'
Usage:
  vault_timestamp_drift_fix.bash [options]

Options:
  --host HOST           (default: cooper)
  --port PORT           (default: 5432)
  --user USER           (default: tyler)
  --db   DB             (default: tyler)
  --commit              actually apply filesystem + DB changes (default: preview only)
  --delete              use rm --force instead of trash when removing files
  --install-tools       run preview-tooling.bash (report mode) and exit
  -h|--help             show help
EOF
}

# Arg parsing with validation for required option arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      if [[ -z "${2:-}" || "${2:0:1}" = "-" ]]; then
        echo "ERROR: --host requires an argument" >&2; usage; exit 2
      fi
      PGHOST="$2"; shift 2;;
    --port)
      if [[ -z "${2:-}" || "${2:0:1}" = "-" ]]; then
        echo "ERROR: --port requires an argument" >&2; usage; exit 2
      fi
      PGPORT="$2"; shift 2;;
    --user)
      if [[ -z "${2:-}" || "${2:0:1}" = "-" ]]; then
        echo "ERROR: --user requires an argument" >&2; usage; exit 2
      fi
      PGUSER="$2"; shift 2;;
    --db)
      if [[ -z "${2:-}" || "${2:0:1}" = "-" ]]; then
        echo "ERROR: --db requires an argument" >&2; usage; exit 2
      fi
      PGDATABASE="$2"; shift 2;;
    --commit) COMMIT=true; shift;;
    --delete) FORCE_DELETE=true; shift;;
    --install-tools) INSTALL_TOOLS=true; shift;;
    -h|--help) usage; exit 0;;
    *) echo "ERROR: Unknown arg: $1" >&2; usage; exit 2;;
  esac
done

have() { command -v "$1" >/dev/null 2>&1; }

IS_MAC=false
[[ "${OSTYPE:-}" == darwin* ]] && IS_MAC=true

# MUST run first (and exit) if requested
if [ "${INSTALL_TOOLS}" = true ]; then
  if [[ -x "$CHECK_TOOLCHAIN" ]]; then
    "$CHECK_TOOLCHAIN"
    exit 0
  fi
  echo "ERROR: missing executable: $CHECK_TOOLCHAIN" >&2
  exit 1
fi

# Prefer to run preview script directly if executable, otherwise fall back to bash <file>
if [[ -x "$PREVIEW" ]]; then
  PREVIEW_CMD=("$PREVIEW")
elif [[ -f "$PREVIEW" ]]; then
  PREVIEW_CMD=( bash "$PREVIEW" )
else
  echo "ERROR: missing preview script: $PREVIEW" >&2
  exit 1
fi

if ! have psql; then
  echo "ERROR: psql not found in PATH" >&2
  exit 1
fi

PSQL=(
  psql
  --no-psqlrc
  --set=ON_ERROR_STOP=1
  --quiet
  --tuples-only
  --no-align
  --field-separator=$'\t'
  --host "$PGHOST"
  --port "$PGPORT"
  --username "$PGUSER"
  --dbname "$PGDATABASE"
)

echo "# host=$PGHOST port=$PGPORT user=$PGUSER db=$PGDATABASE"
echo "# commit=$COMMIT delete=$FORCE_DELETE"

# -------------------------------
# Terminal layout helpers
# -------------------------------
TERM_COLS="$(tput cols 2>/dev/null || echo 120)"
HALF=$(( (TERM_COLS - 3) / 2 ))
if (( HALF < 0 )); then HALF=0; fi
SEP="$(printf '%*s' "$TERM_COLS" '' | tr ' ' '-')"

truncate_to() {
  local s="$1" w="$2"
  if (( w <= 0 )); then printf "%s" ""; return; fi
  if (( ${#s} <= w )); then printf "%s" "$s"; return; fi
  if (( w < 12 )); then printf "%s" "${s:0:w}"; return; fi
  local head=$(( w - 10 ))
  printf "%s...%s" "${s:0:head}" "${s: -7}"
}

print_lr() {
  local l r
  l="$(truncate_to "$1" "$HALF")"
  r="$(truncate_to "$2" "$HALF")"
  if (( HALF > 0 )); then
    printf "%-*s | %s\n" "$HALF" "$l" "$r"
  else
    printf "%s | %s\n" "$l" "$r"
  fi
}

# -------------------------------
# FS / DB helpers
# -------------------------------
touch_mtime() {
  local file="$1"
  local ts="$2"  # "YYYY-MM-DD HH:MM:SS"

  if [ "${IS_MAC}" = true ]; then
    local t
    t="$(date -j -f '%Y-%m-%d %H:%M:%S' "$ts" '+%Y%m%d%H%M.%S')" || return 1
    touch -t "$t" "$file"
  else
    touch --date="$ts" -- "$file"
  fi
}

trash_or_delete() {
  local file="$1"

  if [ "${FORCE_DELETE}" = true ]; then
    rm -f -- "$file"
    return
  fi

  if [ "${IS_MAC}" = true ]; then
    mkdir -p "$HOME/.Trash"
    mv -f -- "$file" "$HOME/.Trash/"
    return
  fi

  if have gio; then
    gio trash -- "$file"
    return
  fi

  rm -f -- "$file"
}

run_update_vault_ts() {
  local vault_id="$1"
  local target_ts="$2"

  "${PSQL[@]}" --set=vault_id="$vault_id" --set=target_ts="$target_ts" <<'SQL'
UPDATE hashes
SET last_modified = :'target_ts'::timestamp
WHERE id = :vault_id::bigint;
SQL
}

run_delete_oldest_row() {
  local oldest_id="$1"

  "${PSQL[@]}" --set=oldest_id="$oldest_id" <<'SQL'
DELETE FROM hashes
WHERE id = :oldest_id::bigint;
SQL
}

# -------------------------------
# Query rows (TSV)
# -------------------------------
TMP="$(mktemp 2>/dev/null || mktemp -t vault_timestamp_drift_fix)"
trap 'rm -f "$TMP"' EXIT

"${PSQL[@]}" <<'SQL' >"$TMP"
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
SQL

if [[ ! -s "$TMP" ]]; then
  echo "No drift rows found."
  exit 0
fi

# -------------------------------
# Interactive processing
# -------------------------------
row_num=0

# Open a file descriptor for interactive user input from the terminal.
# If /dev/tty isn't available, fall back to stdin so the script can still work
# in non-interactive environments (but prompts may not be visible).
if [[ -e /dev/tty ]]; then
  exec 3</dev/tty
else
  exec 3<&0
fi

while IFS=$'\t' read -r hash mime oldest_id oldest_full_path target_ts vault_id vault_full_path vault_ts drift_seconds; do
  row_num=$((row_num + 1))

  echo
  echo "$SEP"
  printf "Row %d  hash=%s  mime=%s  drift_seconds=%s\n" "$row_num" "$hash" "$mime" "$drift_seconds"
  echo

  # Centered vault preview in middle third of the screen
  "${PREVIEW_CMD[@]}" --mime "$mime" --center --width-third --max-width 120 --max-height 24 --text-lines 60 "$vault_full_path"
  echo

  print_lr "OLDEST (non-vault)" "VAULT (canonical)"
  print_lr "id: $oldest_id"     "id: $vault_id"
  print_lr "path: $oldest_full_path" "path: $vault_full_path"
  print_lr "last_modified: $target_ts" "last_modified: $vault_ts"

  echo
  if [ "$COMMIT" != true ]; then
    echo "NOTE: preview mode (no changes). Use --commit to apply."
    echo
  fi

  while true; do
    printf "Action: [1] vault inherits oldest  [2] remove oldest file+row  [s] skip  [q] quit : "
    # Read the user's choice from the terminal FD 3 to avoid consuming the TSV input
    if ! read -r -u 3 choice; then
      # If read fails (e.g., no TTY), treat as a skip to avoid an infinite loop
      echo
      echo "(no interactive input available; skipping)"
      choice='s'
    fi

    case "$choice" in
      1)
        if [[ ! -e "$vault_full_path" ]]; then
          echo "ERROR: vault file not found on filesystem: $vault_full_path"
          echo "Skipped."
          break
        fi

        if [ "$COMMIT" != true ]; then
          echo "PREVIEW: touch vault mtime -> $target_ts"
          echo "PREVIEW: UPDATE hashes SET last_modified='$target_ts' WHERE id=$vault_id"
          break
        fi

        echo "Touching vault file mtime..."
        touch_mtime "$vault_full_path" "$target_ts"
        echo "Updating DB..."
        run_update_vault_ts "$vault_id" "$target_ts"
        echo "Done."
        break
        ;;
      2)
        if [ "$COMMIT" != true ]; then
          echo "PREVIEW: remove file -> $oldest_full_path"
          echo "PREVIEW: DELETE FROM hashes WHERE id=$oldest_id"
          break
        fi

        if [[ -e "$oldest_full_path" ]]; then
          echo "Removing oldest non-vault file..."
          trash_or_delete "$oldest_full_path"
        else
          echo "WARN: oldest file not found on filesystem (will still delete DB row): $oldest_full_path"
        fi

        echo "Deleting DB row..."
        run_delete_oldest_row "$oldest_id"
        echo "Done."
        break
        ;;
      s|S)
        echo "Skipped."
        break
        ;;
      q|Q)
        echo "Quit (no action taken for this row)."
        # Close FD 3 before exiting
        exec 3<&-
        exit 0
        ;;
      *)
        echo "Invalid choice."
        ;;
    esac
  done

done <"$TMP"

# Close the interactive file descriptor
exec 3<&-

echo
echo "Finished."
