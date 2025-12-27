#!/usr/bin/env bash
#
# preview.bash
#
# Purpose:
#   Renders a CLI preview of a file using preferred tools.
#   MIME type is optional; if not supplied, the script will try to detect it.
#
# Usage:
#   preview.bash [options] <path>
#   preview.bash [options] -- <path>        # if path begins with '-'
#
# Strictness:
#   - Exactly ONE positional <path> is required.
#   - Unknown options are errors.
#   - Invalid option values are errors (e.g., non-integer widths, invalid mime strings).
#

set -euo pipefail

MIME=""
CENTER=false
WIDTH_THIRD=false
MAX_WIDTH=120
MAX_HEIGHT=24
TEXT_LINES=60

usage() {
  cat <<'EOF'
Usage:
  preview.bash [options] <path>

Positional:
  <path>            file to preview (required; exactly one)

Options:
  --mime MIME       preferred; if omitted, MIME is detected when possible
  --center          center output where possible (best effort)
  --width-third     use terminal-width/3 as target width (clamped to --max-width)
  --max-width N     integer >= 20 (default 120)
  --max-height N    integer >= 4  (default 24; used by image previewers)
  --text-lines N    integer >= 1  (default 60; for text-ish previews)
  --               end options (useful if path begins with '-')
  -h|--help         help
EOF
}

have() { command -v "$1" >/dev/null 2>&1; }
have_bat() { have bat || have batcat; }

die() { echo "ERROR: $*" >&2; usage; exit 2; }

require_value() {
  local opt="$1"
  [[ $# -ge 2 ]] || die "$opt requires a value"
  local val="$2"
  [[ -n "$val" ]] || die "$opt requires a non-empty value"
  [[ "$val" != -* ]] || die "$opt value looks like an option: '$val'"
}

require_int_ge() {
  local opt="$1" val="$2" min="$3"
  [[ "$val" =~ ^[0-9]+$ ]] || die "$opt value must be an integer >= $min; got '$val'"
  (( val >= min )) || die "$opt value must be >= $min; got '$val'"
}

normalize_and_validate_mime() {
  local m="$1"
  m="${m,,}" # lowercase
  # Basic MIME validation: type/subtype with common token chars
  if [[ ! "$m" =~ ^[a-z0-9][a-z0-9!#\$&\^_.+-]*/[a-z0-9][a-z0-9!#\$&\^_.+-]*$ ]]; then
    die "--mime value is not a valid mime-type string: '$1'"
  fi
  printf "%s" "$m"
}

# -------------------------------
# Arg parsing (strict)
# -------------------------------
positional=()
end_opts=false

while [[ $# -gt 0 ]]; do
  if ! $end_opts; then
    case "$1" in
      --mime)
        require_value "--mime" "${2-}"
        MIME="$(normalize_and_validate_mime "$2")"
        shift 2
        continue
        ;;
      --center)
        CENTER=true
        shift
        continue
        ;;
      --width-third)
        WIDTH_THIRD=true
        shift
        continue
        ;;
      --max-width)
        require_value "--max-width" "${2-}"
        require_int_ge "--max-width" "$2" 20
        MAX_WIDTH="$2"
        shift 2
        continue
        ;;
      --max-height)
        require_value "--max-height" "${2-}"
        require_int_ge "--max-height" "$2" 4
        MAX_HEIGHT="$2"
        shift 2
        continue
        ;;
      --text-lines)
        require_value "--text-lines" "${2-}"
        require_int_ge "--text-lines" "$2" 1
        TEXT_LINES="$2"
        shift 2
        continue
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --)
        end_opts=true
        shift
        continue
        ;;
      -*)
        die "Unknown option: $1"
        ;;
      *)
        positional+=("$1")
        shift
        continue
        ;;
    esac
  else
    positional+=("$1")
    shift
  fi
done

