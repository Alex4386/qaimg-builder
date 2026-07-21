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

    flavor_initial_provision_base_snippet
    flavor_initial_provision_group_dropin docker

    cat <<'EOF'
cat > /usr/local/lib/initial-provision.d/40-supabase-secrets.sh <<'DROPIN'
#!/bin/bash
set -e
# Replace the shipped example secrets with per-instance random values on first
# boot so every image does not share the same well-known credentials.
ENV_FILE=/opt/supabase/project/.env
if [ -f "$ENV_FILE" ] && [ ! -f /opt/supabase/.secrets-done ]; then
    pg_pw="$(openssl rand -hex 24)"
    dash_pw="$(openssl rand -hex 24)"
    secret="$(openssl rand -hex 40)"
    sed -i \
        -e "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${pg_pw}|" \
        -e "s|^DASHBOARD_PASSWORD=.*|DASHBOARD_PASSWORD=${dash_pw}|" \
        -e "s|^SECRET_KEY_BASE=.*|SECRET_KEY_BASE=${secret}|" \
        "$ENV_FILE"
    chown supabase:supabase "$ENV_FILE"
    : > /opt/supabase/.secrets-done
    chown supabase:supabase /opt/supabase/.secrets-done
fi
DROPIN
chmod 0755 /usr/local/lib/initial-provision.d/40-supabase-secrets.sh
EOF
}

supabase_provisioning_script | build_debian_flavor "$@"
