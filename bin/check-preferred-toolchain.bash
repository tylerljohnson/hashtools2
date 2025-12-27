#!/usr/bin/env bash
#
# check-preferred-toolchain.bash
#
# Purpose:
#   Checks for (and optionally installs) the preferred CLI preview toolchain used by
#   preview.bash and vault_timestamp_drift_fix.bash.
#
# Behavior:
#   - Default: prints missing packages + install commands (no changes).
#   - --install: performs installation (brew on macOS, nala/apt on Linux).
#   - --no-extras: only core tools (faster/smaller).
#

set -euo pipefail

INSTALL=false
INCLUDE_EXTRAS=true

usage() {
  cat <<'EOF'
Usage:
  check-preferred-toolchain.bash [options]

Options:
  --install        Actually install missing tools
  --no-extras      Do not include "extras" package set
  -h|--help        Help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install) INSTALL=true; shift;;
    --no-extras) INCLUDE_EXTRAS=false; shift;;
    -h|--help) usage; exit 0;;
    *) echo "ERROR: Unknown arg: $1" >&2; usage; exit 2;;
  esac
done

IS_MAC=false
[[ "${OSTYPE:-}" == darwin* ]] && IS_MAC=true

have() { command -v "$1" >/dev/null 2>&1; }
have_bat() { have bat || have batcat; }

add_unique() {
  local pkg="$1"; shift
  local -n arr="$1"
  local x
  for x in "${arr[@]:-}"; do
    [[ "$x" == "$pkg" ]] && return 0
  done
  arr+=("$pkg")
}

core_pkgs=()
extra_pkgs=()
notes=()

