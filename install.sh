#!/usr/bin/env bash
# SafeBrowse installer — must be run as root (sudo ./install.sh /path/to/SafeBrowse.app)
# Usage: sudo install.sh <path-to-SafeBrowse.app>

set -euo pipefail

APP_PATH="${1:-}"
HELPER_BINARY="/usr/local/bin/safebrowse-helper"
PLIST_PATH="/Library/LaunchDaemons/com.safebrowse.helper.plist"
AGENT_PLIST="/Library/LaunchAgents/com.safebrowse.app.plist"
LOG_PATH="/var/log/safebrowse-helper.log"

# Resolve to absolute path — LaunchAgent requires it or launchd silently fails to restart
APP_PATH="$(cd "$(dirname "$APP_PATH")" && pwd)/$(basename "$APP_PATH")"
APP_BINARY="${APP_PATH}/Contents/MacOS/SafeBrowse"

# ── Checks ─────────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "Error: install.sh must be run as root (sudo ./install.sh ...)." >&2
    exit 1
fi

if [[ -z "$APP_PATH" ]]; then
    echo "Usage: sudo $0 /path/to/SafeBrowse.app" >&2
    exit 1
fi

HELPER_SOURCE="${APP_PATH}/Contents/Resources/safebrowse-helper"
if [[ ! -f "$HELPER_SOURCE" ]]; then
    echo "Error: helper binary not found at ${HELPER_SOURCE}." >&2
    echo "Build the project first (Product → Build in Xcode)." >&2
    exit 1
fi

# ── Install binary ─────────────────────────────────────────────────────────
echo "Installing safebrowse-helper to ${HELPER_BINARY}…"
cp -f "$HELPER_SOURCE" "$HELPER_BINARY"
chmod 755 "$HELPER_BINARY"
chown root:wheel "$HELPER_BINARY"

# ── Create data directory ──────────────────────────────────────────────────
# 777 so the app (running as the logged-in user) can write blocklist files
# while the helper (running as root) reads them.
DATA_DIR="/Library/Application Support/SafeBrowse"
mkdir -p "$DATA_DIR"
chmod 777 "$DATA_DIR"

# ── Write LaunchDaemon plist ───────────────────────────────────────────────
echo "Writing LaunchDaemon plist to ${PLIST_PATH}…"
cat > "$PLIST_PATH" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.safebrowse.helper</string>

    <key>ProgramArguments</key>
    <array>
        <string>${HELPER_BINARY}</string>
    </array>

    <!-- Start immediately and restart if it crashes -->
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>

    <!-- Give the SIGTERM handler enough time to restore system DNS (networksetup subprocesses) -->
    <key>ExitTimeout</key>
    <integer>30</integer>

    <key>StandardOutPath</key>
    <string>${LOG_PATH}</string>
    <key>StandardErrorPath</key>
    <string>${LOG_PATH}</string>
</dict>
</plist>
PLIST_EOF

chmod 644 "$PLIST_PATH"
chown root:wheel "$PLIST_PATH"

# ── Load LaunchDaemon (helper) ─────────────────────────────────────────────
echo "Loading LaunchDaemon…"
launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load -w "$PLIST_PATH"

# ── Write LaunchAgent (auto-restart GUI app) ───────────────────────────────
echo "Writing LaunchAgent plist to ${AGENT_PLIST}…"
cat > "$AGENT_PLIST" << AGENT_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.safebrowse.app</string>

    <key>ProgramArguments</key>
    <array>
        <string>${APP_BINARY}</string>
    </array>

    <!-- Start on login; restart only on crash/force-kill, not on clean exit -->
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>ThrottleInterval</key>
    <integer>3</integer>
</dict>
</plist>
AGENT_EOF

chmod 644 "$AGENT_PLIST"
chown root:wheel "$AGENT_PLIST"

# Load agent for the current console user if possible
REAL_USER="${SUDO_USER:-}"
if [[ -n "$REAL_USER" ]]; then
    REAL_UID=$(id -u "$REAL_USER" 2>/dev/null || echo "")
    if [[ -n "$REAL_UID" ]]; then
        launchctl bootout "gui/$REAL_UID" "$AGENT_PLIST" 2>/dev/null || true
        launchctl bootstrap "gui/$REAL_UID" "$AGENT_PLIST" 2>/dev/null || true
    fi
fi

echo ""
echo "✓ SafeBrowse helper installed and running."
echo "  Log: ${LOG_PATH}"
echo "  Control socket: /var/run/safebrowse.sock"
echo "  GUI app will auto-restart if killed."
echo ""
echo "Open SafeBrowse.app to configure blocklists and set a password."
