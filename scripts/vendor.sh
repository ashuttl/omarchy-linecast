#!/bin/bash
# Refresh the bundled linecast from a tagged release of the linecast repo.
# Usage: scripts/vendor.sh v2.12.0 [path-to-linecast-checkout]
set -euo pipefail
tag="${1:?tag, e.g. v2.12.0}"
src="${2:-$HOME/Developer/linecast}"
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
rm -rf "$here/vendor/linecast"
git -C "$src" archive "$tag" src/linecast | tar -x -C "$here/vendor" --strip-components=1
find "$here/vendor/linecast" -type f -exec chmod 644 {} +
find "$here/vendor/linecast" -name __pycache__ -type d -prune -exec rm -rf {} +
printf '%s\n' "$tag" >"$here/vendor/VERSION"
# linecast reads its version from package metadata, for --version and the
# User-Agent it sends; without it the bundled copy calls itself "dev".
rm -rf "$here"/vendor/linecast-*.dist-info
mkdir "$here/vendor/linecast-${tag#v}.dist-info"
printf 'Metadata-Version: 2.1\nName: linecast\nVersion: %s\n' "${tag#v}" \
  >"$here/vendor/linecast-${tag#v}.dist-info/METADATA"
echo "vendored linecast $tag into vendor/linecast"
