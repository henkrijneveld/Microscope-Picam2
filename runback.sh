#!/usr/bin/env bash

set -e

FRONTEND_DIST="frontend/dist/index.html"

frontend_needs_build=false

if [ ! -f "$FRONTEND_DIST" ]; then
  frontend_needs_build=true
elif find \
  frontend/src \
  frontend/package.json \
  frontend/package-lock.json \
  frontend/vite.config.js \
  -type f -newer "$FRONTEND_DIST" -print -quit | grep -q .; then
  frontend_needs_build=true
fi

if [ "$frontend_needs_build" = true ]; then
  if ! command -v npm >/dev/null 2>&1; then
    echo "Frontend moet opnieuw gebouwd worden, maar npm is niet beschikbaar." >&2
    exit 1
  fi

  if [ ! -d frontend/node_modules ] || [ frontend/package-lock.json -nt frontend/node_modules/.package-lock.json ]; then
    npm --prefix frontend ci
  fi

  npm --prefix frontend run build
fi

exec .venv/bin/uvicorn backend.app.main:app \
  --host 0.0.0.0 \
  --port 8000 \
  --timeout-graceful-shutdown 2
