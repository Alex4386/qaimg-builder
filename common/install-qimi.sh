#!/bin/bash

# Check if qimi is installed globally
if command -v qimi >/dev/null 2>&1; then
    echo "qimi is already installed globally"
    QIMI_PATH="$(command -v qimi)"
    return 0
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Check if qimi exists locally and add to PATH
if [ -f "$PROJECT_ROOT/bin/qimi" ]; then
    echo "qimi found locally, adding to PATH"
    QIMI_PATH="$PROJECT_ROOT/bin/qimi"
    return 0
fi

# Create bin directory if it doesn't exist
mkdir -p "$PROJECT_ROOT/bin"

# Download qimi from GitHub releases
echo "Downloading qimi..."
wget -O "$PROJECT_ROOT/bin/qimi" "https://github.com/PacketStream-LLC/qimi/releases/download/v0.0.2/qimi-linux-amd64"

# Make it executable
chmod +x "$PROJECT_ROOT/bin/qimi"
QIMI_PATH="$PROJECT_ROOT/bin/qimi"

echo "qimi installed to $PROJECT_ROOT/bin/qimi"
