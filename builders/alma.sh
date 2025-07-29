#!/bin/bash

# Simple script to download Rocky Linux cloud image and install qemu-guest-agent using qimi

set -e

# Source qimi installer
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/install-qimi.sh"

# Get version from first argument, default to 9
VERSION="${1:-9}"
PARTITION="4"

# Map version to package manager
case "$VERSION" in
    "9") PKG_MGR="dnf"; PARTITION="4" ;;
    "8") PKG_MGR="dnf"; PARTITION="5" ;;
    *) 
        echo "Error: Unsupported Rocky Linux version '$VERSION'"
        echo "Supported: 7, 8, 9"
        exit 1
        ;;
esac

# Configuration
ROCKY_URL="${MIRROR:-https://repo.almalinux.org/almalinux}/$VERSION/cloud/x86_64/images/Rocky-$VERSION-GenericCloud.latest.x86_64.qcow2"
CHECKSUM_URL="${MIRROR:-https://repo.almalinux.org/almalinux}/$VERSION/cloud/x86_64/images/CHECKSUM"
IMAGE_NAME="AlmaLinux-$VERSION-GenericCloud-latest.x86_64.qcow2"
OUTPUT_NAME="AlmaLinux-$VERSION-GenericCloud-latest-qa.x86_64.qcow2"

echo "Setting up Rocky Linux $VERSION cloud image with qemu-guest-agent using qimi..."

# Download checksum file (temporary)
echo "Downloading checksum file..."
if ! wget -q -O "$IMAGE_NAME.checksum.tmp" "$CHECKSUM_URL"; then
    echo "Warning: Could not download checksum file"
fi

# Download Rocky Linux cloud image if it doesn't exist or checksum differs
DOWNLOAD_NEEDED=false

if [[ ! -f "$IMAGE_NAME" ]]; then
    DOWNLOAD_NEEDED=true
    echo "Image not found, will download..."
elif [[ -f "$IMAGE_NAME.checksum.tmp" ]]; then
    echo "Verifying existing image checksum..."
    # Extract checksum for our specific file from the CHECKSUM file
    EXPECTED_CHECKSUM=$(grep "^SHA256 (Rocky-$VERSION-GenericCloud.latest.x86_64.qcow2)" "$IMAGE_NAME.checksum.tmp" | sed 's/.*= //')
    
    if [[ -n "$EXPECTED_CHECKSUM" ]]; then
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
        echo "Could not find checksum for Rocky-$VERSION-GenericCloud.latest.x86_64.qcow2 in CHECKSUM file"
        echo "Using existing image (no checksum found to verify)"
    fi
else
    echo "Using existing image (no checksum file to verify)"
fi

if [[ "$DOWNLOAD_NEEDED" == "true" ]]; then
    echo "Downloading Rocky Linux $VERSION cloud image..."
    if ! wget -O "$IMAGE_NAME" "$ROCKY_URL"; then
        echo "Failed to download Rocky Linux cloud image from $ROCKY_URL"
        echo "Available versions: 7, 8, 9"
        exit 1
    fi
    
    # Verify downloaded image
    if [[ -f "$IMAGE_NAME.checksum.tmp" ]]; then
        echo "Verifying downloaded image..."
        EXPECTED_CHECKSUM=$(grep "^SHA256 (Rocky-$VERSION-GenericCloud.latest.x86_64.qcow2)" "$IMAGE_NAME.checksum.tmp" | sed 's/.*= //')
        if [[ -n "$EXPECTED_CHECKSUM" ]]; then
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
fi

# Clean up temporary checksum file
rm -f "$IMAGE_NAME.checksum.tmp"

# Create working copy
echo "Creating working copy..."
cp "$IMAGE_NAME" "temp_$OUTPUT_NAME"

# Install qemu-guest-agent using qimi (temporary mount)
echo "Installing qemu-guest-agent..."
sudo "$QIMI_PATH" exec "temp_$OUTPUT_NAME" --nameserver 1.1.1.1 --partition 4 -- /bin/bash -c "
    $PKG_MGR update -y
    $PKG_MGR install -y qemu-guest-agent
    systemctl enable qemu-guest-agent
"

# Move to final name
mv "temp_$OUTPUT_NAME" "$OUTPUT_NAME"

echo "Done! Modified image saved as: $OUTPUT_NAME"