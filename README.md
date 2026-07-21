# Qemu GuestAgent Image Builder

This is a collection of scripts to build cloudinit images with `qemu-guest-agent` installed with [`qimi`](https://github.com/packetstream-llc/qimi). for better integration with cloud platforms like OpenStack, Proxmox VE, etc.

## Build Status

### Global Build (weekly)
| Status | Download | Artifacts |
|--------|----------|-----------|
| [![Build Release](https://github.com/Alex4386/qaimg-builder/actions/workflows/release.yml/badge.svg)](https://github.com/Alex4386/qaimg-builder/actions/workflows/release.yml) | [Latest Release](https://github.com/Alex4386/qaimg-builder/releases/latest) | [Latest Artifacts](https://github.com/Alex4386/qaimg-builder/actions/workflows/release.yml) |

### Nightly Builds per Distribution
| Distribution | Status | Download |
|--------------|--------|----------|
| Ubuntu | [![Build Ubuntu](https://github.com/Alex4386/qaimg-builder/actions/workflows/build-ubuntu.yml/badge.svg)](https://github.com/Alex4386/qaimg-builder/actions/workflows/build-ubuntu.yml) | [Latest Artifacts](https://github.com/Alex4386/qaimg-builder/actions/workflows/build-ubuntu.yml) |
| Debian | [![Build Debian](https://github.com/Alex4386/qaimg-builder/actions/workflows/build-debian.yml/badge.svg)](https://github.com/Alex4386/qaimg-builder/actions/workflows/build-debian.yml) | [Latest Artifacts](https://github.com/Alex4386/qaimg-builder/actions/workflows/build-debian.yml) |
| Debian Flavors | [![Build Debian Flavors](https://github.com/Alex4386/qaimg-builder/actions/workflows/build-flavors.yml/badge.svg)](https://github.com/Alex4386/qaimg-builder/actions/workflows/build-flavors.yml) | [Latest Artifacts](https://github.com/Alex4386/qaimg-builder/actions/workflows/build-flavors.yml) |
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
./download-prebuilt.sh debian trixie         # Debian Trixie (13)
./download-prebuilt.sh rocky 10              # Rocky Linux 10
./download-prebuilt.sh alma 10               # AlmaLinux 10
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
./builders/debian.sh trixie   # specific version

# Rocky Linux (default: 9)
./builders/rocky.sh
./builders/rocky.sh 10        # specific version

# AlmaLinux (default: 9)
./builders/alma.sh
./builders/alma.sh 10         # specific version

# Arch Linux
./builders/arch.sh
```

#### Building Application Flavors

Application flavors bake a service stack into a distribution image, similar to
cloud application blueprints:

```bash
# List available flavors
./flavors/build.sh --list

# Build Debian Bookworm with just the first-run machinery (no app)
./flavors/build.sh debian generic bookworm

# Build Debian Bookworm with Nginx and qemu-guest-agent
./flavors/build.sh debian nginx bookworm

# Build Debian Bookworm with Node.js
./flavors/build.sh debian nodejs bookworm

# Build Debian Bookworm with WireGuard
./flavors/build.sh debian wireguard bookworm

# Build Debian Bookworm with Docker
./flavors/build.sh debian docker bookworm

# Build Debian Bookworm with Grafana OSS
./flavors/build.sh debian grafana bookworm

# Build Debian Bookworm with MariaDB
./flavors/build.sh debian mariadb bookworm

# Build Debian Bookworm with PostgreSQL
./flavors/build.sh debian postgresql bookworm

# Build Debian Bookworm with a vanilla Minecraft server
./flavors/build.sh debian minecraft-vanilla bookworm

# Build Debian Bookworm with a Paper Minecraft server
./flavors/build.sh debian minecraft-paper bookworm

# Build Debian Bookworm with a Palworld dedicated server
./flavors/build.sh debian palworld bookworm

# Build Debian Bookworm with OpenClaw (personal AI assistant gateway)
./flavors/build.sh debian openclaw bookworm

# Build Debian Bookworm with Coolify (self-hosted PaaS)
./flavors/build.sh debian coolify bookworm

# Build Debian Bookworm with self-hosted Supabase
./flavors/build.sh debian supabase bookworm

# Build Debian Bookworm with GitLab CE
./flavors/build.sh debian gitlab bookworm

# Build Debian Bookworm with Strapi
./flavors/build.sh debian strapi bookworm

# Build Debian Bookworm with Prometheus
./flavors/build.sh debian prometheus bookworm

# Build Debian Bookworm with Elasticsearch
./flavors/build.sh debian elasticsearch bookworm
```

Flavor builders live at `flavors/<distribution>/<flavor>/build.sh`. See
[`flavors/README.md`](flavors/README.md) for usage and authoring details.

##### Preconfigured credentials

Flavors that manage secrets (PostgreSQL, MariaDB, Supabase, Strapi, GitLab,
Elasticsearch) resolve them at first boot rather than baking fixed values into
the image. Supply them at deploy time through cloud-init by writing
`/etc/qaimg/credentials`; keys you omit are generated randomly and persisted to
`/etc/qaimg/credentials.generated`. See [`examples/vendor.yaml`](examples/vendor.yaml)
for a ready-to-adapt cloud-init file and
[`flavors/README.md`](flavors/README.md) for the full mechanism.

#### Output
Modified images are saved with `-qa` suffix:
- `noble-server-cloudimg-amd64-qa.img`
- `bookworm-generic-amd64-qa.qcow2`
- `bookworm-generic-amd64-qa.generic.qcow2` (generic first-run flavor)
- `bookworm-generic-amd64-qa.nginx.qcow2` (Nginx flavor)
- `bookworm-generic-amd64-qa.nodejs.qcow2` (Node.js flavor)
- `bookworm-generic-amd64-qa.wireguard.qcow2` (WireGuard flavor)
- `bookworm-generic-amd64-qa.docker.qcow2` (Docker flavor)
- `bookworm-generic-amd64-qa.grafana.qcow2` (Grafana OSS flavor)
- `bookworm-generic-amd64-qa.mariadb.qcow2` (MariaDB flavor)
- `bookworm-generic-amd64-qa.postgresql.qcow2` (PostgreSQL flavor)
- `bookworm-generic-amd64-qa.minecraft-vanilla.qcow2` (Minecraft Vanilla flavor)
- `bookworm-generic-amd64-qa.minecraft-paper.qcow2` (Minecraft Paper flavor)
- `bookworm-generic-amd64-qa.palworld.qcow2` (Palworld flavor)
- `bookworm-generic-amd64-qa.openclaw.qcow2` (OpenClaw flavor)
- `bookworm-generic-amd64-qa.coolify.qcow2` (Coolify flavor)
- `bookworm-generic-amd64-qa.supabase.qcow2` (Supabase flavor)
- `bookworm-generic-amd64-qa.gitlab.qcow2` (GitLab CE flavor)
- `bookworm-generic-amd64-qa.strapi.qcow2` (Strapi flavor)
- `bookworm-generic-amd64-qa.prometheus.qcow2` (Prometheus flavor)
- `bookworm-generic-amd64-qa.elasticsearch.qcow2` (Elasticsearch flavor)
- `rockylinux-9-GenericCloud.latest-qa.qcow2`
- `AlmaLinux-9-GenericCloud-latest-qa.x86_64.qcow2`
- `Arch-Linux-x86_64-cloudimg-qa.qcow2`

#### Using Custom Mirrors
```bash
MIRROR=https://mirror.example.com ./builders/ubuntu.sh
```
