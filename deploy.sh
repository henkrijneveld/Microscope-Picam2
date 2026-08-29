#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

PI_HOST="${1:-${PI_HOST:-}}"
DEPLOY_DIR="${DEPLOY_DIR:-Deploy/Microscope-Picam2}"

if [ -z "$PI_HOST" ]; then
  echo "Gebruik: ./deploy.sh <pi-host>" >&2
  echo "of zet PI_HOST, bijvoorbeeld: export PI_HOST=Raspi3B-1.local" >&2
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

echo "Startscript deployen..."
rsync -az \
  runback.sh \
  "$PI_HOST:~/$DEPLOY_DIR/runback.sh"

ssh "$PI_HOST" "chmod +x ~/$DEPLOY_DIR/runback.sh"

echo "Deploy gereed: $PI_HOST:~/$DEPLOY_DIR"
