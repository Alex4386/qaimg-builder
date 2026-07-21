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

# Paths for the preconfigured-credentials mechanism.
FLAVOR_CRED_DEPLOY_FILE=/etc/qaimg/credentials
FLAVOR_CRED_DEFAULT_FILE=/usr/local/share/qaimg/credentials.default
FLAVOR_CRED_GENERATED_FILE=/etc/qaimg/credentials.generated
FLAVOR_CRED_LIB=/usr/local/lib/qaimg-credentials.sh

flavor_credentials_base_snippet() {
    # Emit provisioning text that installs a small on-image credentials library.
    #
    # Credentials are resolved at FIRST BOOT with this precedence:
    #   1. deploy-time  /etc/qaimg/credentials              (cloud-init write_files / vendor.yaml)
    #   2. build-time   /usr/local/share/qaimg/credentials.default (baked fallback, optional)
    #   3. random       generated and persisted to /etc/qaimg/credentials.generated
    #
    # Files are flat KEY=VALUE (optionally quoted). Drop-ins source
    # /usr/local/lib/qaimg-credentials.sh and call qaimg_cred / qaimg_cred_or_random.
    cat <<'EOF'
install -d -m 0755 /usr/local/lib /usr/local/share/qaimg
install -d -m 0700 /etc/qaimg
cat > /usr/local/lib/qaimg-credentials.sh <<'CREDLIB'
#!/bin/bash
# qaimg preconfigured-credentials helper. Source this file.
QAIMG_CRED_DEPLOY=/etc/qaimg/credentials
QAIMG_CRED_DEFAULT=/usr/local/share/qaimg/credentials.default
QAIMG_CRED_GENERATED=/etc/qaimg/credentials.generated

_qaimg_read() {
    local file="$1" key="$2" line val
    [ -f "$file" ] || return 1
    line="$(grep -E "^[[:space:]]*${key}=" "$file" 2>/dev/null | tail -n1)"
    [ -n "$line" ] || return 1
    val="${line#*=}"
    val="${val%\"}"; val="${val#\"}"
    val="${val%\'}"; val="${val#\'}"
    printf '%s' "$val"
}

qaimg_cred() {
    local key="$1" v
    for f in "$QAIMG_CRED_DEPLOY" "$QAIMG_CRED_DEFAULT" "$QAIMG_CRED_GENERATED"; do
        v="$(_qaimg_read "$f" "$key")" && [ -n "$v" ] && { printf '%s' "$v"; return 0; }
    done
    return 1
}

qaimg_cred_or_random() {
    local key="$1" bytes="${2:-24}" v
    if v="$(qaimg_cred "$key")" && [ -n "$v" ]; then
        printf '%s' "$v"; return 0
    fi
    v="$(openssl rand -hex "$bytes")"
    ( umask 077; mkdir -p /etc/qaimg
      if [ -f "$QAIMG_CRED_GENERATED" ] && grep -qE "^${key}=" "$QAIMG_CRED_GENERATED"; then
          sed -i -E "s|^${key}=.*|${key}=${v}|" "$QAIMG_CRED_GENERATED"
      else
          printf '%s=%s\n' "$key" "$v" >> "$QAIMG_CRED_GENERATED"
      fi
      chmod 0600 "$QAIMG_CRED_GENERATED" )
    printf '%s' "$v"
}
CREDLIB
chmod 0644 /usr/local/lib/qaimg-credentials.sh
EOF
}

flavor_sudo_prefix() {
    # Echo "sudo" when elevation is needed, per QIMI_USE_SUDO (default auto).
    local mode="${QIMI_USE_SUDO:-auto}"
    case "$mode" in
        auto) [[ "$EUID" -ne 0 ]] && { flavor_require_command sudo; echo sudo; } ;;
        1|true|yes) flavor_require_command sudo; echo sudo ;;
        0|false|no) ;;
        *) flavor_die "QIMI_USE_SUDO must be auto, 1, or 0" ;;
    esac
}

flavor_image_virtual_bytes() {
    qemu-img info "$1" 2>/dev/null \
        | sed -n 's/.*(\([0-9][0-9]*\) bytes).*/\1/p' | head -n1
}

