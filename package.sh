#!/usr/bin/env bash
# Creates a distributable zip of the built SafeBrowse app.
# Usage: ./package.sh [Debug|Release]  (default: Debug)

set -euo pipefail

CONFIG="${1:-Debug}"
APP="Build/Products/${CONFIG}/SafeBrowse.app"
OUT="SafeBrowse-${CONFIG}.zip"

if [[ ! -d "$APP" ]]; then
    echo "Error: ${APP} not found. Build the project in Xcode first." >&2
    exit 1
fi

echo "Packaging ${APP}…"
rm -f "$OUT"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT"
echo "Created: $(pwd)/${OUT}  ($(du -sh "$OUT" | cut -f1))"
echo ""
echo "To install on another Mac:"
echo "  1. Copy SafeBrowse-${CONFIG}.zip to the target Mac"
echo "  2. Double-click to unzip → SafeBrowse.app"
echo "  3. Open SafeBrowse.app and click \"Install Helper…\""
