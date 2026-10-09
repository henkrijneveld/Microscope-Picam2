#!/usr/bin/env bash

set -euo pipefail

SERVICE_NAME="microscope-picam2"

sudo systemctl enable "$SERVICE_NAME.service"
echo "$SERVICE_NAME autostart enabled."
