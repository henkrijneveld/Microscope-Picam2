#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

ENV_FILE="frontend/.env.local"

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

PI_HOST="${1:-${PI_HOST:-}}"
DEPLOY_DIR="${DEPLOY_DIR:-Deploy/Microscope-Picam2}"

if [ -z "$PI_HOST" ]; then
  echo "PI_HOST is missing." >&2
  echo "For example, set PI_HOST=Raspi3B-1.local in $ENV_FILE" >&2
  echo "or use: ./sync-dev.sh <pi-host>" >&2
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "npm is not available on the development machine." >&2
  exit 1
fi

if ! command -v rsync >/dev/null 2>&1; then
  echo "rsync is not available on the development machine." >&2
  exit 1
fi

echo "Building frontend..."
npm --prefix frontend run build

echo "Preparing deploy directory on $PI_HOST..."
ssh "$PI_HOST" "mkdir -p ~/$DEPLOY_DIR/backend ~/$DEPLOY_DIR/frontend/dist"

echo "Deploying backend..."
rsync -az --delete \
  --exclude '__pycache__/' \
  --exclude '*.pyc' \
  backend/ \
  "$PI_HOST:~/$DEPLOY_DIR/backend/"

echo "Deploying frontend..."
rsync -az --delete \
  frontend/dist/ \
  "$PI_HOST:~/$DEPLOY_DIR/frontend/dist/"

if [ -f "$ENV_FILE" ]; then
  echo "Deploying local configuration..."
  rsync -az \
    "$ENV_FILE" \
    "$PI_HOST:~/$DEPLOY_DIR/frontend/.env.local"
fi

echo "Deploying start, stop and installation scripts..."
rsync -az \
  dev/runback.sh \
  dev/startcam.sh \
  dev/stopcam.sh \
  dev/install-autostart.sh \
  "$PI_HOST:~/$DEPLOY_DIR/"

ssh "$PI_HOST" "chmod +x ~/$DEPLOY_DIR/runback.sh ~/$DEPLOY_DIR/startcam.sh ~/$DEPLOY_DIR/stopcam.sh ~/$DEPLOY_DIR/install-autostart.sh"

echo "Deploy complete: $PI_HOST:~/$DEPLOY_DIR"
