#!/bin/bash

# Simple script to download Ubuntu cloud image and install qemu-guest-agent using qimi

set -e

# Source qimi installer
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/install-qimi.sh"
source "$SCRIPT_DIR/../common/resize-image.sh"

# Grow the working image before running apt update/upgrade + installs, which
# need more room than the ~2-3 GiB the upstream cloud image ships. Operator can
# override or disable with IMAGE_RESIZE=0.
IMAGE_MIN_DISK_GB="${IMAGE_MIN_DISK_GB:-8}"

# Get codename from first argument, default to noble
CODENAME="${1:-noble}"

# if $2 is nobuild, don't build
NOBUILD=false
if [[ "$2" == "nobuild" ]]; then
    NOBUILD=true
fi

# Configuration
UBUNTU_URL="${MIRROR:-https://cloud-images.ubuntu.com}/$CODENAME/current/$CODENAME-server-cloudimg-amd64.img"
IMAGE_NAME="$CODENAME-server-cloudimg-amd64.img"
OUTPUT_NAME="$CODENAME-server-cloudimg-amd64-qa.img"

echo "Setting up Ubuntu $CODENAME cloud image with qemu-guest-agent using qimi..."

# Download Ubuntu cloud image if it doesn't exist
if [[ ! -f "$IMAGE_NAME" ]]; then
    echo "Downloading Ubuntu $CODENAME cloud image..."
    wget -O "$IMAGE_NAME" "$UBUNTU_URL"
else
    echo "Using existing $IMAGE_NAME"
fi

# nobuild
if [ "$NOBUILD" == "true" ]; then
    echo "Skipping build for Rocky Linux"
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
    set -e
    # Make apt resilient to flaky mirrors.
    printf 'Acquire::Retries \"5\";\n' > /etc/apt/apt.conf.d/80-retries
    apt-get update
    apt-get install -y qemu-guest-agent
    systemctl enable qemu-guest-agent
    # Ship with empty apt lists so downstream consumers fetch fresh indices.
    apt-get clean
    rm -rf /var/lib/apt/lists/*
"

# Move to final name
mv "temp_$OUTPUT_NAME" "$OUTPUT_NAME"

echo "Done! Modified image saved as: $OUTPUT_NAME"