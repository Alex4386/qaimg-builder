#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/../../lib/debian.sh"

supabase_provisioning_script() {
    cat <<'FLAVOR_SCRIPT'
set -e
export DEBIAN_FRONTEND=noninteractive

SUPABASE_DIR=/opt/supabase
SUPABASE_PROJECT="$SUPABASE_DIR/project"

apt-get update
apt-get install -y ca-certificates curl gnupg git openssl jq
# openssl also powers first-boot credential generation.

# Supabase self-hosting is distributed as a Docker Compose stack, so bake Docker
# Engine from Docker's official apt repo (the deb822 way, like the docker flavor).
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

# Dedicated system user owns the compose project tree.
if ! id -u supabase >/dev/null 2>&1; then
    useradd --system --user-group --home-dir "$SUPABASE_DIR" \
        --shell /usr/sbin/nologin supabase
fi
install -d -o supabase -g supabase "$SUPABASE_DIR"

# Sparse-clone just the docker/ config from the Supabase repo and stage it as a
# self-contained compose project. Secrets in .env are replaced at first boot.
git clone --depth 1 --filter=blob:none --sparse \
    https://github.com/supabase/supabase.git "$SUPABASE_DIR/supabase"
git -C "$SUPABASE_DIR/supabase" sparse-checkout set docker
install -d "$SUPABASE_PROJECT"
cp -a "$SUPABASE_DIR/supabase/docker/." "$SUPABASE_PROJECT/"
cp "$SUPABASE_PROJECT/.env.example" "$SUPABASE_PROJECT/.env"
chown -R supabase:supabase "$SUPABASE_DIR"

cat > /etc/systemd/system/supabase.service <<'UNIT'
[Unit]
Description=Supabase self-hosted stack
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
User=supabase
Group=supabase
WorkingDirectory=/opt/supabase/project
ExecStart=/usr/bin/docker compose up -d --wait
ExecStop=/usr/bin/docker compose down

[Install]
WantedBy=multi-user.target
UNIT

systemctl enable supabase.service
FLAVOR_SCRIPT

    flavor_credentials_base_snippet
    flavor_initial_provision_base_snippet
    flavor_initial_provision_group_dropin docker

    cat <<'EOF'
cat > /usr/local/lib/initial-provision.d/40-supabase-secrets.sh <<'DROPIN'
#!/bin/bash
set -e
# On first boot, fill the stack's secrets. Preconfigured values from
# /etc/qaimg/credentials win; otherwise per-instance random values are generated
# (and persisted) so no two images share the shipped example credentials.
. /usr/local/lib/qaimg-credentials.sh

ENV_FILE=/opt/supabase/project/.env
if [ -f "$ENV_FILE" ] && [ ! -f /opt/supabase/.secrets-done ]; then
    pg_pw="$(qaimg_cred_or_random POSTGRES_PASSWORD)"
    dash_user="$(qaimg_cred DASHBOARD_USERNAME || echo supabase)"
    dash_pw="$(qaimg_cred_or_random DASHBOARD_PASSWORD)"
    secret="$(qaimg_cred_or_random SECRET_KEY_BASE 40)"
    jwt_secret="$(qaimg_cred_or_random JWT_SECRET 40)"
    sed -i \
        -e "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${pg_pw}|" \
        -e "s|^DASHBOARD_USERNAME=.*|DASHBOARD_USERNAME=${dash_user}|" \
        -e "s|^DASHBOARD_PASSWORD=.*|DASHBOARD_PASSWORD=${dash_pw}|" \
        -e "s|^SECRET_KEY_BASE=.*|SECRET_KEY_BASE=${secret}|" \
        -e "s|^JWT_SECRET=.*|JWT_SECRET=${jwt_secret}|" \
        "$ENV_FILE"
    chown supabase:supabase "$ENV_FILE"
    : > /opt/supabase/.secrets-done
    chown supabase:supabase /opt/supabase/.secrets-done
fi
DROPIN
chmod 0755 /usr/local/lib/initial-provision.d/40-supabase-secrets.sh
EOF
}

# Docker Engine + compose project tree; runtime image pulls need a large deploy
# disk, but the build itself only needs modest headroom over the ~3G base.
export FLAVOR_MIN_DISK_GB="${FLAVOR_MIN_DISK_GB:-6}"

supabase_provisioning_script | build_debian_flavor "$@"
