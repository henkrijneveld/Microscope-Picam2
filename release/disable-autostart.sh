#!/usr/bin/env bash

set -euo pipefail

SERVICE_NAME="microscope-picam2"

sudo systemctl disable "$SERVICE_NAME.service"
echo "$SERVICE_NAME autostart disabled."
echo "The service keeps its current running state until you use ./start.sh or ./stop.sh."
