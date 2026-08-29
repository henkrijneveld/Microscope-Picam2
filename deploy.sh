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
  echo "PI_HOST ontbreekt." >&2
  echo "Zet bijvoorbeeld PI_HOST=Raspi3B-1.local in $ENV_FILE" >&2
  echo "of gebruik: ./deploy.sh <pi-host>" >&2
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "npm is niet beschikbaar op de ontwikkelmachine." >&2
  exit 1
fi

if ! command -v rsync >/dev/null 2>&1; then
  echo "rsync is niet beschikbaar op de ontwikkelmachine." >&2
  exit 1
fi

echo "Frontend bouwen..."
npm --prefix frontend run build

echo "Deploy-directory voorbereiden op $PI_HOST..."
ssh "$PI_HOST" "mkdir -p ~/$DEPLOY_DIR/backend ~/$DEPLOY_DIR/frontend/dist"

echo "Backend deployen..."
rsync -az --delete \
  --exclude '__pycache__/' \
  --exclude '*.pyc' \
  backend/ \
  "$PI_HOST:~/$DEPLOY_DIR/backend/"

echo "Frontend deployen..."
rsync -az --delete \
  frontend/dist/ \
  "$PI_HOST:~/$DEPLOY_DIR/frontend/dist/"

echo "Start-, stop- en installatiescripts deployen..."
rsync -az \
  runback.sh \
  startcam.sh \
  stopcam.sh \
  install-autostart.sh \
  "$PI_HOST:~/$DEPLOY_DIR/"

ssh "$PI_HOST" "chmod +x ~/$DEPLOY_DIR/runback.sh ~/$DEPLOY_DIR/startcam.sh ~/$DEPLOY_DIR/stopcam.sh ~/$DEPLOY_DIR/install-autostart.sh"

echo "Deploy gereed: $PI_HOST:~/$DEPLOY_DIR"
