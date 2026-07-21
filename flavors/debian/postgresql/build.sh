#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/../../lib/debian.sh"

postgresql_provisioning_script() {
    cat <<'FLAVOR_SCRIPT'
set -e
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y postgresql openssl
FLAVOR_SCRIPT

    flavor_credentials_base_snippet
    flavor_initial_provision_base_snippet

    cat <<'EOF'
cat > /usr/local/lib/initial-provision.d/40-postgresql-credentials.sh <<'DROPIN'
#!/bin/bash
set -e
# Apply preconfigured credentials on first boot: set the postgres superuser
# password (from POSTGRES_PASSWORD, else a persisted random one) and optionally
# create an application database + role.
. /usr/local/lib/qaimg-credentials.sh

command -v psql >/dev/null 2>&1 || exit 0
systemctl is-active --quiet postgresql || systemctl start postgresql || exit 0

pg_pw="$(qaimg_cred_or_random POSTGRES_PASSWORD)"
sudo -u postgres psql -v ON_ERROR_STOP=1 -c \
    "ALTER USER postgres WITH PASSWORD '${pg_pw}';"

app_db="$(qaimg_cred POSTGRES_APP_DB || true)"
app_user="$(qaimg_cred POSTGRES_APP_USER || true)"
if [ -n "$app_user" ]; then
    app_pw="$(qaimg_cred_or_random POSTGRES_APP_PASSWORD)"
    if ! sudo -u postgres psql -tAc \
        "SELECT 1 FROM pg_roles WHERE rolname='${app_user}'" | grep -q 1; then
        sudo -u postgres psql -v ON_ERROR_STOP=1 -c \
            "CREATE ROLE \"${app_user}\" LOGIN PASSWORD '${app_pw}';"
    else
        sudo -u postgres psql -v ON_ERROR_STOP=1 -c \
            "ALTER ROLE \"${app_user}\" LOGIN PASSWORD '${app_pw}';"
    fi
fi
if [ -n "$app_db" ]; then
    if ! sudo -u postgres psql -tAc \
        "SELECT 1 FROM pg_database WHERE datname='${app_db}'" | grep -q 1; then
        sudo -u postgres createdb ${app_user:+-O "$app_user"} "$app_db"
    fi
fi
DROPIN
chmod 0755 /usr/local/lib/initial-provision.d/40-postgresql-credentials.sh
EOF
}

postgresql_provisioning_script | build_debian_flavor "$@"
