#!/bin/bash

# Script to download prebuilt cloud images with qemu-guest-agent from GitHub releases

set -e

REPO="Alex4386/qaimg-builder"
DOWNLOAD_DIR="./downloads"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS] <distribution> [version]

Download prebuilt cloud images with qemu-guest-agent from GitHub releases.

ARGUMENTS:
    distribution    Distribution to download (ubuntu|debian|rocky|alma|arch)
    version         Version/codename (optional, downloads latest if not specified)

OPTIONS:
    -r, --release TAG    Download from specific release tag (default: latest)
    -d, --dir DIR        Download directory (default: ./downloads)
    -l, --list           List available releases and exit
    -a, --all            Download all available images from the release
    -h, --help           Show this help message
    --no-verify          Skip checksum verification
    --list-assets        List available assets for the specified release

EXAMPLES:
    $0 ubuntu noble                    # Download Ubuntu Noble
    $0 debian bookworm                 # Download Debian Bookworm
    $0 rocky 9                         # Download Rocky Linux 9
    $0 alma 8                          # Download AlmaLinux 8
    $0 arch                            # Download Arch Linux
    $0 -a                              # Download all images from latest release
    $0 -r v2025.07.29 ubuntu jammy     # Download from specific release
    $0 -r v2025.07.29 -a              # Download all images from specific release
    $0 -l                              # List all releases
    $0 --list-assets                   # List assets in latest release

SUPPORTED DISTRIBUTIONS:
    ubuntu    - noble, jammy, focal
    debian    - bookworm, bullseye
    rocky     - 9, 8
    alma      - 9, 8
    arch      - latest

EOF
}

# Check dependencies
check_dependencies() {
    local missing_deps=()
    
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    if ! command -v sha256sum &> /dev/null; then
        missing_deps+=("sha256sum")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        print_info "Please install them using your package manager:"
        print_info "  Ubuntu/Debian: sudo apt-get install curl jq coreutils"
        print_info "  CentOS/RHEL: sudo yum install curl jq coreutils"
        print_info "  Arch: sudo pacman -S curl jq coreutils"
        exit 1
    fi
}

# List all releases
list_releases() {
    print_info "Fetching releases from GitHub..."
    local releases=$(curl -s "https://api.github.com/repos/$REPO/releases" | jq -r '.[].tag_name')
    
    if [ -z "$releases" ]; then
        print_error "No releases found or failed to fetch releases"
        exit 1
    fi
    
    echo "Available releases:"
    echo "$releases" | while read -r release; do
        echo "  $release"
    done
}

# List assets for a specific release
list_assets() {
    local release_tag="$1"
    
    if [ "$release_tag" = "latest" ]; then
        local api_url="https://api.github.com/repos/$REPO/releases/latest"
    else
        local api_url="https://api.github.com/repos/$REPO/releases/tags/$release_tag"
    fi
    
    print_info "Fetching assets for release: $release_tag"
    local assets=$(curl -s "$api_url" | jq -r '.assets[].name')
    
    if [ -z "$assets" ]; then
        print_error "No assets found for release $release_tag"
        exit 1
    fi
    
    echo "Available assets:"
    echo "$assets" | while read -r asset; do
        echo "  $asset"
    done
}

# Get download URL for specific asset
get_download_url() {
    local release_tag="$1"
    local asset_name="$2"
    
    if [ "$release_tag" = "latest" ]; then
        local api_url="https://api.github.com/repos/$REPO/releases/latest"
    else
        local api_url="https://api.github.com/repos/$REPO/releases/tags/$release_tag"
    fi
    
    local download_url=$(curl -s "$api_url" | jq -r ".assets[] | select(.name == \"$asset_name\") | .browser_download_url")
    
    if [ -z "$download_url" ] || [ "$download_url" = "null" ]; then
        return 1
    fi
    
    echo "$download_url"
}

# Determine asset name based on distribution and version
get_asset_name() {
    local distro="$1"
    local version="$2"
    
    case "$distro" in
        ubuntu)
            if [ -z "$version" ]; then
                version="noble"  # default
            fi
            echo "${version}-server-cloudimg-amd64-qa.img"
            ;;
        debian)
            if [ -z "$version" ]; then
                version="bookworm"  # default
            fi
            echo "debian-${version}-generic-amd64-qa.qcow2"
            ;;
        rocky)
            if [ -z "$version" ]; then
                version="9"  # default
            fi
            echo "Rocky-${version}-GenericCloud-Base-latest-qa.x86_64.qcow2"
            ;;
        alma)
            if [ -z "$version" ]; then
                version="9"  # default
            fi
            echo "AlmaLinux-${version}-GenericCloud-latest-qa.x86_64.qcow2"
            ;;
        arch)
            echo "Arch-Linux-x86_64-cloudimg-qa.qcow2"
            ;;
        *)
            print_error "Unsupported distribution: $distro"
            print_info "Supported: ubuntu, debian, rocky, alma, arch"
            exit 1
            ;;
    esac
}

