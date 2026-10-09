#!/usr/bin/env bash

set -euo pipefail

SERVICE_NAME="microscope-picam2"
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

if ! command -v systemctl >/dev/null 2>&1; then
  echo "systemctl is not available on this system." >&2
  exit 1
fi

echo "Stopping and disabling MicroRasp service..."
as_root systemctl disable --now "$SERVICE_NAME.service" 2>/dev/null || true

echo "Removing MicroRasp system files..."
as_root rm -f "$SERVICE_FILE"
as_root rm -f "$POWEROFF_HELPER"
as_root rm -f "$SUDOERS_FILE"

as_root systemctl daemon-reload
as_root systemctl reset-failed "$SERVICE_NAME.service" 2>/dev/null || true

echo
echo "MicroRasp system integration has been removed."
echo "The MicroRasp directory, installed local Python packages and photos were left untouched."
echo "Remove the MicroRasp directory manually if you no longer need it."
