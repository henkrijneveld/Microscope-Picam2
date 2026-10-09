#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON="/usr/bin/python3"
PYTHON_DIR="$ROOT_DIR/python"
PYTHON_TAG_FILE="$PYTHON_DIR/.python-tag"
ENV_FILE="$ROOT_DIR/.env.local"
FRONTEND_INDEX="$ROOT_DIR/frontend/dist/index.html"
PHOTOS_DIR="$ROOT_DIR/photos"
MERTENS_SOURCE="$ROOT_DIR/resources/mertens.sh"
MERTENS_TARGET="$PHOTOS_DIR/mertens.sh"

cd "$ROOT_DIR"

if [ ! -f "$MERTENS_SOURCE" ]; then
  echo "Canonical Mertens script is missing: $MERTENS_SOURCE" >&2
  exit 78
fi

mkdir -p "$PHOTOS_DIR"
rm -rf -- "$MERTENS_TARGET"
install -m 0555 "$MERTENS_SOURCE" "$MERTENS_TARGET"

if [ ! -x "$PYTHON" ]; then
  echo "System Python is missing: $PYTHON" >&2
  exit 78
fi

if [ ! -f "$FRONTEND_INDEX" ]; then
  echo "Frontend is missing: $FRONTEND_INDEX" >&2
  echo "Use a complete MicroRasp distribution." >&2
  exit 78
fi

if [ ! -f "$PYTHON_TAG_FILE" ]; then
  echo "MicroRasp Python dependencies have not been installed yet." >&2
  echo "Run ./install.sh." >&2
  exit 78
fi

CURRENT_PYTHON_TAG="$("$PYTHON" - <<'PY'
import sys
print(sys.implementation.cache_tag or f"python-{sys.version_info.major}.{sys.version_info.minor}")
PY
)"
INSTALLED_PYTHON_TAG="$(cat "$PYTHON_TAG_FILE")"

if [ "$CURRENT_PYTHON_TAG" != "$INSTALLED_PYTHON_TAG" ]; then
  echo "The system Python has changed." >&2
  echo "Installed for: $INSTALLED_PYTHON_TAG" >&2
  echo "Current Python:     $CURRENT_PYTHON_TAG" >&2
  echo "Run ./install.sh again." >&2
  exit 78
fi

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

export PYTHONPATH="$PYTHON_DIR${PYTHONPATH:+:$PYTHONPATH}"

exec "$PYTHON" -m uvicorn backend.app.entry:app \
  --host 0.0.0.0 \
  --port 8000 \
  --timeout-graceful-shutdown 2
