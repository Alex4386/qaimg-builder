# QemuAgent Image Builder

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

# AlmaLinux (default: 9)
./builders/alma.sh
./builders/alma.sh 8          # specific version

# Arch Linux
./builders/arch.sh
```

### Output
Modified images are saved with `-qa` suffix:
- `ubuntu-noble-cloudimg-qa.img`
- `debian-bookworm-cloudimg-qa.qcow2`
- `rocky-9-cloudimg-qa.qcow2`
- `AlmaLinux-9-GenericCloud-latest-qa.x86_64.qcow2`
- `arch-cloudimg-qa.qcow2`

### Using Custom Mirrors
```bash
MIRROR=https://mirror.example.com ./builders/ubuntu.sh
```