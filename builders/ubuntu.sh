#!/bin/bash

# Simple script to download Ubuntu cloud image and install qemu-guest-agent using qimi

set -e

# Source qimi installer
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/install-qimi.sh"

# Get codename from first argument, default to noble
CODENAME="${1:-noble}"

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

# Create working copy
echo "Creating working copy..."
cp "$IMAGE_NAME" "$OUTPUT_NAME.tmp"

# Install qemu-guest-agent using qimi (temporary mount)
echo "Installing qemu-guest-agent..."
sudo "$QIMI_PATH" exec "$OUTPUT_NAME.tmp" -- /bin/bash -c "
    apt-get update
    apt-get install -y qemu-guest-agent
    systemctl enable qemu-guest-agent
"

# Move to final name
mv "$OUTPUT_NAME.tmp" "$OUTPUT_NAME"

echo "Done! Modified image saved as: $OUTPUT_NAME"