#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat <<'EOF'
Usage:
  ./flavors/build.sh DISTRO FLAVOR [flavor arguments...]
  ./flavors/build.sh --list

Examples:
  ./flavors/build.sh debian nginx
  ./flavors/build.sh debian nginx trixie
  ./flavors/build.sh debian nodejs bookworm
  ./flavors/build.sh debian wireguard bookworm
  ./flavors/build.sh debian docker bookworm
  ./flavors/build.sh debian minecraft-vanilla bookworm
  ./flavors/build.sh debian minecraft-paper bookworm
EOF
}

list_flavors() {
    local build_script distro flavor
    shopt -s nullglob
    for build_script in "$SCRIPT_DIR"/*/*/build.sh; do
        distro="$(basename "$(dirname "$(dirname "$build_script")")")"
        flavor="$(basename "$(dirname "$build_script")")"
        printf '%s/%s\n' "$distro" "$flavor"
    done
}

if [[ "${1:-}" == "--list" ]]; then
    list_flavors
    exit 0
fi

if [[ "$#" -lt 2 || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    [[ "$#" -ge 2 ]] || exit 0
fi

DISTRO="$1"
FLAVOR="$2"
shift 2

if [[ ! "$DISTRO" =~ ^[a-z0-9][a-z0-9._-]*$ || ! "$FLAVOR" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
    printf 'Invalid distro or flavor name.\n' >&2
    exit 1
fi

BUILD_SCRIPT="$SCRIPT_DIR/$DISTRO/$FLAVOR/build.sh"
if [[ ! -x "$BUILD_SCRIPT" ]]; then
    printf 'Unknown flavor: %s/%s\n\nAvailable flavors:\n' "$DISTRO" "$FLAVOR" >&2
    list_flavors >&2
    exit 1
fi

exec "$BUILD_SCRIPT" "$@"
