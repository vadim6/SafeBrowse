#!/usr/bin/env bash
# SafeBrowse uninstaller — must be run as root (sudo ./uninstall.sh)

set -euo pipefail

HELPER_BINARY="/usr/local/bin/safebrowse-helper"
PLIST_PATH="/Library/LaunchDaemons/com.safebrowse.helper.plist"
AGENT_PLIST="/Library/LaunchAgents/com.safebrowse.app.plist"
SOCKET_PATH="/var/run/safebrowse.sock"

if [[ $EUID -ne 0 ]]; then
    echo "Error: uninstall.sh must be run as root." >&2
    exit 1
fi

# ── Ask helper to restore DNS before we kill it ────────────────────────────
if [[ -S "$SOCKET_PATH" ]]; then
    echo "Asking helper to restore DNS settings…"
    # Send restoreSystemDNS command via Python (always available on macOS)
    python3 - << 'PYEOF' || true
import socket, json
msg = json.dumps({"command": "restoreSystemDNS", "payload": None}).encode()
try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(5)
    s.connect("/var/run/safebrowse.sock")
    s.sendall(msg)
    s.close()
except Exception as e:
    print(f"  (Could not contact helper: {e})")
PYEOF
    sleep 1
fi

# ── Unload and remove LaunchDaemon ────────────────────────────────────────
if [[ -f "$PLIST_PATH" ]]; then
    echo "Unloading LaunchDaemon…"
    launchctl unload -w "$PLIST_PATH" 2>/dev/null || true
    rm -f "$PLIST_PATH"
fi

# ── Unload and remove LaunchAgent (GUI auto-restart) ─────────────────────
if [[ -f "$AGENT_PLIST" ]]; then
    echo "Unloading LaunchAgent…"
    REAL_USER="${SUDO_USER:-}"
    if [[ -n "$REAL_USER" ]]; then
        REAL_UID=$(id -u "$REAL_USER" 2>/dev/null || echo "")
        [[ -n "$REAL_UID" ]] && launchctl bootout "gui/$REAL_UID" "$AGENT_PLIST" 2>/dev/null || true
    fi
    rm -f "$AGENT_PLIST"
fi

# ── Remove helper binary ───────────────────────────────────────────────────
[[ -f "$HELPER_BINARY" ]] && rm -f "$HELPER_BINARY" && echo "Removed $HELPER_BINARY"

# ── Remove data directory (optional) ─────────────────────────────────────
read -rp "Remove blocklist data (/Library/Application Support/SafeBrowse)? [y/N] " REPLY
if [[ "${REPLY,,}" == "y" ]]; then
    rm -rf "/Library/Application Support/SafeBrowse"
    echo "Removed data directory."
fi

echo ""
echo "✓ SafeBrowse uninstalled. DNS settings restored."
