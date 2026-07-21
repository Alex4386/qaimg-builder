#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/../../lib/debian.sh"

elasticsearch_provisioning_script() {
    cat <<'FLAVOR_SCRIPT'
set -e
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y apt-transport-https ca-certificates gnupg wget

install -m 0755 -d /usr/share/keyrings
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | \
    gpg --dearmor --batch --yes -o /usr/share/keyrings/elasticsearch-keyring.gpg
chmod a+r /usr/share/keyrings/elasticsearch-keyring.gpg

# `Suites: stable` is Elastic's repository suite name, not a Debian codename,
# so it stays fixed regardless of the base image release.
cat > /etc/apt/sources.list.d/elastic-8.x.sources <<EOF
Types: deb
URIs: https://artifacts.elastic.co/packages/8.x/apt
Suites: stable
Components: main
Architectures: $(dpkg --print-architecture)
Signed-By: /usr/share/keyrings/elasticsearch-keyring.gpg
EOF

apt-get update
apt-get install -y elasticsearch

# The package ships the `elasticsearch` system user and a systemd unit but does
# not enable it; enable it so the node starts on boot.
systemctl enable elasticsearch.service
FLAVOR_SCRIPT

    flavor_initial_provision_base_snippet
    flavor_initial_provision_group_dropin elasticsearch
}

elasticsearch_provisioning_script | build_debian_flavor "$@"
