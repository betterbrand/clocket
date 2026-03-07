#!/usr/bin/env bash
set -euo pipefail

# Clocket — Install Script
# Installs Radicale, configures it, and sets up persistence.
# Supports macOS (LaunchAgent) and Linux (systemd user unit).

RADICALE_PORT="${RADICALE_PORT:-5232}"
RADICALE_USER="${RADICALE_USER:-agent}"
RADICALE_PASS="${RADICALE_PASS:-$(openssl rand -hex 12)}"
CONFIG_DIR="${HOME}/.config/radicale"
DATA_DIR="${HOME}/.openclaw/workspace/data/radicale/collections"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Clocket — Install ==="
echo ""

# ── 1. Install Radicale ──────────────────────────────────────

RADICALE_BIN=""

if command -v radicale &>/dev/null; then
    RADICALE_BIN=$(command -v radicale)
    echo "✓ Radicale already installed: ${RADICALE_BIN}"
else
    echo "  Installing Radicale via pip..."
    pip3 install --user radicale 2>&1 | tail -1
    echo ""
fi

# Find radicale binary
if [ -z "$RADICALE_BIN" ]; then
    for candidate in \
        "$(command -v radicale 2>/dev/null || echo "")" \
        "${HOME}/Library/Python/3.9/bin/radicale" \
        "${HOME}/Library/Python/3.11/bin/radicale" \
        "${HOME}/Library/Python/3.12/bin/radicale" \
        "${HOME}/Library/Python/3.13/bin/radicale" \
        "${HOME}/.local/bin/radicale"; do
        if [ -n "$candidate" ] && [ -x "$candidate" ] 2>/dev/null; then
            RADICALE_BIN="$candidate"
            break
        fi
    done
fi

[ -z "$RADICALE_BIN" ] && { echo "✗ Could not find radicale binary. Add Python user bin to PATH."; exit 1; }
echo "✓ Radicale binary: ${RADICALE_BIN}"

# ── 2. Configure ─────────────────────────────────────────────

mkdir -p "$CONFIG_DIR" "$DATA_DIR"

# Detect if bcrypt is available
AUTH_TYPE="plain"
if python3 -c "import bcrypt" 2>/dev/null; then
    AUTH_TYPE="bcrypt"
fi

cat > "${CONFIG_DIR}/config" << EOF
[server]
hosts = 127.0.0.1:${RADICALE_PORT}

[auth]
type = htpasswd
htpasswd_filename = ${CONFIG_DIR}/users
htpasswd_encryption = ${AUTH_TYPE}

[storage]
filesystem_folder = ${DATA_DIR}

[logging]
level = info
EOF

# Write credentials
if [ "$AUTH_TYPE" = "bcrypt" ]; then
    HASHED=$(python3 -c "import bcrypt; print(bcrypt.hashpw(b'${RADICALE_PASS}', bcrypt.gensalt()).decode())")
    echo "${RADICALE_USER}:${HASHED}" > "${CONFIG_DIR}/users"
else
    echo "${RADICALE_USER}:${RADICALE_PASS}" > "${CONFIG_DIR}/users"
fi
chmod 600 "${CONFIG_DIR}/users"

echo "✓ Config: ${CONFIG_DIR}/config (auth: ${AUTH_TYPE})"

# ── 3. Persistence ───────────────────────────────────────────

OS="$(uname)"

if [ "$OS" = "Darwin" ]; then
    # macOS: LaunchAgent
    PLIST_PATH="${HOME}/Library/LaunchAgents/com.clocket.plist"
    mkdir -p "$(dirname "$PLIST_PATH")"

    cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.clocket</string>
    <key>ProgramArguments</key>
    <array>
        <string>${RADICALE_BIN}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/clocket.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/clocket-error.log</string>
</dict>
</plist>
EOF

    # Unload old branding if present
    launchctl unload "${HOME}/Library/LaunchAgents/com.radicale-calendar.plist" 2>/dev/null || true
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    launchctl load "$PLIST_PATH"
    echo "✓ LaunchAgent installed: com.clocket"

elif [ "$OS" = "Linux" ]; then
    # Linux: systemd user unit
    UNIT_DIR="${HOME}/.config/systemd/user"
    mkdir -p "$UNIT_DIR"

    cat > "${UNIT_DIR}/clocket.service" << EOF
[Unit]
Description=Clocket (Radicale CalDAV server)
After=network.target

[Service]
Type=simple
ExecStart=${RADICALE_BIN}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable --now clocket.service
    echo "✓ Systemd user unit installed: clocket.service"
else
    echo "⚠ Unknown OS (${OS}). Start manually: ${RADICALE_BIN} &"
fi

# ── 4. Verify ────────────────────────────────────────────────

sleep 2
if curl -sf "http://127.0.0.1:${RADICALE_PORT}/.well-known/caldav" -u "${RADICALE_USER}:${RADICALE_PASS}" >/dev/null 2>&1; then
    echo "✓ Radicale responding on port ${RADICALE_PORT}"
else
    echo "⚠ Radicale may not be ready yet."
    if [ "$OS" = "Darwin" ]; then
        echo "  Check: cat /tmp/clocket-error.log"
    elif [ "$OS" = "Linux" ]; then
        echo "  Check: journalctl --user -u clocket.service"
    fi
fi

# ── 5. Save credentials for clocket.sh ──────────────────────

cat > "${CONFIG_DIR}/skill.env" << EOF
RADICALE_URL=http://127.0.0.1:${RADICALE_PORT}
RADICALE_USER=${RADICALE_USER}
RADICALE_PASS=${RADICALE_PASS}
EOF
chmod 600 "${CONFIG_DIR}/skill.env"

echo ""
echo "=== Clocket installed ==="
echo ""
echo "  Server:  http://127.0.0.1:${RADICALE_PORT}"
echo "  User:    ${RADICALE_USER}"
echo "  Pass:    ${RADICALE_PASS}"
echo "  Data:    ${DATA_DIR}"
echo "  Auth:    ${AUTH_TYPE}"
echo ""
echo "  Connect any CalDAV client to http://127.0.0.1:${RADICALE_PORT}"
echo "  Run: bash scripts/clocket.sh status"
