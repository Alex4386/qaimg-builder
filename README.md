# Qemu GuestAgent Image Builder

This is a collection of scripts to build cloudinit images with `qemu-guest-agent` installed with [`qimi`](https://github.com/packetstream-llc/qimi). for better integration with cloud platforms like OpenStack, Proxmox VE, etc.

## Build Status

| Distribution | Status | Download |
|--------------|--------|----------|
| Ubuntu | [![Build Ubuntu](https://github.com/Alex4386/qaimg-builder/actions/workflows/build-ubuntu.yml/badge.svg)](https://github.com/Alex4386/qaimg-builder/actions/workflows/build-ubuntu.yml) | [Latest Artifacts](https://github.com/Alex4386/qaimg-builder/actions/workflows/build-ubuntu.yml) |
| Debian | [![Build Debian](https://github.com/Alex4386/qaimg-builder/actions/workflows/build-debian.yml/badge.svg)](https://github.com/Alex4386/qaimg-builder/actions/workflows/build-debian.yml) | [Latest Artifacts](https://github.com/Alex4386/qaimg-builder/actions/workflows/build-debian.yml) |
| Rocky Linux | [![Build Rocky](https://github.com/Alex4386/qaimg-builder/actions/workflows/build-rocky.yml/badge.svg)](https://github.com/Alex4386/qaimg-builder/actions/workflows/build-rocky.yml) | [Latest Artifacts](https://github.com/Alex4386/qaimg-builder/actions/workflows/build-rocky.yml) |
| AlmaLinux | [![Build AlmaLinux](https://github.com/Alex4386/qaimg-builder/actions/workflows/build-alma.yml/badge.svg)](https://github.com/Alex4386/qaimg-builder/actions/workflows/build-alma.yml) | [Latest Artifacts](https://github.com/Alex4386/qaimg-builder/actions/workflows/build-alma.yml) |
| Arch Linux | [![Build Arch](https://github.com/Alex4386/qaimg-builder/actions/workflows/build-arch.yml/badge.svg)](https://github.com/Alex4386/qaimg-builder/actions/workflows/build-arch.yml) | [Latest Artifacts](https://github.com/Alex4386/qaimg-builder/actions/workflows/build-arch.yml) |

## Usage

### Downloading Pre-built Images

The easiest way to get images is to download pre-built ones from GitHub releases:

```bash
# Download the script (if not already cloned)
curl -O https://raw.githubusercontent.com/Alex4386/qaimg-builder/main/download-prebuilt.sh
chmod +x download-prebuilt.sh

# Download specific distribution images
./download-prebuilt.sh ubuntu noble          # Ubuntu Noble (24.04)
./download-prebuilt.sh debian bookworm       # Debian Bookworm (12)
./download-prebuilt.sh rocky 9               # Rocky Linux 9
./download-prebuilt.sh alma 8                # AlmaLinux 8
./download-prebuilt.sh arch                  # Arch Linux

# Download all available images from latest release
./download-prebuilt.sh --all

# Download from specific release
./download-prebuilt.sh -r v2025.07.29 ubuntu jammy

# List available releases
./download-prebuilt.sh --list

# List available assets in latest release
./download-prebuilt.sh --list-assets
```

**Script Dependencies:**
- `curl` - for downloading files
- `jq` - for parsing JSON responses
- `sha256sum` - for checksum verification

**Download Options:**
- `-r, --release TAG`: Download from specific release (default: latest)
- `-d, --dir DIR`: Download directory (default: ./downloads)
- `-a, --all`: Download all available images
- `--no-verify`: Skip checksum verification
- `-l, --list`: List available releases
- `--list-assets`: List available assets

### Building Images Locally

If you prefer to build images yourself:

#### Prerequisites
Install dependencies:
```bash
./common/setup-deps.sh
```

#### Building Images

```bash
# Ubuntu (default: noble)
./builders/ubuntu.sh
./builders/ubuntu.sh jammy    # specific version

# Debian (default: bookworm)
./builders/debian.sh
./builders/debian.sh bullseye # specific version

# Rocky Linux (default: 9)
./builders/rocky.sh
./builders/rocky.sh 8         # specific version

# AlmaLinux (default: 9)
./builders/alma.sh
./builders/alma.sh 8          # specific version

# Arch Linux
./builders/arch.sh
```

#### Output
Modified images are saved with `-qa` suffix:
- `ubuntu-noble-cloudimg-qa.img`
- `debian-bookworm-cloudimg-qa.qcow2`
- `rocky-9-cloudimg-qa.qcow2`
- `AlmaLinux-9-GenericCloud-latest-qa.x86_64.qcow2`
- `arch-cloudimg-qa.qcow2`

#### Using Custom Mirrors
```bash
MIRROR=https://mirror.example.com ./builders/ubuntu.sh
```