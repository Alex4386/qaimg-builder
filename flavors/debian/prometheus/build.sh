#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/../../lib/debian.sh"

prometheus_provisioning_script() {
    cat <<'FLAVOR_SCRIPT'
set -e
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y prometheus

# The Debian package ships the `prometheus` system user and a systemd unit;
# make sure it is enabled so the monitoring server starts on boot.
systemctl enable prometheus.service
FLAVOR_SCRIPT

    flavor_initial_provision_base_snippet
    flavor_initial_provision_group_dropin prometheus
}

prometheus_provisioning_script | build_debian_flavor "$@"
