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

# Paths for the generic first-boot provisioning mechanism.
FLAVOR_INITIAL_PROVISION_STATE_DIR=/var/lib/initial-provision
FLAVOR_INITIAL_PROVISION_HOME_TEMPLATE=/usr/local/cloud-init/home-template
FLAVOR_INITIAL_PROVISION_DROPIN_DIR=/usr/local/lib/initial-provision.d

flavor_initial_provision_base_snippet() {
    # Emit provisioning-script text that installs a generic first-boot runner.
    #
    # At build time the cloud-init login user does not exist, so anything that
    # depends on it must run on the booted instance. This installs a oneshot
    # `initial-provision.service` (ordered After=cloud-final.service) that:
    #   1. resolves the login user cloud-init created,
    #   2. copies /usr/local/cloud-init/home-template into that user's home,
    #   3. runs executable drop-ins in /usr/local/lib/initial-provision.d/*.sh,
    #      passing the login user as $1 and exporting LOGIN_USER,
    # then marks itself done so it runs only once.
    cat <<'EOF'
install -d /usr/local/sbin /usr/local/lib/initial-provision.d \
    /usr/local/cloud-init/home-template

cat > /usr/local/sbin/initial-provision <<'RUNNER'
#!/bin/bash
set -e
STATE_DIR=/var/lib/initial-provision
HOME_TEMPLATE=/usr/local/cloud-init/home-template
DROPIN_DIR=/usr/local/lib/initial-provision.d

login_user=""
if [ -f /etc/sudoers.d/90-cloud-init-users ]; then
    login_user="$(grep -hoE '^[a-z_][a-z0-9_-]*' /etc/sudoers.d/90-cloud-init-users | head -n1)"
fi
if [ -z "$login_user" ]; then
    login_user="$(getent passwd 1000 | cut -d: -f1)"
fi
export LOGIN_USER="$login_user"

if [ -n "$login_user" ] && id -u "$login_user" >/dev/null 2>&1; then
    login_home="$(getent passwd "$login_user" | cut -d: -f6)"
    login_group="$(id -gn "$login_user")"
    if [ -d "$HOME_TEMPLATE" ] && [ -n "$login_home" ] && [ -d "$login_home" ]; then
        if [ -n "$(ls -A "$HOME_TEMPLATE" 2>/dev/null)" ]; then
            cp -a "$HOME_TEMPLATE/." "$login_home/"
            chown -R "$login_user:$login_group" "$login_home"
        fi
    fi
fi

if [ -d "$DROPIN_DIR" ]; then
    for dropin in "$DROPIN_DIR"/*.sh; do
        [ -x "$dropin" ] || continue
        "$dropin" "$login_user"
    done
fi

mkdir -p "$STATE_DIR"
: > "$STATE_DIR/.done"
RUNNER
chmod 0755 /usr/local/sbin/initial-provision

cat > /etc/systemd/system/initial-provision.service <<'UNIT'
[Unit]
Description=First-boot provisioning (after cloud-init)
After=cloud-final.service
Wants=cloud-final.service
ConditionPathExists=!/var/lib/initial-provision/.done

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/initial-provision

[Install]
WantedBy=multi-user.target
UNIT

systemctl enable initial-provision.service
EOF
}

flavor_initial_provision_group_dropin() {
    # Emit a drop-in that adds the resolved login user to the given group at
    # first boot. Requires flavor_initial_provision_base_snippet.
    local group="$1"
    local priority="${2:-20}"

    printf 'DROPIN_GROUP=%s\n' "$group"
    printf 'DROPIN_PRIORITY=%s\n' "$priority"

    cat <<'EOF'
cat > "/usr/local/lib/initial-provision.d/${DROPIN_PRIORITY}-group-${DROPIN_GROUP}.sh" <<DROPIN
#!/bin/bash
set -e
login_user="\$1"
group=${DROPIN_GROUP}
if [ -n "\$login_user" ] && id -u "\$login_user" >/dev/null 2>&1; then
    usermod -aG "\$group" "\$login_user"
fi
DROPIN
chmod 0755 "/usr/local/lib/initial-provision.d/${DROPIN_PRIORITY}-group-${DROPIN_GROUP}.sh"
EOF
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
