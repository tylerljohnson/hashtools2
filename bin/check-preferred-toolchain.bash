#!/usr/bin/env bash
# Wrapper for backward compatibility after renaming the tooling script.
# This script used to be named `check-preferred-toolchain.bash`. It now delegates
# to `preview-tooling.bash` in the same directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/preview-tooling.bash"

if [[ -x "$TARGET" ]]; then
  exec "$TARGET" "$@"
fi

if [[ -f "$TARGET" ]]; then
  exec bash "$TARGET" "$@"
fi

echo "ERROR: renamed tooling script not found: $TARGET" >&2
exit 1