flavor_grow_root_filesystem() {
    # Grow the largest partition of a qcow2 and its ext filesystem to fill the
    # (already-resized) virtual disk. Host-side, via qemu-nbd. Requires root.
    local image="$1" sudo nbd i part_name part_num fsdev
    sudo="$(flavor_sudo_prefix)"
    for c in qemu-nbd partprobe growpart resize2fs e2fsck lsblk; do
        flavor_require_command "$c"
    done

    $sudo modprobe nbd 2>/dev/null || true
    nbd=""
    for i in $(seq 0 15); do
        if [[ ! -e "/sys/block/nbd$i/pid" ]]; then nbd="/dev/nbd$i"; break; fi
    done
    [[ -n "$nbd" ]] || flavor_die "No free NBD device to resize image"

    $sudo qemu-nbd --connect="$nbd" "$image" || flavor_die "qemu-nbd connect failed"
    # shellcheck disable=SC2064
    trap "$sudo qemu-nbd --disconnect '$nbd' >/dev/null 2>&1 || true" RETURN
    $sudo partprobe "$nbd" 2>/dev/null || true
    sleep 1

    # Pick the largest partition (the root fs on Debian genericcloud images).
    part_name="$(lsblk -brno NAME,SIZE "$nbd" | awk 'NR>1{print $2, $1}' \
        | sort -nr | head -n1 | awk '{print $2}')"
    [[ -n "$part_name" ]] || flavor_die "Could not find a partition to grow on $nbd"
    part_num="$(printf '%s' "$part_name" | sed 's/.*[^0-9]\([0-9][0-9]*\)$/\1/')"
    fsdev="/dev/$part_name"

    flavor_log "Growing $fsdev (partition $part_num) to fill the disk"
    $sudo growpart "$nbd" "$part_num" || flavor_log "growpart: nothing to grow"
    $sudo partprobe "$nbd" 2>/dev/null || true
    sleep 1

    # resize2fs refuses to grow an unchecked filesystem ("Please run e2fsck -f
    # first"), so force a non-interactive check. e2fsck exits 1 when it fixes
    # something (expected on an offline image) and >=2 on real errors, so only
    # treat >=2 as fatal.
    local fstype
    fstype="$(lsblk -brno FSTYPE "$fsdev" 2>/dev/null | head -n1)"
    case "$fstype" in
        ext2|ext3|ext4|"")
            $sudo e2fsck -f -p "$fsdev"
            local rc=$?
            [[ "$rc" -ge 2 ]] && flavor_die "e2fsck failed on $fsdev (rc=$rc)"
            $sudo resize2fs "$fsdev" || flavor_die "resize2fs failed on $fsdev"
            ;;
        *)
            flavor_die "Unsupported root filesystem for resize: $fstype"
            ;;
    esac
}

flavor_maybe_resize_image() {
    # Resize the working image to at least FLAVOR_MIN_DISK_GB before provisioning
    # so heavy flavors have build-time headroom. No-op when unset/0 or disabled.
    local image="$1"
    local min_gb="${FLAVOR_MIN_DISK_GB:-0}"

    [[ "$min_gb" =~ ^[0-9]+$ ]] || flavor_die "FLAVOR_MIN_DISK_GB must be an integer"
    [[ "$min_gb" -gt 0 ]] || return 0

    if [[ "${FLAVOR_RESIZE:-1}" != "1" ]]; then
        flavor_log "Resize to ${min_gb}G requested but FLAVOR_RESIZE!=1; skipping"
        return 0
    fi

    flavor_require_command qemu-img
    local cur_bytes target_bytes
    cur_bytes="$(flavor_image_virtual_bytes "$image")"
    target_bytes=$(( min_gb * 1024 * 1024 * 1024 ))
    if [[ -n "$cur_bytes" && "$cur_bytes" -ge "$target_bytes" ]]; then
        flavor_log "Image virtual size already >= ${min_gb}G; no resize needed"
        return 0
    fi

    flavor_log "Resizing working image to ${min_gb}G"
    qemu-img resize "$image" "${min_gb}G" || flavor_die "qemu-img resize failed"
    flavor_grow_root_filesystem "$image"
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
