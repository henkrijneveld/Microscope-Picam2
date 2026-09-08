#!/usr/bin/env bash
set -euo pipefail

timestamp="${1:?Gebruik: $0 YYMMDD-HHMMSS}"

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

if ! command -v exiftool >/dev/null 2>&1; then
    echo "exiftool ontbreekt." >&2
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
# Geen Python nodig: ExifTool leest UserComment en Bash haalt het FOV-object eruit.
user_comment="$(exiftool -s3 -EXIF:UserComment "$aeb0")"

if [[ $user_comment =~ \"FOV\":(\{[^}]*\}) ]]; then
    fov_object="${BASH_REMATCH[1]}"
else
    echo "AEB-0 bevat geen FOV metadata" >&2
    exit 1
fi

fov_json="{\"microscope_picam2\":{\"FOV\":${fov_object}}}"

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
