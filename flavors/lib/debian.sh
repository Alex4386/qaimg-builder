#!/bin/bash

set -euo pipefail

DEBIAN_FLAVOR_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$DEBIAN_FLAVOR_LIB_DIR/common.sh"

build_debian_flavor() {
    local caller_script="${BASH_SOURCE[1]}"
    local flavor_dir flavor project_root caller_dir codename
    local output_dir output_image base_image working_image customize_script

    flavor_dir="$(cd "$(dirname "$caller_script")" && pwd)"
    flavor="$(basename "$flavor_dir")"
    project_root="$(cd "$flavor_dir/../../.." && pwd)"
    caller_dir="$PWD"

    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        cat <<EOF
Build the Debian $flavor flavor.

Usage:
  $caller_script [CODENAME]

CODENAME defaults to bookworm.

Optional environment variables:
  BASE_IMAGE=/path/base.qcow2   Reuse an existing Debian QA image
  OUTPUT_DIR=/path/output       Directory for the completed image
  OUTPUT_IMAGE=/path/name       Explicit completed-image path
  OVERWRITE=1                   Replace an existing output image
  KEEP_WORKDIR=1                Preserve temporary build files
EOF
        return 0
    fi

    if [[ "$#" -gt 1 ]]; then
        flavor_die "Expected at most one Debian codename"
    fi

    codename="${1:-bookworm}"
    case "$codename" in
        trixie|bookworm|bullseye|buster|stretch|jessie) ;;
        *) flavor_die "Unsupported Debian codename: $codename" ;;
    esac

    customize_script="$(cat)"
    [[ -n "$customize_script" ]] || flavor_die "Flavor provisioning script is empty"

    for command_name in mktemp cp mv mkdir dirname basename cat; do
        flavor_require_command "$command_name"
    done

    output_dir="$(flavor_absolute_path "${OUTPUT_DIR:-.}" "$caller_dir")"
    output_image="${OUTPUT_IMAGE:-$output_dir/${codename}-generic-amd64-qa.${flavor}.qcow2}"
    output_image="$(flavor_absolute_path "$output_image" "$caller_dir")"

    base_image="${BASE_IMAGE:-}"
    if [[ -n "$base_image" ]]; then
        base_image="$(flavor_absolute_path "$base_image" "$caller_dir")"
    fi

    flavor_create_workdir debian "$flavor"
    trap flavor_cleanup_workdir EXIT

    if [[ -z "$base_image" ]]; then
        flavor_log "Building the Debian $codename QA base image"
        (
            cd "$FLAVOR_WORK_DIR"
            "$project_root/builders/debian.sh" "$codename"
        )
        base_image="$FLAVOR_WORK_DIR/${codename}-generic-amd64-qa.qcow2"
    fi

    working_image="$FLAVOR_WORK_DIR/${codename}-generic-amd64-qa.${flavor}.qcow2"
    flavor_prepare_output "$base_image" "$working_image" "$output_image"
    flavor_ensure_qimi "$project_root"
    flavor_exec_in_image "$working_image" "${NAMESERVER:-1.1.1.1}" "$customize_script"
    flavor_publish_image "$working_image" "$output_image"
}
