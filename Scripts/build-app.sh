#!/bin/zsh
# Compatibility entry point; the root script owns bundling, icons, and signing.
set -eu
exec "$(dirname "$0")/../build_app.sh" "$@"
