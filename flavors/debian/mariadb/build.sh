#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/../../lib/debian.sh"

mariadb_provisioning_script() {
    cat <<'FLAVOR_SCRIPT'
set -e
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y mariadb-server openssl
FLAVOR_SCRIPT

    flavor_credentials_base_snippet
    flavor_initial_provision_base_snippet

    cat <<'EOF'
cat > /usr/local/lib/initial-provision.d/40-mariadb-credentials.sh <<'DROPIN'
#!/bin/bash
set -e
# Apply preconfigured credentials on first boot: set the root password (from
# MARIADB_ROOT_PASSWORD, else a persisted random one) and optionally create an
# application database + user. Uses local root socket auth (Debian default).
. /usr/local/lib/qaimg-credentials.sh

command -v mariadb >/dev/null 2>&1 || command -v mysql >/dev/null 2>&1 || exit 0
MYSQL="$(command -v mariadb || command -v mysql)"
systemctl is-active --quiet mariadb || systemctl start mariadb || exit 0

root_pw="$(qaimg_cred_or_random MARIADB_ROOT_PASSWORD)"
"$MYSQL" <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED BY '${root_pw}';
FLUSH PRIVILEGES;
SQL

app_db="$(qaimg_cred MARIADB_APP_DB || true)"
app_user="$(qaimg_cred MARIADB_APP_USER || true)"
if [ -n "$app_db" ]; then
    "$MYSQL" -e "CREATE DATABASE IF NOT EXISTS \`${app_db}\`;"
fi
if [ -n "$app_user" ]; then
    app_pw="$(qaimg_cred_or_random MARIADB_APP_PASSWORD)"
    "$MYSQL" <<SQL
CREATE USER IF NOT EXISTS '${app_user}'@'%' IDENTIFIED BY '${app_pw}';
ALTER USER '${app_user}'@'%' IDENTIFIED BY '${app_pw}';
${app_db:+GRANT ALL PRIVILEGES ON \`${app_db}\`.* TO '${app_user}'@'%';}
FLUSH PRIVILEGES;
SQL
fi
DROPIN
chmod 0755 /usr/local/lib/initial-provision.d/40-mariadb-credentials.sh
EOF
}

mariadb_provisioning_script | build_debian_flavor "$@"
