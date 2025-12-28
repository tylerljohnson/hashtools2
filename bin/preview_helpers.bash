#!/usr/bin/env bash
# preview_helpers.bash
# Sourced by preview.bash. Provides helper functions to preview images, videos,
# archives, and a few document/database types in a portable way (macOS + Linux).

# NOTE: This file expects the following symbols/functions to be available from
# the caller (preview.bash): have(), center_pipe (optional), w, h, TEXT_LINES,
# BAT_CMD. It must be sourced, not executed.

# Detect a usable timeout command (coreutils timeout or gtimeout on macOS)
TIMEOUT_CMD=""
if have timeout; then TIMEOUT_CMD=timeout
elif have gtimeout; then TIMEOUT_CMD=gtimeout
fi

# Display an image using the best available terminal backend.
# Usage: display_image <path> [width]
display_image() {
  local img="$1"
  local width="${2-}"
  [[ -n "$width" ]] || width="$w"

  # iTerm2 imgcat (writes control codes to terminal)
  if have imgcat; then
    imgcat --preserve-aspect-ratio --width "$width" "$img" 2>/dev/null || true
    return
  fi

  # kitty icat (kitty must be present)
  if have kitty && kitty +kitten icat --help >/dev/null 2>&1; then
    # use transfer-mode file for large images
    kitty +kitten icat --transfer-mode file --silent --align=center --place "${width}x0@0x0" "$img" 2>/dev/null || true
    return
  fi

  # chafa - good terminal fallback
  if have chafa; then
    chafa --size="${width}x${h}" -- "$img" 2>/dev/null || true
    return
  fi

  # viu - another good fallback
  if have viu; then
    viu -w "$width" -- "$img" 2>/dev/null || true
    return
  fi

  # final fallback: use ImageMagick's identify to show basic info
  if have identify; then
    identify -format "%%m %%wx%%h %%b\n" "$img" 2>/dev/null | head -n 20 || true
    return
  fi

  echo "(no image preview backend available)"
}

# Generate and display a video thumbnail using ffmpeg (fast) or fall back to
# metadata output from ffprobe/mediainfo.
# Usage: preview_video_thumbnail <path> [width]
preview_video_thumbnail() {
  local file="$1"
  local width="${2-}"
  [[ -n "$width" ]] || width="$w"

  local tmp
  # mktemp differences: try portable form
  tmp="$(mktemp 2>/dev/null || mktemp -t preview_thumb)" || return 1
  tmp="$tmp.png"

  if have ffmpeg; then
    # Prefer a short seek (1s) to avoid black frames at 0s; scale to width
    if [ -n "$TIMEOUT_CMD" ]; then
      $TIMEOUT_CMD 8s ffmpeg -y -hide_banner -loglevel error -ss 00:00:01 -i "$file" -frames:v 1 -vf "scale='min($width,iw)':-1" "$tmp" 2>/dev/null && display_image "$tmp" "$width" && rm -f "$tmp" && return 0
    else
      ffmpeg -y -hide_banner -loglevel error -ss 00:00:01 -i "$file" -frames:v 1 -vf "scale='min($width,iw)':-1" "$tmp" 2>/dev/null && display_image "$tmp" "$width" && rm -f "$tmp" && return 0
    fi
  fi

  # fallback to metadata
  if have ffprobe; then
    ffprobe -hide_banner -show_format -show_streams "$file" 2>/dev/null | head -n 60 || true
    return 0
  fi
  if have mediainfo; then
    mediainfo -- "$file" 2>/dev/null | head -n 60 || true
    return 0
  fi

  echo "(no video preview backend available)"
  return 1
}

# Robustly list archive contents. Returns first N lines (default 60).
# Usage: list_archive_contents <path> [n]
list_archive_contents() {
  local file="$1"
  local n="${2-60}"

  # bsdtar (libarchive) is excellent for many formats
  if have bsdtar; then
    bsdtar -tf "$file" 2>/dev/null | head -n "$n" && return 0
  fi

  if have 7z; then
    7z l -- "$file" 2>/dev/null | head -n "$n" && return 0
  fi

  # zip
  if have unzip && file --brief --mime-type -- "$file" 2>/dev/null | grep -qi zip; then
    unzip -l -- "$file" 2>/dev/null | head -n "$n" && return 0
  fi

  # .deb
  if [[ "$file" == *.deb ]] && have dpkg-deb; then
    dpkg-deb -c "$file" 2>/dev/null | head -n "$n" && return 0
  fi

  # tar-like formats
  if have tar && file --brief --mime-type -- "$file" 2>/dev/null | grep -Ei 'tar|x-tar|x-xz|gzip|x-bzip2|x-xz' >/dev/null 2>&1; then
    tar -tf -- "$file" 2>/dev/null | head -n "$n" && return 0
  fi

  # dmg on macOS
  if [[ "$(uname -s)" == "Darwin" ]] && have hdiutil; then
    hdiutil imageinfo -puppetstrings "$file" 2>/dev/null | head -n "$n" || true
    return 0
  fi

  echo "(archive listing unavailable; install bsdtar or p7zip/unzip)"
  return 1
}

# Preview sqlite DB: show tables and sample rows from first table
preview_sqlite() {
  local file="$1"
  if ! have sqlite3; then
    echo "(sqlite3 not installed)"
    return 1
  fi
  echo "sqlite: tables:"
  sqlite3 "$file" ".tables" 2>/dev/null || true
  local tbl
  tbl="$(sqlite3 "$file" ".tables" 2>/dev/null | awk '{print $1}' | head -n1)"
  if [[ -n "$tbl" ]]; then
    echo
    echo "sample rows from $tbl:"
    sqlite3 "$file" "select * from \"$tbl\" limit 10;" 2>/dev/null | sed -n '1,40p' || true
  fi
}

# Preview Office Open XML documents (docx/pptx/xlsx) by extracting core props
preview_office_doc() {
  local file="$1"
  if have unzip; then
    unzip -p -- "$file" docProps/core.xml 2>/dev/null | sed -n '1,120p' || true
    return 0
  fi
  echo "(unzip not available to inspect office document)"
  return 1
}

# QuickLook thumbnail helper (macOS) - generates a PNG in same directory as tmp
quicklook_thumbnail_and_display() {
  local file="$1"
  local width="${2-}"
  [[ -n "$width" ]] || width="$w"
  if [[ "$(uname -s)" != "Darwin" ]] || ! have qlmanage; then
    return 1
  fi

  local outdir tmpname png
  outdir="$(mktemp -d 2>/dev/null || mktemp -d -t qlthumb)"
  # qlmanage -t will create <basename>.png in outdir
  qlmanage -t -s 512 -o "$outdir" -- "$file" >/dev/null 2>&1 || true
  tmpname="$(basename "$file").png"
  png="$outdir/$tmpname"
  if [[ -f "$png" ]]; then
    display_image "$png" "$width"
    rm -rf "$outdir"
    return 0
  fi
  rm -rf "$outdir"
  return 1
}

# End of helpers

