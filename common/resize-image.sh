#!/bin/bash

# Shared build-host image growth for base and flavor builders.
#
# Grows a qcow2's virtual disk to at least a target size, then expands the
# largest partition and its filesystem to fill it, so build-time work (apt/dnf
# update + upgrade, package installs, downloads) has headroom. Runs host-side
# via qemu-nbd and requires root/sudo. Supports ext2/3/4 and xfs root fses.
#
# Usage (source, then call):
#   source "$PROJECT_ROOT/common/resize-image.sh"
#   resize_qcow2_image /path/to/image.qcow2 8      # grow to >= 8 GiB
#
# Environment:
#   IMAGE_RESIZE=0        Disable resizing entirely (no-op).
#   IMAGE_RESIZE_SUDO     auto (default) | 1 | 0 — whether to prefix with sudo.

resize_log() { printf '[resize] %s\n' "$*"; }
resize_die() { printf '[resize] Error: %s\n' "$*" >&2; return 1; }

resize_require_command() {
    command -v "$1" >/dev/null 2>&1 || resize_die "Required command not found: $1"
}

resize_sudo_prefix() {
    # Echo "sudo" when elevation is needed, per IMAGE_RESIZE_SUDO (default auto).
    local mode="${IMAGE_RESIZE_SUDO:-auto}"
    case "$mode" in
        auto) [[ "$EUID" -ne 0 ]] && { resize_require_command sudo && echo sudo; } ;;
        1|true|yes) resize_require_command sudo && echo sudo ;;
        0|false|no) ;;
        *) resize_die "IMAGE_RESIZE_SUDO must be auto, 1, or 0" ;;
    esac
}

resize_image_virtual_bytes() {
    qemu-img info "$1" 2>/dev/null \
        | sed -n 's/.*(\([0-9][0-9]*\) bytes).*/\1/p' | head -n1
}

