#!/bin/bash

# Simple script to download Debian cloud image and install qemu-guest-agent using qimi

set -e

# Get codename from first argument, default to bookworm
CODENAME="${1:-bookworm}"

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
IMAGE_NAME="debian-$CODENAME-cloud.qcow2"
OUTPUT_NAME="$CODENAME-generic-amd64-qa.qcow2"

echo "Setting up Debian $CODENAME cloud image with qemu-guest-agent using qimi..."

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root"
    exit 1
fi

# Download Debian cloud image if it doesn't exist
if [[ ! -f "$IMAGE_NAME" ]]; then
    echo "Downloading Debian $CODENAME cloud image..."
    wget -O "$IMAGE_NAME" "$DEBIAN_URL"
else
    echo "Using existing $IMAGE_NAME"
fi

# Create working copy
echo "Creating working copy..."
cp "$IMAGE_NAME" "$OUTPUT_NAME.tmp"

# Install qemu-guest-agent using qimi (temporary mount)
echo "Installing qemu-guest-agent..."
qimi exec "$OUTPUT_NAME.tmp" /bin/bash -c "
    apt-get update
    apt-get install -y qemu-guest-agent
    systemctl enable qemu-guest-agent
"

# Move to final name
mv "$OUTPUT_NAME.tmp" "$OUTPUT_NAME"

echo "Done! Modified image saved as: $OUTPUT_NAME"