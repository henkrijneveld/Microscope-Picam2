#!/usr/bin/env bash
set -euo pipefail

name="${1:?Gebruik: $0 <bestandsnaam-zonder-jpg>}"

shopt -s nullglob
inputs=( "${name}-AEB-"*.jpg )

if [ "${#inputs[@]}" -eq 0 ]; then
    echo "Geen AEB-bestanden gevonden voor: ${name}-AEB-*.jpg" >&2
    exit 1
fi

enfuse -o "${name}.jpg" "${inputs[@]}"

# install enfuse with: sudo apt install enfuse