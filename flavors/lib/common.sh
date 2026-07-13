#!/bin/bash

# Shared helpers for application-flavored image builders.

flavor_log() {
    printf '[flavor] %s\n' "$*"
}

flavor_die() {
    printf '[flavor] Error: %s\n' "$*" >&2
    exit 1
}

flavor_require_command() {
    command -v "$1" >/dev/null 2>&1 || flavor_die "Required command not found: $1"
}

flavor_absolute_path() {
    local path="$1"
    local base_dir="$2"

    if [[ "$path" = /* ]]; then
        printf '%s\n' "$path"
    else
        printf '%s/%s\n' "$base_dir" "$path"
    fi
}

flavor_create_workdir() {
    local distro="$1"
    local flavor="$2"

    FLAVOR_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/qaimg-${distro}-${flavor}.XXXXXX")"
    : > "$FLAVOR_WORK_DIR/.qaimg-flavor-workdir"
    export FLAVOR_WORK_DIR
}

flavor_cleanup_workdir() {
    if [[ -z "${FLAVOR_WORK_DIR:-}" || ! -f "$FLAVOR_WORK_DIR/.qaimg-flavor-workdir" ]]; then
        return 0
    fi

    if [[ "${KEEP_WORKDIR:-0}" == "1" ]]; then
        flavor_log "Keeping work directory: $FLAVOR_WORK_DIR"
        return 0
    fi

    rm -rf "$FLAVOR_WORK_DIR"
}

flavor_prepare_output() {
    local base_image="$1"
    local working_image="$2"
    local output_image="$3"

    [[ -f "$base_image" ]] || flavor_die "Base image does not exist: $base_image"

    if [[ -e "$output_image" && "${OVERWRITE:-0}" != "1" ]]; then
        flavor_die "Output already exists: $output_image (set OVERWRITE=1 to replace it)"
    fi

    mkdir -p "$(dirname "$output_image")"
    flavor_log "Creating working image from $base_image"
    cp "$base_image" "$working_image"
}

flavor_ensure_qimi() {
    local project_root="$1"
    local SCRIPT_DIR PROJECT_ROOT

    if [[ -n "${QIMI_PATH:-}" ]]; then
        [[ -x "$QIMI_PATH" ]] || flavor_die "QIMI_PATH is not executable: $QIMI_PATH"
        return 0
    fi

    # Protect the caller's SCRIPT_DIR and PROJECT_ROOT from the sourced installer.
    # shellcheck source=../../common/install-qimi.sh
    source "$project_root/common/install-qimi.sh"
    [[ -x "${QIMI_PATH:-}" ]] || flavor_die "Unable to locate or install qimi"
}

flavor_exec_in_image() {
    local image="$1"
    local nameserver="$2"
    local script="$3"
    local sudo_mode="${QIMI_USE_SUDO:-auto}"
    local use_sudo=0

    case "$sudo_mode" in
        auto)
            if [[ "$EUID" -ne 0 ]]; then
                flavor_require_command sudo
                use_sudo=1
            fi
            ;;
        1|true|yes)
            flavor_require_command sudo
            use_sudo=1
            ;;
        0|false|no)
            ;;
        *)
            flavor_die "QIMI_USE_SUDO must be auto, 1, or 0"
            ;;
    esac

    flavor_log "Customizing image with qimi"
    if [[ "$use_sudo" == "1" ]]; then
        sudo "$QIMI_PATH" exec "$image" \
            --nameserver "$nameserver" -- /bin/bash -c "$script"
    else
        "$QIMI_PATH" exec "$image" \
            --nameserver "$nameserver" -- /bin/bash -c "$script"
    fi
}

flavor_publish_image() {
    local working_image="$1"
    local output_image="$2"

    if [[ -e "$output_image" ]]; then
        rm -f "$output_image"
    fi

    mv "$working_image" "$output_image"
    flavor_log "Image written to $output_image"
}
