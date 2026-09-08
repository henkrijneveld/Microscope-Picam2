#!/usr/bin/env bash
set -euo pipefail

timestamp="${1:?Gebruik: $0 YYMMDD-HHMMSS}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON="$SCRIPT_DIR/.venv/bin/python"

shopt -s nullglob
inputs=( "${timestamp}-"*-AEB-*.jpg )

if [ "${#inputs[@]}" -eq 0 ]; then
    echo "Geen AEB-bestanden gevonden voor timestamp: ${timestamp}" >&2
    exit 1
fi

base="${inputs[0]%-AEB-*}"

# Controleer dat alle gevonden opnamen bij dezelfde AEB-serie horen.
for input in "${inputs[@]}"; do
    input_base="${input%-AEB-*}"
    if [ "$input_base" != "$base" ]; then
        echo "Meerdere AEB-series gevonden voor timestamp ${timestamp}:" >&2
        printf '  %s\n' "${inputs[@]}" >&2
        exit 1
    fi
done

aeb0="${base}-AEB-0.jpg"
if [ ! -f "$aeb0" ]; then
    echo "AEB-0 ontbreekt: $aeb0" >&2
    exit 1
fi

if [ ! -x "$PYTHON" ]; then
    echo "Python uit project-venv niet gevonden: $PYTHON" >&2
    exit 1
fi

if ! command -v exiftool >/dev/null 2>&1; then
    echo "exiftool ontbreekt. Installeer met: sudo apt install libimage-exiftool-perl" >&2
    exit 1
fi

tif="${base}.tif"
jpg="${base}.jpg"
contrast="${base}-contrast.jpg"

# Exposure fusion (Mertens/enfuse) naar TIFF als hoogwaardige tussenstap.
enfuse -o "$tif" "${inputs[@]}"

# Gewone JPEG-versie van hetzelfde resultaat.
convert "$tif" "$jpg"

# Contrast-stretch op de TIFF; ImageMagick 6 gebruikt het commando 'convert'.
convert "$tif" -contrast-stretch 0.3%x0.3% "$contrast"

# Neem alleen de FOV uit de EXIF UserComment-JSON van AEB-0 over.
fov_json="$($PYTHON - "$aeb0" <<'PY'
import json
import sys

import piexif
import piexif.helper

source = sys.argv[1]
exif = piexif.load(source)
user_comment = exif.get("Exif", {}).get(piexif.ExifIFD.UserComment)

if not user_comment:
    raise SystemExit("AEB-0 bevat geen EXIF UserComment")

metadata = json.loads(piexif.helper.UserComment.load(user_comment))
fov = metadata.get("microscope_picam2", {}).get("FOV")

if not fov:
    raise SystemExit("AEB-0 bevat geen FOV metadata")

print(json.dumps(
    {"microscope_picam2": {"FOV": fov}},
    ensure_ascii=False,
    separators=(",", ":"),
))
PY
)"

exiftool -overwrite_original \
    "-EXIF:UserComment=$fov_json" \
    "$jpg" "$tif" "$contrast" >/dev/null

echo "Gemaakt:"
echo "  $jpg"
echo "  $tif"
echo "  $contrast"
echo "FOV metadata overgenomen uit: $aeb0"

# install enfuse with: sudo apt install enfuse
# install ImageMagick 6 with: sudo apt install imagemagick
# install ExifTool with: sudo apt install libimage-exiftool-perl
