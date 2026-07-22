#!/bin/bash

# Simple script to download Debian cloud image and install qemu-guest-agent using qimi

set -e

# Source qimi installer
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/install-qimi.sh"
source "$SCRIPT_DIR/../common/resize-image.sh"

# Grow the working image before running apt update/upgrade + installs, which
# need more room than the ~2-3 GiB the upstream cloud image ships. Operator can
# override or disable with IMAGE_RESIZE=0.
IMAGE_MIN_DISK_GB="${IMAGE_MIN_DISK_GB:-8}"

# Get codename from first argument, default to bookworm
CODENAME="${1:-bookworm}"

# if $2 is nobuild, don't build
NOBUILD=false
if [[ "$2" == "nobuild" ]]; then
    NOBUILD=true
fi

# Map codename to version number
case "$CODENAME" in
    "trixie") VERSION="13" ;;
    "bookworm") VERSION="12" ;;
    "bullseye") VERSION="11" ;;
    "buster") VERSION="10" ;;
    "stretch") VERSION="9" ;;
    "jessie") VERSION="8" ;;
    *) 
        echo "Error: Unknown Debian codename '$CODENAME'"
        echo "Supported: trixie (13), bookworm (12), bullseye (11), buster (10), stretch (9), jessie (8)"
        exit 1
        ;;
esac

# Configuration
DEBIAN_URL="${MIRROR:-https://cloud.debian.org/images/cloud}/$CODENAME/latest/debian-$VERSION-generic-amd64.qcow2"
IMAGE_NAME="$CODENAME-generic-amd64.qcow2"
OUTPUT_NAME="$CODENAME-generic-amd64-qa.qcow2"

echo "Setting up Debian $CODENAME cloud image with qemu-guest-agent using qimi..."

# Download Debian cloud image if it doesn't exist
if [[ ! -f "$IMAGE_NAME" ]]; then
    echo "Downloading Debian $CODENAME cloud image..."
    wget -O "$IMAGE_NAME" "$DEBIAN_URL"
else
    echo "Using existing $IMAGE_NAME"
fi

# nobuild
if [ "$NOBUILD" == "true" ]; then
    echo "Skipping build for Debian"
    exit 0
fi

# Create working copy
echo "Creating working copy..."
cp "$IMAGE_NAME" "temp_$OUTPUT_NAME"

# Grow the disk so the update/install below has headroom.
resize_qcow2_image "temp_$OUTPUT_NAME" "$IMAGE_MIN_DISK_GB"

# Install qemu-guest-agent using qimi (temporary mount)
echo "Installing qemu-guest-agent..."
sudo "$QIMI_PATH" exec "temp_$OUTPUT_NAME" --nameserver 1.1.1.1 -- /bin/bash -c "
    apt-get update
    apt-get install -y qemu-guest-agent
    systemctl enable qemu-guest-agent
"

# Move to final name
mv "temp_$OUTPUT_NAME" "$OUTPUT_NAME"

echo "Done! Modified image saved as: $OUTPUT_NAME"