# Download all images from a release
download_all_images() {
    local release_tag="$1"
    local verify_checksum="$2"
    
    if [ "$release_tag" = "latest" ]; then
        local api_url="https://api.github.com/repos/$REPO/releases/latest"
    else
        local api_url="https://api.github.com/repos/$REPO/releases/tags/$release_tag"
    fi
    
    print_info "Fetching all assets from release: $release_tag"
    local assets=$(curl -s "$api_url" | jq -r '.assets[] | select(.name | test("\\.(img|qcow2)$")) | .name')
    
    if [ -z "$assets" ]; then
        print_error "No image assets found for release $release_tag"
        exit 1
    fi
    
    local total_count=$(echo "$assets" | wc -l)
    local current=0
    local failed=0
    
    print_info "Found $total_count image(s) to download"
    
    # Use array to avoid subshell issues
    local assets_array=()
    while IFS= read -r line; do
        assets_array+=("$line")
    done <<< "$assets"
    
    for asset_name in "${assets_array[@]}"; do
        current=$((current + 1))
        print_info "[$current/$total_count] Processing: $asset_name"
        
        local download_url=$(get_download_url "$release_tag" "$asset_name")
        if [ $? -ne 0 ] || [ -z "$download_url" ]; then
            print_error "Failed to get download URL for $asset_name"
            failed=$((failed + 1))
            continue
        fi
        
        if download_file "$download_url" "$asset_name" "$verify_checksum"; then
            print_success "[$current/$total_count] Downloaded: $asset_name"
        else
            print_error "[$current/$total_count] Failed to download: $asset_name"
            failed=$((failed + 1))
        fi
    done
    
    if [ $failed -eq 0 ]; then
        print_success "Successfully downloaded all $total_count image(s)"
    else
        print_warning "Downloaded $((total_count - failed)) out of $total_count image(s)"
        if [ $failed -gt 0 ]; then
            return 1
        fi
    fi
}

# Download and verify file
download_file() {
    local url="$1"
    local filename="$2"
    local verify_checksum="$3"
    
    local filepath="$DOWNLOAD_DIR/$filename"
    
    # Create download directory
    mkdir -p "$DOWNLOAD_DIR"
    
    # Download file
    print_info "Downloading $filename..."
    if curl -L -o "$filepath" "$url"; then
        print_success "Downloaded: $filepath"
    else
        print_error "Failed to download $filename"
        return 1
    fi
    
    # Download and verify checksum if requested
    if [ "$verify_checksum" = "true" ]; then
        local checksum_url="${url}.sha256"
        local checksum_file="${filepath}.sha256"
        
        print_info "Downloading checksum..."
        if curl -L -o "$checksum_file" "$checksum_url" 2>/dev/null; then
            print_info "Verifying checksum..."
            if (cd "$DOWNLOAD_DIR" && sha256sum -c "$filename.sha256"); then
                print_success "Checksum verification passed"
                rm "$checksum_file"
            else
                print_error "Checksum verification failed"
                return 1
            fi
        else
            print_warning "Checksum file not available, skipping verification"
        fi
    fi
    
    return 0
}

# Main function
main() {
    local release_tag="latest"
    local verify_checksum="true"
    local list_releases_flag="false"
    local list_assets_flag="false"
    local download_all_flag="false"
    local distribution=""
    local version=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--release)
                release_tag="$2"
                shift 2
                ;;
            -d|--dir)
                DOWNLOAD_DIR="$2"
                shift 2
                ;;
            -l|--list)
                list_releases_flag="true"
                shift
                ;;
            -a|--all)
                download_all_flag="true"
                shift
                ;;
            --list-assets)
                list_assets_flag="true"
                shift
                ;;
            --no-verify)
                verify_checksum="false"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                print_error "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                if [ -z "$distribution" ]; then
                    distribution="$1"
                elif [ -z "$version" ]; then
                    version="$1"
                else
                    print_error "Too many arguments"
                    usage
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Check dependencies
    check_dependencies
    
    # Handle list operations
    if [ "$list_releases_flag" = "true" ]; then
        list_releases
        exit 0
    fi
    
    if [ "$list_assets_flag" = "true" ]; then
        list_assets "$release_tag"
        exit 0
    fi
    
    # Handle download all option
    if [ "$download_all_flag" = "true" ]; then
        if [ -n "$distribution" ]; then
            print_error "Cannot specify distribution when using --all option"
            exit 1
        fi
        
        if download_all_images "$release_tag" "$verify_checksum"; then
            exit 0
        else
            exit 1
        fi
    fi
    
    # Validate required arguments
    if [ -z "$distribution" ]; then
        print_error "Distribution is required"
        usage
        exit 1
    fi
    
    # Get asset name
    local asset_name=$(get_asset_name "$distribution" "$version")
    print_info "Looking for asset: $asset_name"
    
    # Get download URL
    local download_url=$(get_download_url "$release_tag" "$asset_name")
    if [ $? -ne 0 ] || [ -z "$download_url" ]; then
        print_error "Asset not found: $asset_name in release $release_tag"
        print_info "Use --list-assets to see available assets"
        exit 1
    fi
    
    # Download file
    if download_file "$download_url" "$asset_name" "$verify_checksum"; then
        print_success "Successfully downloaded $asset_name to $DOWNLOAD_DIR/"
        
        # Show file info
        local filepath="$DOWNLOAD_DIR/$asset_name"
        local filesize=$(stat -c%s "$filepath" 2>/dev/null || stat -f%z "$filepath" 2>/dev/null || echo "unknown")
        print_info "File size: $(numfmt --to=iec --suffix=B "$filesize" 2>/dev/null || echo "$filesize bytes")"
    else
        exit 1
    fi
}

main "$@"