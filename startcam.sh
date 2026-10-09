#!/usr/bin/env bash

set -euo pipefail

SERVICE_NAME="microscope-picam2"

sudo systemctl start "$SERVICE_NAME"
sudo systemctl --no-pager --full status "$SERVICE_NAME" || true