[[ ${#positional[@]} -eq 1 ]] || die "Exactly one <path> positional arg is required; got ${#positional[@]}"
PATH_ARG="${positional[0]}"

# -------------------------------
# Layout helpers
# -------------------------------
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

# -------------------------------
# Validate path
# -------------------------------
if [[ ! -e "$PATH_ARG" ]]; then
  echo "(preview skipped: file not found: $PATH_ARG)"
  exit 0
fi

# -------------------------------
# Width/height selection
# -------------------------------
cols="$(tput cols 2>/dev/null || echo 120)"
w="$MAX_WIDTH"
h="$MAX_HEIGHT"

if $WIDTH_THIRD; then
  w=$(( cols / 3 ))
  (( w > MAX_WIDTH )) && w="$MAX_WIDTH"
  (( w < 20 )) && w=20
fi

center_pipe() {
  if $CENTER; then
    indent_center "$w"
  else
    cat
  fi
}

# -------------------------------
# MIME detection (if needed)
# -------------------------------
detect_mime() {
  local file="$1"

  if have file; then
    local mt
    mt="$(file --brief --mime-type -- "$file" 2>/dev/null || true)"
    if [[ -n "$mt" ]]; then
      printf "%s" "${mt,,}"
      return 0
    fi
  fi

  case "${file##*.}" in
    jpg|jpeg) echo "image/jpeg" ;;
    png) echo "image/png" ;;
    gif) echo "image/gif" ;;
    webp) echo "image/webp" ;;
    heic) echo "image/heic" ;;
    tif|tiff) echo "image/tiff" ;;
    bmp) echo "image/bmp" ;;
    svg) echo "image/svg+xml" ;;
    pdf) echo "application/pdf" ;;
    mp4|m4v) echo "video/mp4" ;;
    mov) echo "video/quicktime" ;;
    mkv) echo "video/x-matroska" ;;
    avi) echo "video/x-msvideo" ;;
    mp3) echo "audio/mpeg" ;;
    wav) echo "audio/vnd.wave" ;;
    json) echo "application/json" ;;
    xml) echo "application/xml" ;;
    html|htm) echo "text/html" ;;
    txt|log) echo "text/plain" ;;
    *) echo "application/octet-stream" ;;
  esac
}

if [[ -z "$MIME" ]]; then
  MIME="$(detect_mime "$PATH_ARG")"
  # detected MIME is best-effort; keep it even if it's octet-stream
fi

# -------------------------------
# Text helper
# -------------------------------
print_text_head() {
  local file="$1"
  local n="$2"
  if have_bat; then
    if have bat; then
      bat --style=plain --paging=never --line-range=1:"$n" -- "$file" 2>/dev/null || head -n "$n" -- "$file" || true
    else
      batcat --style=plain --paging=never --line-range=1:"$n" -- "$file" 2>/dev/null || head -n "$n" -- "$file" || true
    fi
  else
    head -n "$n" -- "$file" 2>/dev/null || true
  fi
}

