#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/../../lib/debian.sh"

build_debian_flavor "$@" <<'FLAVOR_SCRIPT'
set -e
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y apt-transport-https software-properties-common wget

install -m 0755 -d /usr/share/keyrings
wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key
printf '%s\n' \
    'deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main' \
    > /etc/apt/sources.list.d/grafana.list

apt-get update
apt-get install -y grafana
FLAVOR_SCRIPT
