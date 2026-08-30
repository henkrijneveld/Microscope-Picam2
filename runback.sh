#!/usr/bin/env bash

set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

ENV_FILE="frontend/.env.local"
FRONTEND_DIST="frontend/dist/index.html"

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

if [ ! -f "$FRONTEND_DIST" ]; then
  echo "Frontend build ontbreekt: frontend/dist/index.html" >&2
  echo "Deploy de applicatie opnieuw vanaf de ontwikkelmachine met deploy.sh." >&2
  exit 1
fi

exec .venv/bin/uvicorn backend.app.main:app \
  --host 0.0.0.0 \
  --port 8000 \
  --timeout-graceful-shutdown 2
