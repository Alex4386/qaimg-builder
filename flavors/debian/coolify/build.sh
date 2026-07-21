#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/../../lib/debian.sh"

coolify_provisioning_script() {
    cat <<'FLAVOR_SCRIPT'
set -e
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y ca-certificates curl gnupg

# Coolify runs on Docker Engine. Bake the official Docker apt repo and engine at
# build time (the deb822 way, like the docker flavor) so the coolify installer
# only has to bootstrap Coolify itself at first boot.
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
    -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

. /etc/os-release
cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $VERSION_CODENAME
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
systemctl enable docker.service
FLAVOR_SCRIPT

    flavor_initial_provision_base_snippet
    flavor_initial_provision_group_dropin docker

    cat <<'EOF'
cat > /usr/local/lib/initial-provision.d/40-coolify-install.sh <<'DROPIN'
#!/bin/bash
set -e
# Coolify's official installer needs a running Docker daemon, so it runs on the
# booted instance rather than in the image build. It installs Coolify into
# /data/coolify and starts the dockerized dashboard on port 8000. It is a no-op
# if Coolify is already installed.
if [ ! -f /data/coolify/source/docker-compose.yml ]; then
    curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash
fi
DROPIN
chmod 0755 /usr/local/lib/initial-provision.d/40-coolify-install.sh
EOF
}

# Docker Engine at build time; Coolify + its containers install at first boot and
# want a large deploy disk. Give the build modest headroom over the ~3G base.
export FLAVOR_MIN_DISK_GB="${FLAVOR_MIN_DISK_GB:-6}"

coolify_provisioning_script | build_debian_flavor "$@"