# -------------------------------
# Preview dispatch
# -------------------------------
case "$MIME" in
  image/*)
    if have imgcat; then
      imgcat -w "$w" -- "$PATH_ARG" | center_pipe
      exit 0
    fi
    if have chafa; then
      chafa --size="${w}x${h}" -- "$PATH_ARG" | center_pipe
      exit 0
    fi
    if have viu; then
      viu -w "$w" -- "$PATH_ARG" | center_pipe
      exit 0
    fi
    echo "(preview skipped: install imgcat (iTerm2), chafa, or viu)"
    ;;

  video/*)
    if have ffprobe; then
      ffprobe --hide_banner --loglevel error \
        --show_entries format=duration,size:stream=index,codec_type,codec_name,width,height,avg_frame_rate \
        --of default=nw=1 -- "$PATH_ARG" | head -n 25
      exit 0
    fi
    if have mediainfo; then
      mediainfo -- "$PATH_ARG" | head -n 25
      exit 0
    fi
    echo "(preview skipped: install ffprobe (ffmpeg) or mediainfo)"
    ;;

  audio/*)
    if have ffprobe; then
      ffprobe --hide_banner --loglevel error \
        --show_entries format=duration,size:stream=index,codec_type,codec_name,channels,sample_rate,bit_rate \
        --of default=nw=1 -- "$PATH_ARG" | head -n 25
      exit 0
    fi
    if have mediainfo; then
      mediainfo -- "$PATH_ARG" | head -n 25
      exit 0
    fi
    echo "(preview skipped: install ffprobe (ffmpeg) or mediainfo)"
    ;;

  application/pdf)
    if have pdfinfo; then
      pdfinfo -- "$PATH_ARG" | head -n 20
    fi
    if have pdftotext; then
      pdftotext -f 1 -l 1 -layout -- "$PATH_ARG" - 2>/dev/null | head -n 20
      exit 0
    fi
    echo "(preview skipped: install poppler utils)"
    ;;

  application/json)
    if have jq; then
      (head -c 200000 -- "$PATH_ARG" 2>/dev/null || true) | jq . 2>/dev/null | head -n 40
    else
      print_text_head "$PATH_ARG" "$TEXT_LINES"
    fi
    ;;

  application/xml|application/xhtml+xml|application/xml-dtd|application/rss+xml|application/atom+xml|application/wsdl+xml|application/xslt+xml|application/rdf+xml|image/svg+xml|application/dita+xml|application/smil+xml)
    if have xmllint; then
      xmllint --format --recover --nocdata --nowarning -- "$PATH_ARG" 2>/dev/null | head -n 40
    else
      print_text_head "$PATH_ARG" "$TEXT_LINES"
    fi
    ;;

  text/*|text/javascript)
    print_text_head "$PATH_ARG" "$TEXT_LINES"
    ;;

  application/zip|application/java-archive|application/vnd.android.package-archive|application/epub+zip)
    if have unzip; then
      unzip -l -- "$PATH_ARG" | head -n 40
      exit 0
    fi
    if have 7z; then
      7z l -- "$PATH_ARG" | head -n 60
      exit 0
    fi
    echo "(preview skipped: install unzip or p7zip)"
    ;;

  application/x-7z-compressed|application/x-rar-compressed|application/x-tar|application/gzip|application/x-bzip2|application/x-xz|application/x-lzip|application/x-compress|application/x-cpio|application/x-gtar|application/x-archive|application/zlib)
    if have 7z; then
      7z l -- "$PATH_ARG" | head -n 60
      exit 0
    fi
    if [[ "$MIME" == application/x-tar* ]] && have tar; then
      tar -tf -- "$PATH_ARG" 2>/dev/null | head -n 40
      exit 0
    fi
    echo "(preview skipped: install p7zip)"
    ;;

  application/vnd.ms-outlook-pst)
    if have readpst; then
      readpst -D -o /dev/null -- "$PATH_ARG" 2>/dev/null | head -n 40 || true
      exit 0
    fi
    echo "(preview skipped: install pst-utils (Linux) / libpst (macOS brew))"
    ;;

  message/rfc822|multipart/*|application/mbox)
    if have ripmime; then
      ripmime -i "$PATH_ARG" -d /tmp 2>/dev/null | head -n 40 || true
      exit 0
    fi
    print_text_head "$PATH_ARG" "$TEXT_LINES"
    ;;

  application/octet-stream|application/x-msdownload|application/x-dosexec|application/x-executable|application/x-mach-o-executable|application/java-vm|application/java-serialized-object)
    if have file; then
      file --brief --mime-type --mime-encoding -- "$PATH_ARG"
    fi
    if have strings; then
      strings -n 8 -- "$PATH_ARG" 2>/dev/null | head -n 30 || true
    fi
    ;;

  *)
    if have file; then
      file --brief --mime-type --mime-encoding -- "$PATH_ARG"
    fi
    print_text_head "$PATH_ARG" "$TEXT_LINES"
    ;;
esac

exit 0