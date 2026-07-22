#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/../../lib/debian.sh"

strapi_provisioning_script() {
    cat <<'FLAVOR_SCRIPT'
set -e
export DEBIAN_FRONTEND=noninteractive

NODE_MAJOR=22
STRAPI_DIR=/opt/strapi
STRAPI_APP="$STRAPI_DIR/app"

apt-get update
apt-get install -y apt-transport-https ca-certificates curl gnupg git build-essential openssl

# Node.js LTS from NodeSource (Strapi supports Active/Maintenance LTS only).
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

apt-get update
apt-get install -y nodejs

# Dedicated non-login system user owns the app tree.
if ! id -u strapi >/dev/null 2>&1; then
    useradd --system --user-group --home-dir "$STRAPI_DIR" \
        --shell /usr/sbin/nologin strapi
fi
install -d -o strapi -g strapi "$STRAPI_DIR"

# Scaffold a production project non-interactively. SQLite keeps the image
# self-contained; switch DATABASE_CLIENT in the .env for an external database.
# The target directory is a positional argument (there is no --dir flag), and
# --non-interactive is required to skip all prompts in a headless build.
sudo -u strapi -H env HOME="$STRAPI_DIR" npx --yes create-strapi-app@latest "$STRAPI_APP" \
    --no-run --skip-cloud --use-npm --dbclient=sqlite --js \
    --no-git-init --non-interactive

# Build the admin panel for production.
sudo -u strapi -H env HOME="$STRAPI_DIR" NODE_ENV=production \
    npm --prefix "$STRAPI_APP" run build
chown -R strapi:strapi "$STRAPI_DIR"

cat > /etc/systemd/system/strapi.service <<'UNIT'
[Unit]
Description=Strapi Headless CMS
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=strapi
Group=strapi
WorkingDirectory=/opt/strapi/app
Environment=HOME=/opt/strapi
Environment=NODE_ENV=production
ExecStart=/usr/bin/npm run start
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

systemctl enable strapi.service
FLAVOR_SCRIPT

    flavor_credentials_base_snippet
    flavor_initial_provision_base_snippet
    flavor_initial_provision_group_dropin strapi

    cat <<'EOF'
cat > /usr/local/lib/initial-provision.d/40-strapi-secrets.sh <<'DROPIN'
#!/bin/bash
set -e
# create-strapi-app bakes APP_KEYS/*_SALT/*_SECRET into .env at BUILD time, so
# every image would otherwise share identical secrets. On first boot, apply
# preconfigured values from /etc/qaimg/credentials, else generate per-instance
# random ones, then restart Strapi so it picks them up.
. /usr/local/lib/qaimg-credentials.sh
ENV_FILE=/opt/strapi/app/.env
[ -f "$ENV_FILE" ] || exit 0
[ -f /opt/strapi/.secrets-done ] && exit 0

app_keys="$(qaimg_cred STRAPI_APP_KEYS || echo "$(openssl rand -hex 16),$(openssl rand -hex 16)")"
api_salt="$(qaimg_cred_or_random STRAPI_API_TOKEN_SALT 16)"
admin_jwt="$(qaimg_cred_or_random STRAPI_ADMIN_JWT_SECRET 16)"
xfer_salt="$(qaimg_cred_or_random STRAPI_TRANSFER_TOKEN_SALT 16)"
jwt_secret="$(qaimg_cred_or_random STRAPI_JWT_SECRET 16)"
enc_key="$(qaimg_cred_or_random STRAPI_ENCRYPTION_KEY 16)"

set_kv() {
    local key="$1" val="$2"
    if grep -qE "^${key}=" "$ENV_FILE"; then
        sed -i -E "s|^${key}=.*|${key}=${val}|" "$ENV_FILE"
    else
        printf '%s=%s\n' "$key" "$val" >> "$ENV_FILE"
    fi
}
set_kv APP_KEYS "$app_keys"
set_kv API_TOKEN_SALT "$api_salt"
set_kv ADMIN_JWT_SECRET "$admin_jwt"
set_kv TRANSFER_TOKEN_SALT "$xfer_salt"
set_kv JWT_SECRET "$jwt_secret"
set_kv ENCRYPTION_KEY "$enc_key"
chown strapi:strapi "$ENV_FILE"
: > /opt/strapi/.secrets-done
chown strapi:strapi /opt/strapi/.secrets-done
systemctl try-restart strapi.service || true
DROPIN
chmod 0755 /usr/local/lib/initial-provision.d/40-strapi-secrets.sh
EOF
}

# Node.js + node_modules + admin build need more than the base ~3G image.
export FLAVOR_MIN_DISK_GB="${FLAVOR_MIN_DISK_GB:-8}"

strapi_provisioning_script | build_debian_flavor "$@"
