#!/usr/bin/env bash
#
# preview.bash
#
# Purpose:
#   Given a MIME type and a file path, renders a CLI preview using preferred tools.
#   Designed to be called by vault_timestamp_drift_fix.bash, but usable standalone.
#
# Examples:
#   preview.bash --mime image/jpeg --path /some/file.jpg --center --width-third
#   preview.bash --mime application/pdf --path doc.pdf
#

set -euo pipefail

MIME=""
PATH_ARG=""
CENTER=false
WIDTH_THIRD=false
MAX_WIDTH=120
MAX_HEIGHT=24
TEXT_LINES=60

usage() {
  cat <<'EOF'
Usage:
  preview.bash --mime <mime-type> --path <file> [options]

Required:
  --mime MIME
  --path PATH

Options:
  --center          Center output where possible (best effort)
  --width-third     Use terminal-width/3 as target width (clamped to --max-width)
  --max-width N     Default 120
  --max-height N    Default 24 (used by image previewers)
  --text-lines N    Default 60 (for text-ish previews)
  -h|--help         Help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mime) MIME="$2"; shift 2;;
    --path) PATH_ARG="$2"; shift 2;;
    --center) CENTER=true; shift;;
    --width-third) WIDTH_THIRD=true; shift;;
    --max-width) MAX_WIDTH="$2"; shift 2;;
    --max-height) MAX_HEIGHT="$2"; shift 2;;
    --text-lines) TEXT_LINES="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "ERROR: Unknown arg: $1" >&2; usage; exit 2;;
  esac
done

if [[ -z "$MIME" || -z "$PATH_ARG" ]]; then
  echo "ERROR: --mime and --path are required" >&2
  usage
  exit 2
fi

have() { command -v "$1" >/dev/null 2>&1; }
have_bat() { have bat || have batcat; }

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

if [[ ! -e "$PATH_ARG" ]]; then
  echo "(preview skipped: file not found: $PATH_ARG)"
  exit 0
fi

# --- Helpers for text output ---
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
    else
      echo "(preview skipped: install file)"
    fi
    ;;
esac

exit 0