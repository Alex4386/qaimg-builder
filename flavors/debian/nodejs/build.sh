#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/../../lib/debian.sh"

build_debian_flavor "$@" <<'FLAVOR_SCRIPT'
set -e
export DEBIAN_FRONTEND=noninteractive

NODE_MAJOR=24

apt-get update
apt-get install -y apt-transport-https ca-certificates curl gnupg

install -m 0755 -d /usr/share/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | \
    gpg --dearmor --batch --yes -o /usr/share/keyrings/nodesource.gpg
chmod a+r /usr/share/keyrings/nodesource.gpg

cat > /etc/apt/sources.list.d/nodesource.sources <<EOF
Types: deb
URIs: https://deb.nodesource.com/node_${NODE_MAJOR}.x
Suites: nodistro
Components: main
Architectures: $(dpkg --print-architecture)
Signed-By: /usr/share/keyrings/nodesource.gpg
EOF

cat > /etc/apt/preferences.d/nodejs <<'EOF'
Package: nodejs
Pin: origin deb.nodesource.com
Pin-Priority: 600
EOF

apt-get update
apt-get install -y nodejs
FLAVOR_SCRIPT
