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

tif="${base}.tif"
jpg="${base}.jpg"
contrast="${base}-contrast.jpg"

# Exposure fusion (Mertens/enfuse) naar TIFF als hoogwaardige tussenstap.
enfuse -o "$tif" "${inputs[@]}"

# Gewone JPEG-versie van hetzelfde resultaat.
convert "$tif" "$jpg"

# Contrast-stretch op de TIFF; ImageMagick 6 gebruikt het commando 'convert'.
convert "$tif" -contrast-stretch 0.3%x0.3% "$contrast"

echo "Gemaakt:"
echo "  $jpg"
echo "  $tif"
echo "  $contrast"

# install enfuse with: sudo apt install enfuse
# install ImageMagick 6 with: sudo apt install imagemagick
