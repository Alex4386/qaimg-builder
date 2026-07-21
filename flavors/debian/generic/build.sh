#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/../../lib/debian.sh"

# The "generic" flavor ships the reusable first-run machinery on its own, without
# any application: the initial-provision oneshot (home-template + drop-in runner)
# and the preconfigured-credentials library. It lets operators attach their own
# first-boot logic via cloud-init (drop-ins and /etc/qaimg/credentials) on top of
# a plain Debian QA image.
generic_provisioning_script() {
    cat <<'FLAVOR_SCRIPT'
set -e
export DEBIAN_FRONTEND=noninteractive

# openssl backs the credentials library's random value generation.
apt-get update
apt-get install -y openssl
FLAVOR_SCRIPT

    flavor_credentials_base_snippet
    flavor_initial_provision_base_snippet
}

generic_provisioning_script | build_debian_flavor "$@"
