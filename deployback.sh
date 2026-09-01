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
  echo "of gebruik: bash deployback.sh <pi-host>" >&2
  exit 1
fi

if ! command -v rsync >/dev/null 2>&1; then
  echo "rsync is niet beschikbaar op de ontwikkelmachine." >&2
  exit 1
fi

echo "Backend deployen naar $PI_HOST..."
ssh "$PI_HOST" "mkdir -p ~/$DEPLOY_DIR/backend"

rsync -az --delete \
  --exclude '__pycache__/' \
  --exclude '*.pyc' \
  backend/ \
  "$PI_HOST:~/$DEPLOY_DIR/backend/"

echo "Backend deploy gereed: $PI_HOST:~/$DEPLOY_DIR/backend"
