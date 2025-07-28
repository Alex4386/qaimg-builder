# QemuAgent Image Builder

[![Build Images](https://github.com/Alex4386/qaimg-builder/actions/workflows/build-images.yml/badge.svg)](https://github.com/Alex4386/qaimg-builder/actions/workflows/build-images.yml)

This is a collection of scripts to build cloudinit images with `qemu-guest-agent` installed with [`qimi`](https://github.com/packetstream-llc/qimi). for better integration with cloud platforms like OpenStack, Proxmox VE, etc.  

## Pre-built Images

Pre-built images are available from [GitHub Actions](https://github.com/Alex4386/qaimg-builder/actions/workflows/build-images.yml). Download the latest artifacts from successful workflow runs.

## Usage

### Prerequisites
Install dependencies:
```bash
./common/setup-deps.sh
```

### Building Images

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

# Arch Linux
./builders/arch.sh
```

### Output
Modified images are saved with `-qa` suffix:
- `ubuntu-noble-cloudimg-qa.img`
- `debian-bookworm-cloudimg-qa.qcow2`
- `rocky-9-cloudimg-qa.qcow2`
- `arch-cloudimg-qa.qcow2`

### Using Custom Mirrors
```bash
MIRROR=https://mirror.example.com ./builders/ubuntu.sh
```