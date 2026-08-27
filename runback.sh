#!/usr/bin/env bash

set -e

exec .venv/bin/uvicorn backend.app.main:app \
  --host 0.0.0.0 \
  --port 8000