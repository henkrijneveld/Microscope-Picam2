#!/usr/bin/env bash

set -euo pipefail

SERVICE_NAME="microscope-picam2"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON="/usr/bin/python3"
PYTHON_DIR="$ROOT_DIR/python"
REQUIREMENTS="$ROOT_DIR/requirements.txt"
RUN_USER="${SUDO_USER:-$(id -un)}"
RUN_GROUP="$(id -gn "$RUN_USER")"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
POWEROFF_HELPER="/usr/local/sbin/microscope-picam2-poweroff"
SUDOERS_FILE="/etc/sudoers.d/microscope-picam2-poweroff"

as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

if ! command -v apt-get >/dev/null 2>&1; then
  echo "This installation script expects Raspberry Pi OS/Debian with apt." >&2
  exit 1
fi

if [ ! -f "$REQUIREMENTS" ]; then
  echo "Missing file: $REQUIREMENTS" >&2
  exit 1
fi

if [ ! -f "$ROOT_DIR/resources/mertens.sh" ]; then
  echo "Canonical Mertens script is missing: $ROOT_DIR/resources/mertens.sh" >&2
  exit 1
fi

if [ ! -f "$ROOT_DIR/frontend/dist/index.html" ]; then
  echo "Frontend build is missing from $ROOT_DIR/frontend/dist." >&2
  exit 1
fi

mkdir -p "$ROOT_DIR/photos"

echo "Installing system packages..."
as_root apt-get update
as_root apt-get install -y --no-install-recommends \
  python3-picamera2 \
  python3-pip \
  sudo

# The webserver runs as the user who installed MicroRasp and must be able
# to create photos even when install.sh itself was started with sudo.
as_root chown "$RUN_USER:$RUN_GROUP" "$ROOT_DIR/photos"

if [ ! -x "$PYTHON" ]; then
  echo "System Python is missing after installation: $PYTHON" >&2
  exit 1
fi

echo "Checking Picamera2/libcamera..."
"$PYTHON" - <<'PY'
from picamera2 import Picamera2
import libcamera
print("Picamera2/libcamera OK")
PY

echo "Stopping existing MicroRasp service if present..."
as_root systemctl stop "$SERVICE_NAME.service" 2>/dev/null || true

echo "Installing MicroRasp Python dependencies..."
rm -rf "$PYTHON_DIR"
mkdir -p "$PYTHON_DIR"
touch "$PYTHON_DIR/.gitkeep"

"$PYTHON" -m pip install \
  --upgrade \
  --target "$PYTHON_DIR" \
  --requirement "$REQUIREMENTS"

PYTHON_TAG="$("$PYTHON" - <<'PY'
import sys
print(sys.implementation.cache_tag or f"python-{sys.version_info.major}.{sys.version_info.minor}")
PY
)"
printf '%s\n' "$PYTHON_TAG" > "$PYTHON_DIR/.python-tag"

echo "Checking Python installation..."
PYTHONPATH="$PYTHON_DIR" "$PYTHON" - <<'PY'
import fastapi
import piexif
import pydantic
import uvicorn
from picamera2 import Picamera2

print("FastAPI", fastapi.__version__)
print("Pydantic", pydantic.__version__)
print("Uvicorn", uvicorn.__version__)
print("MicroRasp Python-dependencies OK")
PY

chmod +x "$ROOT_DIR/run.sh" "$ROOT_DIR/start.sh" "$ROOT_DIR/stop.sh" "$ROOT_DIR/check-installation.sh"
chmod 0555 "$ROOT_DIR/resources/mertens.sh"

SYSTEMCTL="$(command -v systemctl)"
SERVICE_TMP="$(mktemp)"
HELPER_TMP="$(mktemp)"
SUDOERS_TMP="$(mktemp)"
trap 'rm -f "$SERVICE_TMP" "$HELPER_TMP" "$SUDOERS_TMP"' EXIT

cat > "$SERVICE_TMP" <<EOF
[Unit]
Description=MicroRasp microscope camera webserver
After=network.target

[Service]
Type=simple
User=$RUN_USER
Group=$RUN_GROUP
WorkingDirectory=$ROOT_DIR
ExecStart=$ROOT_DIR/run.sh
Restart=on-failure
RestartSec=2
RestartPreventExitStatus=78

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

if ! as_root visudo -cf "$SUDOERS_TMP" >/dev/null; then
  echo "Sudoers configuration for poweroff is invalid." >&2
  exit 1
fi

echo "Installing poweroff helper..."
as_root install -o root -g root -m 0755 "$HELPER_TMP" "$POWEROFF_HELPER"
as_root install -o root -g root -m 0440 "$SUDOERS_TMP" "$SUDOERS_FILE"

echo "Installing systemd service..."
as_root install -o root -g root -m 0644 "$SERVICE_TMP" "$SERVICE_FILE"
as_root systemctl daemon-reload
as_root systemctl enable "$SERVICE_NAME.service"
as_root systemctl restart "$SERVICE_NAME.service"

echo
as_root systemctl --no-pager --full status "$SERVICE_NAME.service" || true

echo
echo "Checking installation..."
"$ROOT_DIR/check-installation.sh"

echo
echo "MicroRasp is installed and verified."
echo "Python:   $("$PYTHON" --version 2>&1) ($PYTHON_TAG)"
echo "Hostname: $(hostname)"
echo "Web:      http://$(hostname).local:8000/"
echo
echo "Optional overrides can be placed in:"
echo "  $ROOT_DIR/.env.local"
echo
echo "After a system Python upgrade, run ./install.sh again."
