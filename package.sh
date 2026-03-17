#!/usr/bin/env bash
# SafeBrowse release bundler
# Usage: ./package.sh <xcode-export-folder>
# Example: ./package.sh '/Users/vadim/workspace/SafeBrowse/Build/Products/SafeBrowse 2026-03-17 17-15-42'

set -euo pipefail

EXPORT_DIR="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ -z "$EXPORT_DIR" ]]; then
    echo "Usage: $0 <xcode-export-folder>" >&2
    echo "  The folder is what Xcode creates when you do Product → Export (Built Products)." >&2
    exit 1
fi

APP_SRC="${EXPORT_DIR}/Products/Applications/SafeBrowse.app"
if [[ ! -d "$APP_SRC" ]]; then
    echo "Error: SafeBrowse.app not found at ${APP_SRC}" >&2
    echo "Make sure you passed the correct Xcode export folder." >&2
    exit 1
fi

# Derive version from CFBundleShortVersionString in the app bundle
VERSION=$(defaults read "${APP_SRC}/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "")
BUILD=$(defaults read "${APP_SRC}/Contents/Info" CFBundleVersion 2>/dev/null || echo "")
if [[ -z "$VERSION" ]]; then
    VERSION="1.0"
fi
RELEASE_NAME="SafeBrowse-${VERSION}"
ZIP_NAME="${RELEASE_NAME}.zip"

echo "Version : ${VERSION} (build ${BUILD:-?})"
echo "App     : ${APP_SRC}"
echo "Output  : ${SCRIPT_DIR}/${ZIP_NAME}"
echo ""

# ── Build staging folder ───────────────────────────────────────────────────
STAGE="${SCRIPT_DIR}/${RELEASE_NAME}"
rm -rf "$STAGE"
mkdir "$STAGE"

# Copy app (preserves resource forks, symlinks, etc.)
echo "Copying SafeBrowse.app…"
ditto "$APP_SRC" "${STAGE}/SafeBrowse.app"

# Strip quarantine so users don't get Gatekeeper warnings on first launch
echo "Stripping quarantine attributes…"
xattr -cr "${STAGE}/SafeBrowse.app"

# Copy installer scripts from the app bundle (guaranteed to match this build)
for f in install.sh uninstall.sh; do
    BUNDLED="${APP_SRC}/Contents/Resources/${f}"
    if [[ -f "$BUNDLED" ]]; then
        cp "$BUNDLED" "${STAGE}/${f}"
        chmod +x "${STAGE}/${f}"
    elif [[ -f "${SCRIPT_DIR}/${f}" ]]; then
        echo "Warning: ${f} not in app bundle, falling back to repo root" >&2
        cp "${SCRIPT_DIR}/${f}" "${STAGE}/${f}"
        chmod +x "${STAGE}/${f}"
    else
        echo "Warning: ${f} not found — skipping" >&2
    fi
done

# ── Zip ───────────────────────────────────────────────────────────────────
cd "$SCRIPT_DIR"
rm -f "$ZIP_NAME"
echo "Creating ${ZIP_NAME}…"
ditto -c -k --sequesterRsrc --keepParent "$RELEASE_NAME" "$ZIP_NAME"
rm -rf "$STAGE"

SIZE=$(du -sh "$ZIP_NAME" | cut -f1)
echo ""
echo "✓ ${ZIP_NAME}  (${SIZE})"
echo ""
echo "Release contents:"
echo "  SafeBrowse.app   — drag to /Applications"
echo "  install.sh       — sudo ./install.sh /Applications/SafeBrowse.app"
echo "  uninstall.sh     — sudo ./uninstall.sh"
echo ""
echo "Recipients must run: sudo xattr -cr /Applications/SafeBrowse.app"
echo "before the first launch if macOS blocks it."
