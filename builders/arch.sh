#!/bin/bash

# Simple script to download Arch Linux cloud image and install qemu-guest-agent using qimi

set -e

# Source qimi installer
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/install-qimi.sh"

# Configuration
ARCH_URL="${MIRROR:-https://geo.mirror.pkgbuild.com/images/latest}/Arch-Linux-x86_64-cloudimg.qcow2"
CHECKSUM_URL="${MIRROR:-https://geo.mirror.pkgbuild.com/images/latest}/Arch-Linux-x86_64-cloudimg.qcow2.SHA256"
IMAGE_NAME="Arch-Linux-x86_64-cloudimg.qcow2"
OUTPUT_NAME="Arch-Linux-x86_64-cloudimg-qa.qcow2"

echo "Setting up Arch Linux cloud image with qemu-guest-agent using qimi..."

# Download checksum file (temporary)
echo "Downloading checksum file..."
if ! wget -q -O "$IMAGE_NAME.sha256.tmp" "$CHECKSUM_URL"; then
    echo "Warning: Could not download checksum file"
fi

# Download Arch Linux cloud image if it doesn't exist or checksum differs
DOWNLOAD_NEEDED=false

if [[ ! -f "$IMAGE_NAME" ]]; then
    DOWNLOAD_NEEDED=true
    echo "Image not found, will download..."
elif [[ -f "$IMAGE_NAME.sha256.tmp" ]]; then
    echo "Verifying existing image checksum..."
    EXPECTED_CHECKSUM=$(cat "$IMAGE_NAME.sha256.tmp" | awk '{print $1}')
    ACTUAL_CHECKSUM=$(sha256sum "$IMAGE_NAME" | awk '{print $1}')
    
    if [[ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]]; then
        echo "Checksum mismatch - image is outdated or corrupted"
        echo "Expected: $EXPECTED_CHECKSUM"
        echo "Actual:   $ACTUAL_CHECKSUM"
        DOWNLOAD_NEEDED=true
    else
        echo "Checksum verified - using existing image"
    fi
else
    echo "Using existing image (no checksum file to verify)"
fi

if [[ "$DOWNLOAD_NEEDED" == "true" ]]; then
    echo "Downloading Arch Linux cloud image..."
    if ! wget -O "$IMAGE_NAME" "$ARCH_URL"; then
        echo "Failed to download Arch Linux cloud image from $ARCH_URL"
        echo "Note: Arch Linux cloud images may become unavailable."
        echo "Consider using Ubuntu or Debian for more stable cloud image availability."
        exit 1
    fi
    
    # Verify downloaded image
    if [[ -f "$IMAGE_NAME.sha256.tmp" ]]; then
        echo "Verifying downloaded image..."
        EXPECTED_CHECKSUM=$(cat "$IMAGE_NAME.sha256.tmp" | awk '{print $1}')
        ACTUAL_CHECKSUM=$(sha256sum "$IMAGE_NAME" | awk '{print $1}')
        if [[ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]]; then
            echo "Downloaded image failed checksum verification!"
            echo "Expected: $EXPECTED_CHECKSUM"
            echo "Actual:   $ACTUAL_CHECKSUM"
            exit 1
        fi
        echo "Downloaded image verified successfully"
    fi
fi

# Clean up temporary checksum file
rm -f "$IMAGE_NAME.sha256.tmp"

# Create working copy
echo "Creating working copy..."
cp "$IMAGE_NAME" "$OUTPUT_NAME.tmp"

# Install qemu-guest-agent using qimi (temporary mount)
echo "Installing qemu-guest-agent..."
sudo "$QIMI_PATH" exec -i "$OUTPUT_NAME.tmp" --nameserver 1.1.1.1 -- /bin/bash -c "
    pacman -Sy --noconfirm qemu-guest-agent
    systemctl enable qemu-guest-agent
"

# Move to final name
mv "$OUTPUT_NAME.tmp" "$OUTPUT_NAME"

echo "Done! Modified image saved as: $OUTPUT_NAME"