resize_grow_root_filesystem() {
    # Grow the largest partition of a qcow2 and its filesystem to fill the
    # (already-resized) virtual disk. Host-side, via qemu-nbd. Requires root.
    local image="$1" sudo nbd i part_name part_num fsdev fstype rc
    sudo="$(resize_sudo_prefix)" || return 1
    for c in qemu-nbd partprobe growpart lsblk; do
        resize_require_command "$c" || return 1
    done

    $sudo modprobe nbd 2>/dev/null || true
    nbd=""
    for i in $(seq 0 15); do
        if [[ ! -e "/sys/block/nbd$i/pid" ]]; then nbd="/dev/nbd$i"; break; fi
    done
    [[ -n "$nbd" ]] || { resize_die "No free NBD device to resize image"; return 1; }

    $sudo qemu-nbd --connect="$nbd" "$image" || { resize_die "qemu-nbd connect failed"; return 1; }
    # shellcheck disable=SC2064
    trap "$sudo qemu-nbd --disconnect '$nbd' >/dev/null 2>&1 || true" RETURN
    $sudo partprobe "$nbd" 2>/dev/null || true
    sleep 1

    # Pick the largest partition (the root fs on the generic cloud images).
    part_name="$(lsblk -brno NAME,SIZE "$nbd" | awk 'NR>1{print $2, $1}' \
        | sort -nr | head -n1 | awk '{print $2}')"
    [[ -n "$part_name" ]] || { resize_die "Could not find a partition to grow on $nbd"; return 1; }
    part_num="$(printf '%s' "$part_name" | sed 's/.*[^0-9]\([0-9][0-9]*\)$/\1/')"
    fsdev="/dev/$part_name"

    resize_log "Growing $fsdev (partition $part_num) to fill the disk"
    $sudo growpart "$nbd" "$part_num" || resize_log "growpart: nothing to grow"
    $sudo partprobe "$nbd" 2>/dev/null || true
    sleep 1

    fstype="$(lsblk -brno FSTYPE "$fsdev" 2>/dev/null | head -n1)"
    case "$fstype" in
        ext2|ext3|ext4|"")
            resize_require_command resize2fs || return 1
            resize_require_command e2fsck || return 1
            # resize2fs refuses to grow an unchecked filesystem, so force a
            # non-interactive check first. e2fsck exits 1 when it fixes
            # something (expected on an offline image) and >= 4 on real errors;
            # only >= 4 is fatal. "|| rc=$?" keeps set -e from aborting on rc 1.
            rc=0
            $sudo e2fsck -f -p "$fsdev" || rc=$?
            [[ "$rc" -ge 4 ]] && { resize_die "e2fsck failed on $fsdev (rc=$rc)"; return 1; }
            $sudo resize2fs "$fsdev" || { resize_die "resize2fs failed on $fsdev"; return 1; }
            ;;
        xfs)
            # xfs_growfs works on a mounted filesystem, so mount it read-write to
            # a temporary directory, grow, then unmount. Rocky/Alma cloud images
            # use xfs for the root partition.
            resize_require_command xfs_growfs || return 1
            resize_require_command mount || return 1
            local mnt
            mnt="$(mktemp -d "${TMPDIR:-/tmp}/qaimg-xfs.XXXXXX")"
            if $sudo mount -t xfs "$fsdev" "$mnt" 2>/dev/null; then
                $sudo xfs_growfs "$mnt" || { $sudo umount "$mnt"; rmdir "$mnt"; resize_die "xfs_growfs failed on $fsdev"; return 1; }
                $sudo umount "$mnt"
            else
                rmdir "$mnt"
                resize_die "Could not mount xfs $fsdev to grow it"
                return 1
            fi
            rmdir "$mnt" 2>/dev/null || true
            ;;
        btrfs)
            # btrfs grows online, so mount it and resize the root subvolume to
            # max. Arch Linux cloud images use btrfs for the root partition.
            resize_require_command btrfs || return 1
            resize_require_command mount || return 1
            local mnt
            mnt="$(mktemp -d "${TMPDIR:-/tmp}/qaimg-btrfs.XXXXXX")"
            if $sudo mount -t btrfs "$fsdev" "$mnt" 2>/dev/null; then
                $sudo btrfs filesystem resize max "$mnt" || { $sudo umount "$mnt"; rmdir "$mnt"; resize_die "btrfs resize failed on $fsdev"; return 1; }
                $sudo umount "$mnt"
            else
                rmdir "$mnt"
                resize_die "Could not mount btrfs $fsdev to grow it"
                return 1
            fi
            rmdir "$mnt" 2>/dev/null || true
            ;;
        *)
            resize_die "Unsupported root filesystem for resize: $fstype"
            return 1
            ;;
    esac
}

resize_qcow2_image() {
    # Grow $1 to at least $2 GiB (virtual), then expand its root filesystem.
    # No-op when the target is unset/0, IMAGE_RESIZE=0, or the image is already
    # big enough.
    local image="$1"
    local min_gb="${2:-0}"

    [[ -f "$image" ]] || { resize_die "Image does not exist: $image"; return 1; }
    [[ "$min_gb" =~ ^[0-9]+$ ]] || { resize_die "Target size must be an integer number of GiB"; return 1; }
    [[ "$min_gb" -gt 0 ]] || return 0

    if [[ "${IMAGE_RESIZE:-1}" != "1" ]]; then
        resize_log "Resize to ${min_gb}G requested but IMAGE_RESIZE!=1; skipping"
        return 0
    fi

    resize_require_command qemu-img || return 1
    local cur_bytes target_bytes
    cur_bytes="$(resize_image_virtual_bytes "$image")"
    target_bytes=$(( min_gb * 1024 * 1024 * 1024 ))
    if [[ -n "$cur_bytes" && "$cur_bytes" -ge "$target_bytes" ]]; then
        resize_log "Image virtual size already >= ${min_gb}G; no resize needed"
        return 0
    fi

    resize_log "Resizing working image to ${min_gb}G"
    qemu-img resize "$image" "${min_gb}G" || { resize_die "qemu-img resize failed"; return 1; }
    resize_grow_root_filesystem "$image"
}
