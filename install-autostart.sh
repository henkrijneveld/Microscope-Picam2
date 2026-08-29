#!/usr/bin/env bash

set -euo pipefail

SERVICE_NAME="microscope-picam2"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_USER="${SUDO_USER:-$(id -un)}"
RUN_GROUP="$(id -gn "$RUN_USER")"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

cd "$ROOT_DIR"

if [ ! -x ".venv/bin/uvicorn" ]; then
  echo "Uvicorn ontbreekt in $ROOT_DIR/.venv." >&2
  exit 1
fi

if [ ! -f "frontend/dist/index.html" ]; then
  echo "Frontend build ontbreekt in $ROOT_DIR/frontend/dist." >&2
  exit 1
fi

chmod +x "$ROOT_DIR/runback.sh"

TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

cat > "$TMP_FILE" <<EOF
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

echo "Systemd-service installeren als $SERVICE_NAME..."
sudo cp "$TMP_FILE" "$SERVICE_FILE"
sudo systemctl daemon-reload
sudo systemctl enable --now "$SERVICE_NAME.service"

echo
sudo systemctl --no-pager --full status "$SERVICE_NAME.service" || true

echo
echo "Autostart geïnstalleerd."
echo "Status:  sudo systemctl status $SERVICE_NAME"
echo "Restart: sudo systemctl restart $SERVICE_NAME"
echo "Logs:    journalctl -u $SERVICE_NAME -f"
