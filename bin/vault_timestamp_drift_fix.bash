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
#   Use --install-tools to see recommended install commands for missing preview tools,
#   then exit without processing any rows.
#

set -euo pipefail

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
  --install-tools       show recommended install commands for missing preview tools, then exit
  -h|--help             show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)   PGHOST="$2"; shift 2;;
    --port)   PGPORT="$2"; shift 2;;
    --user)   PGUSER="$2"; shift 2;;
    --db)     PGDATABASE="$2"; shift 2;;
    --commit) COMMIT=true; shift;;
    --delete) FORCE_DELETE=true; shift;;
    --install-tools) INSTALL_TOOLS=true; shift;;
    -h|--help) usage; exit 0;;
    *) echo "ERROR: Unknown arg: $1" >&2; usage; exit 2;;
  esac
done

IS_MAC=false
[[ "${OSTYPE:-}" == darwin* ]] && IS_MAC=true

have() { command -v "$1" >/dev/null 2>&1; }

print_install_suggestions_and_exit() {
  local -a pkgs=()
  local -a notes=()

  if $IS_MAC; then
    have chafa     || pkgs+=("chafa")
    have ffprobe   || pkgs+=("ffmpeg")
    have mediainfo || pkgs+=("mediainfo")
    (have pdftotext && have pdfinfo && have pdftoppm) || pkgs+=("poppler")
    have jq        || pkgs+=("jq")
    have bat       || pkgs+=("bat")
    have 7z        || pkgs+=("p7zip")
    have unzip     || pkgs+=("unzip")

    if ! have imgcat; then
      notes+=("imgcat not found: enable iTerm2 Shell Integration or put imgcat on PATH for best image/PDF-frame previews.")
    fi

    if ((${#pkgs[@]} == 0)); then
      echo "All recommended preview tools are already available."
      ((${#notes[@]} > 0)) && printf "%s\n" "${notes[@]}"
      exit 0
    fi

    if ! have brew; then
      echo "Missing tools detected, but Homebrew (brew) is not installed."
      echo "Install Homebrew, then run:"
      echo "  brew install ${pkgs[*]}"
      ((${#notes[@]} > 0)) && printf "%s\n" "${notes[@]}"
      exit 0
    fi

    echo "Recommended installs (macOS/Homebrew):"
    echo "  brew install ${pkgs[*]}"
    ((${#notes[@]} > 0)) && printf "%s\n" "${notes[@]}"
    exit 0

  else
    have chafa     || pkgs+=("chafa")
    have ffprobe   || pkgs+=("ffmpeg")
    have mediainfo || pkgs+=("mediainfo")
    (have pdftotext && have pdfinfo && have pdftoppm) || pkgs+=("poppler-utils")
    have jq        || pkgs+=("jq")
    (have bat || have batcat) || pkgs+=("bat")
    have 7z        || pkgs+=("p7zip-full")
    have unzip     || pkgs+=("unzip")
    have file      || pkgs+=("file")

    if have batcat && ! have bat; then
      notes+=("bat is installed as 'batcat'. Optional: sudo ln -s /usr/bin/batcat /usr/local/bin/bat")
    fi
    if ! have imgcat; then
      notes+=("imgcat not found: optional for iTerm2 image display. chafa covers images without imgcat.")
    fi

    if ((${#pkgs[@]} == 0)); then
      echo "All recommended preview tools are already available."
      ((${#notes[@]} > 0)) && printf "%s\n" "${notes[@]}"
      exit 0
    fi

    echo "Recommended installs (Pop!_OS / apt):"
    echo "  sudo apt update && sudo apt install ${pkgs[*]}"
    ((${#notes[@]} > 0)) && printf "%s\n" "${notes[@]}"
    exit 0
  fi
}

# MUST run first (and exit) if requested
if $INSTALL_TOOLS; then
  print_install_suggestions_and_exit
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
  printf "%-*s | %s\n" "$HALF" "$l" "$r"
}

indent_center() {
  local content_width="$1"
  local cols
  cols="$(tput cols 2>/dev/null || echo 120)"
  local pad=$(( (cols - content_width) / 2 ))
  (( pad < 0 )) && pad=0
  local spaces
  spaces="$(printf '%*s' "$pad" '')"
  sed "s/^/${spaces}/"
}

preview_vault_file_centered() {
  local path="$1"
  local mime="$2"

  [[ -e "$path" ]] || { echo "(preview skipped: vault file not found)"; return 0; }

  local cols lines w h
  cols="$(tput cols 2>/dev/null || echo 120)"
  lines="$(tput lines 2>/dev/null || echo 40)"

  # Preview width: middle third of terminal
  w=$(( cols / 3 ))
  (( w > 120 )) && w=120
  (( w < 20 )) && w=20

  # Preview height: about 1/3 of terminal rows (bounded)
  h=$(( lines / 3 ))
  (( h > 24 )) && h=24
  (( h < 8 )) && h=8

  case "$mime" in
    image/*)
      if have chafa; then
        chafa --size="${w}x${h}" -- "$path" | indent_center "$w"
        return 0
      fi
      if have viu; then
        viu -w "$w" -- "$path" | indent_center "$w"
        return 0
      fi
      if have imgcat; then
        imgcat -w "$w" -- "$path" | indent_center "$w"
        return 0
      fi
      echo "(preview skipped: install chafa or viu; imgcat is iTerm2-only)"
      ;;

    video/*)
      if have ffprobe; then
        ffprobe --hide_banner --loglevel error \
          --show_entries format=duration,size:stream=index,codec_type,codec_name,width,height,avg_frame_rate \
          --of default=nw=1 -- "$path" | head -n 25
        return 0
      fi
      if have mediainfo; then
        mediainfo -- "$path" | head -n 25
        return 0
      fi
      echo "(preview skipped: install ffprobe (ffmpeg) or mediainfo)"
      ;;

    audio/*)
      if have ffprobe; then
        ffprobe --hide_banner --loglevel error \
          --show_entries format=duration,size:stream=index,codec_type,codec_name,channels,sample_rate,bit_rate \
          --of default=nw=1 -- "$path" | head -n 25
        return 0
      fi
      if have mediainfo; then
        mediainfo -- "$path" | head -n 25
        return 0
      fi
      echo "(preview skipped: install ffprobe (ffmpeg) or mediainfo)"
      ;;

    application/pdf)
      if have pdftotext; then
        pdftotext -f 1 -l 1 -layout -- "$path" - 2>/dev/null | head -n 30
        return 0
      fi
      if have pdfinfo; then
        pdfinfo -- "$path" | head -n 30
        return 0
      fi
      echo "(preview skipped: install poppler utils (pdftotext/pdfinfo))"
      ;;

    text/*|application/json|application/xml)
      (head -n 30 -- "$path" 2>/dev/null || true)
      ;;

    application/zip)
      if have unzip; then
        unzip -l -- "$path" | head -n 30
        return 0
      fi
      echo "(preview skipped: install unzip)"
      ;;

    application/x-tar|application/gzip|application/x-gzip|application/x-7z-compressed|application/x-bzip2)
      if [[ "$mime" == application/x-tar* ]] && have tar; then
        tar -tf -- "$path" 2>/dev/null | head -n 30
        return 0
      fi
      if [[ "$mime" == application/x-7z-compressed ]] && have 7z; then
        7z l -- "$path" | head -n 40
        return 0
      fi
      echo "(preview skipped: install tar/7z tools)"
      ;;

    *)
      if have file; then
        file --brief --mime-type --mime-encoding -- "$path"
      else
        echo "(preview skipped: install file)"
      fi
      ;;
  esac
}

# -------------------------------
# FS / DB helpers
# -------------------------------
touch_mtime() {
  local file="$1"
  local ts="$2"  # "YYYY-MM-DD HH:MM:SS"

  if $IS_MAC; then
    local t
    t="$(date -j -f '%Y-%m-%d %H:%M:%S' "$ts" '+%Y%m%d%H%M.%S')" || return 1
    touch -t "$t" "$file"
  else
    touch --date="$ts" -- "$file"
  fi
}

trash_or_delete() {
  local file="$1"

  if $FORCE_DELETE; then
    rm --force -- "$file"
    return
  fi

  if $IS_MAC; then
    mkdir -p "$HOME/.Trash"
    mv --force -- "$file" "$HOME/.Trash/"
    return
  fi

  if have gio; then
    gio trash -- "$file"
    return
  fi

  rm --force -- "$file"
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
TMP="$(mktemp)"
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
while IFS=$'\t' read -r hash mime oldest_id oldest_full_path target_ts vault_id vault_full_path vault_ts drift_seconds; do
  row_num=$((row_num + 1))

  echo
  echo "$SEP"
  printf "Row %d  hash=%s  mime=%s  drift_seconds=%s\n" "$row_num" "$hash" "$mime" "$drift_seconds"
  echo

  # Centered vault preview (middle third of screen)
  preview_vault_file_centered "$vault_full_path" "$mime"
  echo

  print_lr "OLDEST (non-vault)" "VAULT (canonical)"
  print_lr "id: $oldest_id"     "id: $vault_id"
  print_lr "path: $oldest_full_path" "path: $vault_full_path"
  print_lr "last_modified: $target_ts" "last_modified: $vault_ts"

  echo
  if ! $COMMIT; then
    echo "NOTE: preview mode (no changes). Use --commit to apply."
    echo
  fi

  while true; do
    printf "Action: [1] vault inherits oldest  [2] remove oldest file+row  [s] skip  [q] quit : "
    read -r choice
    case "$choice" in
      1)
        if [[ ! -e "$vault_full_path" ]]; then
          echo "ERROR: vault file not found on filesystem: $vault_full_path"
          echo "Skipped."
          break
        fi

        if ! $COMMIT; then
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
        if ! $COMMIT; then
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
        exit 0
        ;;
      *)
        echo "Invalid choice."
        ;;
    esac
  done

done <"$TMP"

echo
echo "Finished."