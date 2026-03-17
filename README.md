# SafeBrowse

A macOS menu-bar app that blocks unsafe domains at the OS level using public blocklists.
Blocking is done via a local DNS proxy on port 53 — no network extension entitlements required.

## How it works

```
SafeBrowse.app  (menu bar, user space)
       │  Unix socket: /var/run/safebrowse.sock
       ▼
safebrowse-helper  (LaunchDaemon, root)
       │  listens on 127.0.0.1:53
       ▼
System DNS → 127.0.0.1 → proxy → blocklist check → 1.1.1.1 (upstream)
```

Blocked domains receive an **NXDOMAIN** response.
Allowing/blocking only changes a flag in the proxy — system DNS stays pointed at `127.0.0.1` throughout.

## Requirements

- macOS 13 (Ventura) or later
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Build

```bash
cd SafeBrowse
xcodegen generate          # creates SafeBrowse.xcodeproj
open SafeBrowse.xcodeproj
# Build → Product → Build (⌘B)
```

## Install the helper daemon (once, as root)

```bash
sudo ./install.sh ~/Library/Developer/Xcode/DerivedData/SafeBrowse-.../Build/Products/Debug/SafeBrowse.app
```

Or after archiving: `sudo ./install.sh /Applications/SafeBrowse.app`

This:
1. Copies `safebrowse-helper` to `/usr/local/bin/`
2. Installs a LaunchDaemon at `/Library/LaunchDaemons/com.safebrowse.helper.plist`
3. Starts the daemon (it survives reboots)

## Uninstall

```bash
sudo ./uninstall.sh
```

## Usage

1. Launch **SafeBrowse.app** — the shield icon appears in the menu bar
2. Open the app window to choose blocklists and update them
3. Set a password (Settings tab) to protect the pause function
4. Click the shield → **Pause Protection…** to temporarily bypass blocking

## Built-in blocklists

| Name | Format | ~Domains |
|------|--------|----------|
| OISD Basic | hosts | 50 k |
| Steven Black (ads + malware) | hosts | 250 k |
| Hagezi Pro | plain | 400 k |

Custom blocklist URLs (hosts format or plain domain list) can be added in the app.

## Files

```
SafeBrowse/
├── Shared/              ← Shared types (socket protocol)
├── SafeBrowseHelper/    ← Privileged daemon source
├── SafeBrowse/          ← Menu-bar app source
├── project.yml          ← XcodeGen project spec
├── install.sh           ← sudo installer
└── uninstall.sh         ← sudo uninstaller
```

## Testing

```bash
# Is the helper running?
pgrep safebrowse-helper

# Test DNS proxy directly (before changing system DNS)
dig @127.0.0.1 google.com          # should resolve
dig @127.0.0.1 doubleclick.net     # should return NXDOMAIN (if list is loaded)

# Check system DNS after enabling
scutil --dns | grep nameserver

# View helper logs
tail -f /var/log/safebrowse-helper.log
```