if $IS_MAC; then
  # ---------- Core ----------
  have chafa       || add_unique "chafa" core_pkgs
  have ffprobe     || add_unique "ffmpeg" core_pkgs
  have mediainfo   || add_unique "mediainfo" core_pkgs
  (have pdftotext && have pdfinfo && have pdftoppm) || add_unique "poppler" core_pkgs
  have jq          || add_unique "jq" core_pkgs
  have rg          || add_unique "ripgrep" core_pkgs
  have_bat         || add_unique "bat" core_pkgs
  have 7z          || add_unique "p7zip" core_pkgs
  have unzip       || add_unique "unzip" core_pkgs
  have exiftool    || add_unique "exiftool" core_pkgs
  have xmllint     || add_unique "libxml2" core_pkgs
  have sqlite3     || add_unique "sqlite" core_pkgs
  have strings     || add_unique "binutils" core_pkgs

  if ! have imgcat; then
    notes+=("imgcat not found: enable iTerm2 Shell Integration (best inline image/PDF-frame previews).")
  fi

  # ---------- Extras ----------
  if $INCLUDE_EXTRAS; then
    have cabextract  || add_unique "cabextract" extra_pkgs
    have msiextract  || add_unique "msitools" extra_pkgs
    have readpst     || add_unique "libpst" extra_pkgs
    have ripmime     || add_unique "ripmime" extra_pkgs
    have munpack     || add_unique "mpack" extra_pkgs
    have formail     || add_unique "procmail" extra_pkgs
    have catdoc      || add_unique "catdoc" extra_pkgs
    have antiword    || add_unique "antiword" extra_pkgs
    have unrtf       || add_unique "unrtf" extra_pkgs
  fi

  if ((${#core_pkgs[@]} == 0 && ${#extra_pkgs[@]} == 0)); then
    echo "All preferred tools are available."
    ((${#notes[@]} > 0)) && printf "%s\n" "${notes[@]}"
    exit 0
  fi

  if ! have brew; then
    echo "Homebrew (brew) not found."
    echo "Install Homebrew, then run:"
    ((${#core_pkgs[@]} > 0)) && echo "  brew install ${core_pkgs[*]}"
    ((${#extra_pkgs[@]} > 0)) && echo "  brew install ${extra_pkgs[*]}"
    ((${#notes[@]} > 0)) && printf "%s\n" "${notes[@]}"
    exit 1
  fi

  echo "Missing tools:"
  ((${#core_pkgs[@]} > 0)) && echo "  Core:   ${core_pkgs[*]}"
  ((${#extra_pkgs[@]} > 0)) && echo "  Extras: ${extra_pkgs[*]}"
  ((${#notes[@]} > 0)) && printf "%s\n" "${notes[@]}"

  if ! $INSTALL; then
    echo
    ((${#core_pkgs[@]} > 0)) && echo "Run: brew install ${core_pkgs[*]}"
    ((${#extra_pkgs[@]} > 0)) && echo "Run: brew install ${extra_pkgs[*]}"
    exit 0
  fi

  ((${#core_pkgs[@]} > 0)) && brew install "${core_pkgs[@]}"
  ((${#extra_pkgs[@]} > 0)) && brew install "${extra_pkgs[@]}"
  echo "Done."
  exit 0

else
  # prefer nala if present, else apt; if installing and nala missing, install nala first
  PM="apt"
  have nala && PM="nala"

  # ---------- Core ----------
  have chafa       || add_unique "chafa" core_pkgs
  have ffprobe     || add_unique "ffmpeg" core_pkgs
  have mediainfo   || add_unique "mediainfo" core_pkgs
  (have pdftotext && have pdfinfo && have pdftoppm) || add_unique "poppler-utils" core_pkgs
  have jq          || add_unique "jq" core_pkgs
  have rg          || add_unique "ripgrep" core_pkgs
  have_bat         || add_unique "bat" core_pkgs
  have 7z          || add_unique "p7zip-full" core_pkgs
  have unzip       || add_unique "unzip" core_pkgs
  have file        || add_unique "file" core_pkgs
  have tar         || add_unique "tar" core_pkgs
  have gzip        || add_unique "gzip" core_pkgs
  have bzip2       || add_unique "bzip2" core_pkgs
  have xz          || add_unique "xz-utils" core_pkgs
  have exiftool    || add_unique "libimage-exiftool-perl" core_pkgs
  have strings     || add_unique "binutils" core_pkgs
  have xxd         || add_unique "xxd" core_pkgs
  have sqlite3     || add_unique "sqlite3" core_pkgs
  have xmllint     || add_unique "libxml2-utils" core_pkgs

  if have batcat && ! have bat; then
    notes+=("bat is installed as 'batcat'. Optional: sudo ln -s /usr/bin/batcat /usr/local/bin/bat")
  fi
  if ! have imgcat; then
    notes+=("imgcat not found: optional for iTerm2 inline images. chafa covers images without imgcat.")
  fi

  # ---------- Extras ----------
  if $INCLUDE_EXTRAS; then
    have cabextract  || add_unique "cabextract" extra_pkgs
    have msiextract  || add_unique "msitools" extra_pkgs
    have readpst     || add_unique "pst-utils" extra_pkgs
    have ripmime     || add_unique "ripmime" extra_pkgs
    have munpack     || add_unique "mpack" extra_pkgs
    have formail     || add_unique "procmail" extra_pkgs
    have catdoc      || add_unique "catdoc" extra_pkgs
    have antiword    || add_unique "antiword" extra_pkgs
    have unrtf       || add_unique "unrtf" extra_pkgs
  fi

  if ((${#core_pkgs[@]} == 0 && ${#extra_pkgs[@]} == 0)); then
    echo "All preferred tools are available."
    ((${#notes[@]} > 0)) && printf "%s\n" "${notes[@]}"
    exit 0
  fi

  echo "Missing tools:"
  ((${#core_pkgs[@]} > 0)) && echo "  Core:   ${core_pkgs[*]}"
  ((${#extra_pkgs[@]} > 0)) && echo "  Extras: ${extra_pkgs[*]}"
  ((${#notes[@]} > 0)) && printf "%s\n" "${notes[@]}"

  if ! $INSTALL; then
    echo
    if [[ "$PM" == "nala" ]]; then
      ((${#core_pkgs[@]} > 0)) && echo "Run: sudo nala update && sudo nala install ${core_pkgs[*]}"
      ((${#extra_pkgs[@]} > 0)) && echo "Run: sudo nala update && sudo nala install ${extra_pkgs[*]}"
    else
      echo "NOTE: nala not found; install it (optional): sudo apt update && sudo apt install nala"
      ((${#core_pkgs[@]} > 0)) && echo "Run: sudo apt update && sudo apt install ${core_pkgs[*]}"
      ((${#extra_pkgs[@]} > 0)) && echo "Run: sudo apt update && sudo apt install ${extra_pkgs[*]}"
    fi
    exit 0
  fi

  # install mode
  if ! have nala; then
    sudo apt update
    sudo apt install -y nala
    PM="nala"
  fi

  sudo nala update
  ((${#core_pkgs[@]} > 0)) && sudo nala install -y "${core_pkgs[@]}"
  ((${#extra_pkgs[@]} > 0)) && sudo nala install -y "${extra_pkgs[@]}"
  echo "Done."
  exit 0
fi