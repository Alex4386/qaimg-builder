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

    flavor_credentials_base_snippet
    flavor_initial_provision_base_snippet
    flavor_initial_provision_group_dropin elasticsearch

    cat <<'EOF'
cat > /usr/local/lib/initial-provision.d/40-elasticsearch-credentials.sh <<'DROPIN'
#!/bin/bash
set -e
# Best-effort: if ELASTIC_PASSWORD is preconfigured in /etc/qaimg/credentials,
# set the built-in `elastic` superuser password on first boot. ES 8.x otherwise
# auto-generates this on first start; without a provided value we leave the
# auto-generated one in place (retrieve it with elasticsearch-reset-password).
. /usr/local/lib/qaimg-credentials.sh
RESET=/usr/share/elasticsearch/bin/elasticsearch-reset-password
[ -x "$RESET" ] || exit 0

elastic_pw="$(qaimg_cred ELASTIC_PASSWORD || true)"
[ -n "$elastic_pw" ] || exit 0

systemctl is-active --quiet elasticsearch || systemctl start elasticsearch || exit 0
# Wait for the node to accept the reset (it needs the cluster to be up). The
# interactive flow asks to confirm, then prompts for the password twice.
for _ in $(seq 1 30); do
    if printf 'y\n%s\n%s\n' "$elastic_pw" "$elastic_pw" \
        | "$RESET" -u elastic -i >/dev/null 2>&1; then
        break
    fi
    sleep 5
done
DROPIN
chmod 0755 /usr/local/lib/initial-provision.d/40-elasticsearch-credentials.sh
EOF
}

# Elasticsearch (JVM + package) benefits from build-time headroom.
export FLAVOR_MIN_DISK_GB="${FLAVOR_MIN_DISK_GB:-8}"

elasticsearch_provisioning_script | build_debian_flavor "$@"
