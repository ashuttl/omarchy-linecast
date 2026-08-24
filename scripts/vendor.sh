#!/bin/bash
# Refresh the bundled linecast from a tagged release of the linecast repo.
# Usage: scripts/vendor.sh v1.15.1 [path-to-linecast-checkout]
set -euo pipefail
tag="${1:?tag, e.g. v1.15.1}"
src="${2:-$HOME/Developer/linecast}"
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
rm -rf "$here/vendor/linecast"
git -C "$src" archive "$tag" src/linecast | tar -x -C "$here/vendor" --strip-components=1
find "$here/vendor/linecast" -type f -exec chmod 644 {} +
find "$here/vendor/linecast" -name __pycache__ -type d -prune -exec rm -rf {} +
printf '%s\n' "$tag" >"$here/vendor/VERSION"
echo "vendored linecast $tag into vendor/linecast"
