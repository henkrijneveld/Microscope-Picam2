#!/usr/bin/env bash
set -euo pipefail

timestamp="${1:?Usage: $0 YYMMDD-HHMMSS}"
focus_dir="${timestamp}-focusstack"

shopt -s nullglob

aeb_inputs=( "${timestamp}-"*-AEB-*.jpg )
single_inputs=( "${timestamp}-"*.jpg )

if [ "${#aeb_inputs[@]}" -eq 0 ] && [ "${#single_inputs[@]}" -eq 0 ]; then
    echo "No files found for timestamp: ${timestamp}" >&2
    exit 1
fi

# Parse a base name of the form:
#   YYMMDD-HHMMSS-<stack-number>-<name>
#
# Set STACK_NUMBER and STACK_REST when this is actually a stack name.
parse_stack_base() {
    local base="$1"
    local prefix="${timestamp}-"
    local remainder
    local number
    local rest

    STACK_NUMBER=""
    STACK_REST=""

    case "$base" in
        "$prefix"*) ;;
        *) return 1 ;;
    esac

    remainder="${base#"$prefix"}"

    case "$remainder" in
        *-*) ;;
        *) return 1 ;;
    esac

    number="${remainder%%-*}"
    rest="${remainder#*-}"

    case "$number" in
        ''|*[!0-9]*) return 1 ;;
    esac

    [ -n "$rest" ] || return 1

    STACK_NUMBER="$number"
    STACK_REST="$rest"
    return 0
}

prepare_focus_dir() {
    mkdir -p "$focus_dir"
    rm -f -- "$focus_dir"/*.tif "$focus_dir"/*.jpg
}

show_install_hint() {
    local package="$1"

    echo "Install with:" >&2
    echo "  sudo apt update" >&2
    echo "  sudo apt install $package" >&2
}

filter_enfuse_output() {
    sed -E \
        -e '/: info: input image .* does not have an alpha channel;$/d' \
        -e '/: note: assuming all pixels should contribute to the final image$/d' \
        -e '/: warning: no usable resolution found in first image .*;$/d' \
        -e '/: note: Enfuse will assume [0-9]+ dpi$/d'
}

copy_stack_item() {
    local source="$1"
    local base="$2"
    local extension="$3"
    local padded

    if ! parse_stack_base "$base"; then
        echo "Internal error: not a stack name: $base" >&2
        return 1
    fi

    printf -v padded '%04d' "$((10#$STACK_NUMBER))"
    cp -f -- "$source" "$focus_dir/${padded}-${STACK_REST}.${extension}"
    echo "  -> $focus_dir/${padded}-${STACK_REST}.${extension}"
}

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
        echo "No AEB files found for series: $base" >&2
        return 1
    fi

    if [ ! -f "$aeb0" ]; then
        echo "AEB-0 is missing: $aeb0" >&2
        return 1
    fi

    # enfuse -o "$tif" "${inputs[@]}"

    # google AI recommendation: not the layer but the contrast
    # for microscop it also advicews the --hard-mask flag. But it seems not OK for me
    enfuse --verbose=1 --exposure-weight=0.3 --contrast-weight=1.0 --saturation-weight=0.5 --contrast-window-size=5 -o "$tif" "${inputs[@]}" \
        2> >(filter_enfuse_output >&2)

    "$IMAGEMAGICK" "$tif" "$jpg"
    "$IMAGEMAGICK" "$tif" -contrast-stretch 0.2%x0.2% "$contrast"

    # Metadata is useful, but must never block image processing or the focus stack.
    # Older captures, for example, may not contain FOV metadata yet.
    user_comment="$(exiftool -s3 -EXIF:UserComment "$aeb0" 2>/dev/null || true)"

    if [[ $user_comment =~ \"FOV\":(\{[^}]*\}) ]]; then
        fov_object="${BASH_REMATCH[1]}"
        fov_json="{\"microscope_picam2\":{\"FOV\":${fov_object}}}"

        if ! exiftool -overwrite_original \
            "-EXIF:UserComment=$fov_json" \
            "$jpg" "$tif" "$contrast" >/dev/null 2>&1; then
            echo "Warning: FOV metadata could not be copied for $base" >&2
        fi
    fi

    echo "Created:"
    echo "  $jpg"
    echo "  $tif"
    echo "  $contrast"
}

if [ "${#aeb_inputs[@]}" -gt 0 ]; then
    if ! command -v enfuse >/dev/null 2>&1; then
        echo "enfuse is missing." >&2
        show_install_hint "enfuse"
        exit 1
    fi

    if ! command -v magick >/dev/null 2>&1; then
        echo "ImageMagick 7 ('magick') is missing." >&2
        show_install_hint "imagemagick"
        exit 1
    fi
    IMAGEMAGICK="magick"

    if ! command -v exiftool >/dev/null 2>&1; then
        echo "exiftool is missing." >&2
        show_install_hint "libimage-exiftool-perl"
        exit 1
    fi

    # Derive the unique series from all AEB files. No dependency
    # on the exact name of one specific bracket.
    series_bases=()
    for input in "${aeb_inputs[@]}"; do
        base="${input%-AEB-*}"
        seen=false

        for existing in "${series_bases[@]}"; do
            if [ "$existing" = "$base" ]; then
                seen=true
                break
            fi
        done

        if [ "$seen" = false ]; then
            series_bases+=( "$base" )
        fi
    done

    hdr_stack=false
    for base in "${series_bases[@]}"; do
        if parse_stack_base "$base"; then
            hdr_stack=true
            break
        fi
    done

    if [ "$hdr_stack" = true ]; then
        prepare_focus_dir
        echo "Focus stack detected: ${#series_bases[@]} HDR series"
        echo "Zerene directory: $focus_dir/"
    fi

    for base in "${series_bases[@]}"; do
        process_series "$base"

        if [ "$hdr_stack" = true ] && parse_stack_base "$base"; then
            copy_stack_item "${base}.tif" "$base" "tif"
        fi
    done

    if [ "$hdr_stack" = true ]; then
        echo "Focus stack for Zerene Stacker ready:"
        echo "  $focus_dir/  (TIFF, HDR/Mertens)"
    fi
else
    stack_jpgs=()

    for input in "${single_inputs[@]}"; do
        case "$input" in
            *-contrast.jpg|*-AEB-*) continue ;;
        esac

        base="${input%.jpg}"
        if parse_stack_base "$base"; then
            stack_jpgs+=( "$input" )
        fi
    done

    if [ "${#stack_jpgs[@]}" -eq 0 ]; then
        echo "No focus stack found for timestamp: ${timestamp}" >&2
        exit 1
    fi

    prepare_focus_dir

    for jpg in "${stack_jpgs[@]}"; do
        base="${jpg%.jpg}"
        copy_stack_item "$jpg" "$base" "jpg"
    done

    echo "Focus stack for Zerene Stacker ready:"
    echo "  $focus_dir/  (JPEG, single captures)"
fi

# Dependencies:
#   sudo apt update
#   sudo apt install enfuse imagemagick libimage-exiftool-perl
