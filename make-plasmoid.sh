#!/bin/bash
# Builds dist/thinkpad-fan-control-<version>.plasmoid for upload to the KDE Store.
#
# A .plasmoid is just a zip of the package *contents* — metadata.json must sit at
# the archive root, not inside a package/ directory, or Plasma refuses to install it.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION=$(grep -oP '"Version"\s*:\s*"\K[^"]+' "$HERE/package/metadata.json")
OUT="$HERE/dist/thinkpad-fan-control-${VERSION}.plasmoid"

command -v zip >/dev/null || { echo "zip is not installed" >&2; exit 1; }

mkdir -p "$HERE/dist"
rm -f "$OUT"

cd "$HERE/package"
zip -qr "$OUT" . -x '.*' -x '*/.*'

echo "$OUT"
unzip -l "$OUT" | tail -n +4 | head -n -2
