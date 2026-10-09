#!/usr/bin/env bash

set -euo pipefail

SERVICE_NAME="microscope-picam2"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_USER="${SUDO_USER:-$(id -un)}"
RUN_GROUP="$(id -gn "$RUN_USER")"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
POWEROFF_HELPER="/usr/local/sbin/microscope-picam2-poweroff"
SUDOERS_FILE="/etc/sudoers.d/microscope-picam2-poweroff"
SYSTEMCTL="$(command -v systemctl)"

cd "$ROOT_DIR"

if [ ! -x ".venv/bin/uvicorn" ]; then
  echo "Uvicorn is missing from $ROOT_DIR/.venv." >&2
  exit 1
fi

if [ ! -f "frontend/dist/index.html" ]; then
  echo "Frontend build is missing from $ROOT_DIR/frontend/dist." >&2
  exit 1
fi

chmod +x "$ROOT_DIR/runback.sh"

SERVICE_TMP="$(mktemp)"
HELPER_TMP="$(mktemp)"
SUDOERS_TMP="$(mktemp)"
trap 'rm -f "$SERVICE_TMP" "$HELPER_TMP" "$SUDOERS_TMP"' EXIT

cat > "$SERVICE_TMP" <<EOF
[Unit]
Description=Microscope Picam2 webserver
After=network.target

[Service]
Type=simple
User=$RUN_USER
Group=$RUN_GROUP
WorkingDirectory=$ROOT_DIR
ExecStart=$ROOT_DIR/runback.sh
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

cat > "$HELPER_TMP" <<EOF
#!/bin/sh
exec "$SYSTEMCTL" poweroff
EOF

cat > "$SUDOERS_TMP" <<EOF
$RUN_USER ALL=(root) NOPASSWD: $POWEROFF_HELPER
EOF

if ! sudo visudo -cf "$SUDOERS_TMP" >/dev/null; then
  echo "Sudoers configuration for poweroff is invalid." >&2
  exit 1
fi

echo "Installing poweroff helper..."
sudo install -o root -g root -m 0755 "$HELPER_TMP" "$POWEROFF_HELPER"
sudo install -o root -g root -m 0440 "$SUDOERS_TMP" "$SUDOERS_FILE"

echo "Installing systemd service as $SERVICE_NAME..."
sudo cp "$SERVICE_TMP" "$SERVICE_FILE"
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME.service"
sudo systemctl restart "$SERVICE_NAME.service"

echo
sudo systemctl --no-pager --full status "$SERVICE_NAME.service" || true

echo
echo "Autostart installed."
echo "Status:  sudo systemctl status $SERVICE_NAME"
echo "Restart: sudo systemctl restart $SERVICE_NAME"
echo "Logs:    journalctl -u $SERVICE_NAME -f"
echo "The web interface can now shut down the Pi cleanly as well."
