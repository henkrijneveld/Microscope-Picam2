#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_ROOT="$ROOT_DIR/dist"
DIST_DIR="$DIST_ROOT/MicroRasp"
ZIP_FILE="$DIST_ROOT/MicroRasp.zip"

cd "$ROOT_DIR"

if ! command -v npm >/dev/null 2>&1; then
  echo "npm is missing on the development machine." >&2
  exit 1
fi

if ! command -v zip >/dev/null 2>&1; then
  echo "zip is missing on the development machine." >&2
  exit 1
fi

echo "Building frontend..."
npm --prefix frontend run build

echo "Rebuilding distribution directory..."
rm -rf "$DIST_DIR"
mkdir -p \
  "$DIST_DIR/backend" \
  "$DIST_DIR/frontend/dist" \
  "$DIST_DIR/python" \
  "$DIST_DIR/photos" \
  "$DIST_DIR/resources"

cp -a backend/. "$DIST_DIR/backend/"
cp -a frontend/dist/. "$DIST_DIR/frontend/dist/"

cp release/install.sh "$DIST_DIR/install.sh"
cp release/uninstall.sh "$DIST_DIR/uninstall.sh"
cp release/check-installation.sh "$DIST_DIR/check-installation.sh"
cp release/run.sh "$DIST_DIR/run.sh"
cp release/start.sh "$DIST_DIR/start.sh"
cp release/stop.sh "$DIST_DIR/stop.sh"
cp release/enable-autostart.sh "$DIST_DIR/enable-autostart.sh"
cp release/disable-autostart.sh "$DIST_DIR/disable-autostart.sh"
cp release/requirements.txt "$DIST_DIR/requirements.txt"
cp release/.env.local.example "$DIST_DIR/.env.local.example"
cp LICENSE "$DIST_DIR/LICENSE"

cp release/resources/mertens.sh "$DIST_DIR/resources/mertens.sh"
cp release/resources/mertens.sh "$DIST_DIR/photos/mertens.sh"

find "$DIST_DIR/backend" -type d -name '__pycache__' -prune -exec rm -rf {} +
find "$DIST_DIR/backend" -type f -name '*.py[co]' -delete

touch "$DIST_DIR/python/.gitkeep"

chmod +x \
  "$DIST_DIR/install.sh" \
  "$DIST_DIR/uninstall.sh" \
  "$DIST_DIR/check-installation.sh" \
  "$DIST_DIR/run.sh" \
  "$DIST_DIR/start.sh" \
  "$DIST_DIR/stop.sh" \
  "$DIST_DIR/enable-autostart.sh" \
  "$DIST_DIR/disable-autostart.sh"

chmod 0555 \
  "$DIST_DIR/resources/mertens.sh" \
  "$DIST_DIR/photos/mertens.sh"

echo "Creating ZIP..."
rm -f "$ZIP_FILE"
(
  cd "$DIST_ROOT"
  zip -qr "MicroRasp.zip" "MicroRasp" \
    -x "MicroRasp/python/.python-tag" \
       "MicroRasp/python/*.pyc" \
       "MicroRasp/photos/*.jpg" \
       "MicroRasp/photos/*.jpeg" \
       "MicroRasp/photos/*.png" \
       "MicroRasp/photos/*.tif" \
       "MicroRasp/photos/*.tiff"
)

echo
echo "Distribution ready:"
echo "  $DIST_DIR"
echo "  $ZIP_FILE"
echo
echo "The directory and ZIP are generated locally and ignored by Git."
echo "Upload MicroRasp.zip as a GitHub Release asset."
