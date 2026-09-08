#!/usr/bin/env bash
set -euo pipefail

timestamp="${1:?Gebruik: $0 YYMMDD-HHMMSS}"

shopt -s nullglob
all_inputs=( "${timestamp}-"*-AEB-*.jpg )

if [ "${#all_inputs[@]}" -eq 0 ]; then
    echo "Geen AEB-bestanden gevonden voor timestamp: ${timestamp}" >&2
    exit 1
fi

if ! command -v exiftool >/dev/null 2>&1; then
    echo "exiftool ontbreekt." >&2
    exit 1
fi

process_series() {
    local base="$1"
    local inputs=( "${base}-AEB-"*.jpg )
    local aeb0="${base}-AEB-0.jpg"
    local tif="${base}.tif"
    local jpg="${base}.jpg"
    local contrast="${base}-contrast.jpg"
    local user_comment
    local fov_object
    local fov_json

    if [ "${#inputs[@]}" -eq 0 ]; then
        echo "Geen AEB-bestanden gevonden voor serie: $base" >&2
        return 1
    fi

    if [ ! -f "$aeb0" ]; then
        echo "AEB-0 ontbreekt: $aeb0" >&2
        return 1
    fi

    echo "Verwerk serie: $base"

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
        echo "AEB-0 bevat geen FOV metadata: $aeb0" >&2
        return 1
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
}

# Verzamel iedere unieke AEB-serie onder deze timestamp.
# Daardoor worden stacks zoals:
#   YYMMDD-HHMMSS-1-naam-AEB-*.jpg
#   YYMMDD-HHMMSS-2-naam-AEB-*.jpg
# onafhankelijk van elkaar verwerkt.
declare -A series=()
for input in "${all_inputs[@]}"; do
    base="${input%-AEB-*}"
    series["$base"]=1
done

for base in "${!series[@]}"; do
    process_series "$base"
done

# install enfuse with: sudo apt install enfuse
# install ImageMagick 6 with: sudo apt install imagemagick
# install ExifTool with: sudo apt install libimage-exiftool-perl
