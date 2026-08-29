#!/usr/bin/env bash

set -euo pipefail

SERVICE_NAME="microscope-picam2"

sudo systemctl stop "$SERVICE_NAME"
echo "$SERVICE_NAME gestopt."
