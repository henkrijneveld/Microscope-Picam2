#!/usr/bin/env bash

set -e

FRONTEND_DIST="frontend/dist/index.html"

if [ ! -f "$FRONTEND_DIST" ]; then
  echo "Frontend build ontbreekt: frontend/dist/index.html" >&2
  echo "Bouw de frontend op de dev-machine met 'npm --prefix frontend run build', commit frontend/dist en doe daarna git pull op de Pi." >&2
  exit 1
fi

exec .venv/bin/uvicorn backend.app.main:app \
  --host 0.0.0.0 \
  --port 8000 \
  --timeout-graceful-shutdown 2
