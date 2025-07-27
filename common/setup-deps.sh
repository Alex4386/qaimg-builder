#!/bin/bash

# Check and install required dependencies for qaimg-builder

# Function to detect OS and package manager
detect_os() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "debian"
    elif command -v dnf >/dev/null 2>&1; then
        echo "fedora"
    elif command -v yum >/dev/null 2>&1; then
        echo "rhel"
    elif command -v pacman >/dev/null 2>&1; then
        echo "arch"
    else
        echo "unknown"
    fi
}

# Function to install packages based on OS
install_packages() {
    local os="$1"
    local packages="$2"
    
    case "$os" in
        "debian")
            echo "Installing packages with apt-get: $packages"
            sudo apt-get update
            sudo apt-get install -y $packages
            ;;
        "fedora")
            echo "Installing packages with dnf: $packages"
            sudo dnf install -y $packages
            ;;
        "rhel")
            echo "Installing packages with yum: $packages"
            sudo yum install -y $packages
            ;;
        "arch")
            echo "Installing packages with pacman: $packages"
            sudo pacman -Sy --noconfirm $packages
            ;;
        *)
            echo "Unknown OS. Please install the following packages manually: $packages"
            return 1
            ;;
    esac
}

# Check if partprobe is installed
if ! command -v partprobe >/dev/null 2>&1; then
    echo "partprobe not found, installing..."
    OS=$(detect_os)
    case "$OS" in
        "debian")
            install_packages "$OS" "parted"
            ;;
        "fedora"|"rhel")
            install_packages "$OS" "parted"
            ;;
        "arch")
            install_packages "$OS" "parted"
            ;;
        *)
            echo "Error: Cannot install partprobe on unknown OS"
            return 1
            ;;
    esac
else
    echo "partprobe is already installed"
fi

# Check if qemu-nbd is installed
if ! command -v qemu-nbd >/dev/null 2>&1; then
    echo "qemu-nbd not found, installing..."
    OS=$(detect_os)
    case "$OS" in
        "debian")
            install_packages "$OS" "qemu-utils"
            ;;
        "fedora"|"rhel")
            install_packages "$OS" "qemu-img"
            ;;
        "arch")
            install_packages "$OS" "qemu-base"
            ;;
        *)
            echo "Error: Cannot install qemu-nbd on unknown OS"
            return 1
            ;;
    esac
else
    echo "qemu-nbd is already installed"
fi

echo "Dependencies check complete"