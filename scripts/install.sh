#!/usr/bin/env bash
set -euo pipefail

# Radicale Calendar Skill — Install Script
# Installs Radicale, configures it, sets up LaunchAgent for persistence.

RADICALE_PORT="${RADICALE_PORT:-5232}"
RADICALE_USER="${RADICALE_USER:-agent}"
RADICALE_PASS="${RADICALE_PASS:-$(openssl rand -hex 12)}"
CONFIG_DIR="${HOME}/.config/radicale"
DATA_DIR="${HOME}/.openclaw/workspace/data/radicale/collections"
PLIST_PATH="${HOME}/Library/LaunchAgents/com.radicale-calendar.plist"

echo "=== Radicale Calendar Skill — Install ==="

# 1. Install Radicale
if command -v radicale &>/dev/null || python3 -m radicale --version &>/dev/null 2>&1; then
    echo "[OK] Radicale already installed"
    RADICALE_BIN=$(command -v radicale 2>/dev/null || echo "")
else
    echo "[..] Installing Radicale via pip..."
    pip3 install --user radicale
    echo "[OK] Radicale installed"
fi

# Find radicale binary
if [ -z "${RADICALE_BIN:-}" ]; then
    # Check common locations
    for candidate in \
        "$(command -v radicale 2>/dev/null)" \
        "${HOME}/Library/Python/3.9/bin/radicale" \
        "${HOME}/Library/Python/3.11/bin/radicale" \
        "${HOME}/Library/Python/3.12/bin/radicale" \
        "${HOME}/.local/bin/radicale"; do
        if [ -x "$candidate" ] 2>/dev/null; then
            RADICALE_BIN="$candidate"
            break
        fi
    done
fi

if [ -z "${RADICALE_BIN:-}" ]; then
    echo "[ERROR] Could not find radicale binary. Add Python user bin to PATH."
    exit 1
fi

echo "[OK] Radicale binary: $RADICALE_BIN"

# 2. Create config
mkdir -p "$CONFIG_DIR" "$DATA_DIR"

cat > "${CONFIG_DIR}/config" << EOF
[server]
hosts = 127.0.0.1:${RADICALE_PORT}

[auth]
type = htpasswd
htpasswd_filename = ${CONFIG_DIR}/users
htpasswd_encryption = plain

[storage]
filesystem_folder = ${DATA_DIR}

[logging]
level = info
EOF

echo "${RADICALE_USER}:${RADICALE_PASS}" > "${CONFIG_DIR}/users"
chmod 600 "${CONFIG_DIR}/users"

echo "[OK] Config written to ${CONFIG_DIR}/config"
echo "[OK] Credentials: ${RADICALE_USER} / ${RADICALE_PASS}"

# 3. Create LaunchAgent (macOS) or systemd unit (Linux)
if [[ "$(uname)" == "Darwin" ]]; then
    cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.radicale-calendar</string>
    <key>ProgramArguments</key>
    <array>
        <string>${RADICALE_BIN}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/radicale.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/radicale-error.log</string>
</dict>
</plist>
EOF
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    launchctl load "$PLIST_PATH"
    echo "[OK] LaunchAgent installed and loaded"
else
    echo "[SKIP] LaunchAgent is macOS-only. Start manually: ${RADICALE_BIN} &"
fi

# 4. Wait for server
sleep 2
if curl -sf "http://127.0.0.1:${RADICALE_PORT}/.well-known/caldav" -u "${RADICALE_USER}:${RADICALE_PASS}" >/dev/null 2>&1; then
    echo "[OK] Radicale is running on port ${RADICALE_PORT}"
else
    echo "[WARN] Radicale may not be ready yet. Check /tmp/radicale.log"
fi

# 5. Save credentials for calendar.sh
cat > "${CONFIG_DIR}/skill.env" << EOF
RADICALE_URL=http://127.0.0.1:${RADICALE_PORT}
RADICALE_USER=${RADICALE_USER}
RADICALE_PASS=${RADICALE_PASS}
EOF
chmod 600 "${CONFIG_DIR}/skill.env"

echo ""
echo "=== Install complete ==="
echo "Server: http://127.0.0.1:${RADICALE_PORT}"
echo "User:   ${RADICALE_USER}"
echo "Pass:   ${RADICALE_PASS}"
echo "Data:   ${DATA_DIR}"
echo ""
echo "Connect any CalDAV client to http://127.0.0.1:${RADICALE_PORT}"
