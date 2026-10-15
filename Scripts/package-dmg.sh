#!/bin/bash
# Packages an already built app with an Applications shortcut. Signing and
# notarization are handled by the release workflow after image creation.
set -euo pipefail

if [[ $# != 2 || ! -d "$1/Contents/MacOS" ]]; then
  echo "Usage: $0 path/to/ArgusDesk.app output.dmg" >&2
  exit 1
fi

app_path="$1"
output_path="$2"
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/argusdesk-dmg.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT

# Copy only the app bundle, never project files or private monitoring config.
ditto "$app_path" "$staging_dir/ArgusDesk.app"
ln -s /Applications "$staging_dir/Applications"
mkdir -p "$(dirname "$output_path")"
hdiutil create -volname ArgusDesk -srcfolder "$staging_dir" \
  -format UDZO -fs HFS+ -ov "$output_path"
hdiutil verify "$output_path"
