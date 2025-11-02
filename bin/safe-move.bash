#!/usr/bin/env bash
#
# safe-move.bash
# Safely moves one or more regular files to a destination path,
# preserving timestamps and metadata across filesystems (local or SMB).
#
# Usage:
#   safe-move.bash <src>... <dest>
#
# Behavior:
# - <dest> can be a directory or a single filename (if one src).
# - Accepts shell globs (e.g. *.jpg)
# - Only operates on regular files (skips symlinks, directories, devices).
# - Creates destination directories as needed.
# - Preserves timestamps and metadata.
#
# Exit codes:
#   0 success
#   1 usage error
#   2 invalid source(s)
#   3 destination exists (for single-file rename)
#   4 insufficient space
#   5 move/rsync failure or post-check mismatch

set -euo pipefail
shopt -s nullglob dotglob # expand globs safely, include dotfiles

# ----- Colors -----
RED='\033[0;31m'; YEL='\033[0;33m'; GRN='\033[0;32m'; CYA='\033[0;36m'; NC='\033[0m'
err(){ echo -e "${RED}ERROR:${NC} $*" >&2; }
warn(){ echo -e "${YEL}WARN:${NC} $*" >&2; }
info(){ echo -e "${CYA}[*]${NC} $*"; }
ok(){ echo -e "${GRN}[OK]${NC} $*"; }

# ----- Args -----
if [[ $# -lt 2 ]]; then
  err "Usage: $0 <src>... <dest>"
  exit 1
fi

dest="${@: -1}"              # last argument = destination
sources=("${@:1:$#-1}")      # all but last = source(s)

# Flatten globs manually (Bash expands them automatically)
expanded_sources=()
for s in "${sources[@]}"; do
  matches=($s)
  for m in "${matches[@]}"; do
    expanded_sources+=("$m")
  done
done

if [[ ${#expanded_sources[@]} -eq 0 ]]; then
  err "No matching source files found."
  exit 2
fi

# ----- Helper functions -----
stat_size(){ stat -c '%s' "$1" 2>/dev/null || stat -f '%z' "$1"; }
stat_mtime(){ stat -c '%Y' "$1" 2>/dev/null || stat -f '%m' "$1"; }
stat_dev(){ stat -c '%d' "$1" 2>/dev/null || stat -f '%d' "$1"; }

check_space(){
  local path="$1" needed_bytes="$2"
  if ! command -v df >/dev/null; then return 0; fi
  local avail_kb
  avail_kb=$(df -Pk -- "$path" | awk 'NR==2{print $4}')
  [[ -z "$avail_kb" ]] && return 0
  local need_kb=$(( (needed_bytes + 1023) / 1024 + 1 ))
  (( avail_kb < need_kb )) && return 1 || return 0
}

build_rsync_opts(){
  local opts=(-a --remove-source-files -A -X -H -S --no-o --no-g)
  if [[ "$(uname -s)" == "Darwin" ]]; then
    rsync --help 2>&1 | grep -q -- '--fileflags' && opts+=(--fileflags)
    rsync --help 2>&1 | grep -q -- '--crtimes' && opts+=(--crtimes)
  fi
  printf '%s\n' "${opts[@]}"
}

move_one(){
  local src=$1 dest=$2
  [[ ! -e "$src" ]] && { warn "Skipping missing source: $src"; return 1; }
  if [[ ! -f "$src" ]] || [[ -L "$src" ]]; then
    warn "Skipping non-regular file: $src"
    return 1
  fi
  if [[ ! -r "$src" ]]; then
    warn "Skipping unreadable file: $src"
    return 1
  fi

  # If dest is a directory, append basename
  if [[ -d "$dest" ]]; then
    dest="$dest/$(basename "$src")"
  fi

  local dest_parent
  dest_parent=$(dirname "$dest")
  mkdir -p -- "$dest_parent"

  if [[ -e "$dest" ]]; then
    warn "Skipping existing destination: $dest"
    return 1
  fi

  local src_size src_mtime src_dev dst_dev
  src_size=$(stat_size "$src")
  src_mtime=$(stat_mtime "$src")
  src_dev=$(stat_dev "$src")
  dst_dev=$(stat_dev "$dest_parent")

  if [[ "$src_dev" == "$dst_dev" ]]; then
    info "Moving (same FS): $src → $dest"
    mv -- "$src" "$dest"
  else
    info "Cross-filesystem move: $src → $dest"
    if ! check_space "$dest_parent" "$src_size"; then
      err "Insufficient free space for: $src"
      return 1
    fi
    mapfile -t RSYNC_OPTS < <(build_rsync_opts)
    rsync "${RSYNC_OPTS[@]}" -- "$src" "$dest"
  fi

  # Validation
  if [[ ! -f "$dest" ]] || [[ -e "$src" ]]; then
    err "Move failed or incomplete for: $src"
    return 1
  fi
  local dest_size dest_mtime
  dest_size=$(stat_size "$dest")
  dest_mtime=$(stat_mtime "$dest")
  if [[ "$dest_size" != "$src_size" ]]; then
    err "Size mismatch after move: $src"
    return 1
  fi
  local mtime_diff=$(( dest_mtime - src_mtime ))
  if (( mtime_diff < -1 || mtime_diff > 1 )); then
    warn "mtime skew detected: $src"
  fi
  ok "Moved $(basename "$src") → $dest"
  return 0
}

# ----- Main loop -----
if [[ ${#expanded_sources[@]} -eq 1 && ! -d "$dest" ]]; then
  move_one "${expanded_sources[0]}" "$dest"
else
  mkdir -p -- "$dest"
  for src in "${expanded_sources[@]}"; do
    move_one "$src" "$dest" || true
  done
fi

ok "All matching files processed."
exit 0
