#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/qaimg-flavor-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

while IFS= read -r script; do
    bash -n "$script"
done < <(find "$PROJECT_ROOT/flavors" -type f -name '*.sh' -print)

while IFS= read -r -d '' build_script; do
    if [[ ! -x "$build_script" ]]; then
        printf 'Flavor builder is not executable: %s\n' "$build_script" >&2
        exit 1
    fi
    if [[ ! -f "$(dirname "$build_script")/README.md" ]]; then
        printf 'Flavor README is missing for: %s\n' "$build_script" >&2
        exit 1
    fi
done < <(find "$PROJECT_ROOT/flavors" -mindepth 3 -maxdepth 3 \
    -type f -name build.sh -print0)

AVAILABLE_FLAVORS="$("$PROJECT_ROOT/flavors/build.sh" --list)"

if ! grep -qx 'debian/nginx' <<< "$AVAILABLE_FLAVORS"; then
    printf 'Dispatcher did not list debian/nginx\n' >&2
    exit 1
fi

for flavor in nodejs wireguard docker grafana mariadb postgresql; do
    if ! grep -qx "debian/$flavor" <<< "$AVAILABLE_FLAVORS"; then
        printf 'Dispatcher did not list debian/%s\n' "$flavor" >&2
        exit 1
    fi
done

if ! grep -qx 'debian/minecraft-vanilla' <<< "$AVAILABLE_FLAVORS"; then
    printf 'Dispatcher did not list debian/minecraft-vanilla\n' >&2
    exit 1
fi

if ! grep -qx 'debian/minecraft-paper' <<< "$AVAILABLE_FLAVORS"; then
    printf 'Dispatcher did not list debian/minecraft-paper\n' >&2
    exit 1
fi

if ! grep -qx 'debian/palworld' <<< "$AVAILABLE_FLAVORS"; then
    printf 'Dispatcher did not list debian/palworld\n' >&2
    exit 1
fi

if grep -q 'common-minecraft' <<< "$AVAILABLE_FLAVORS"; then
    printf 'Dispatcher listed the shared Minecraft routines as a flavor\n' >&2
    exit 1
fi

for flavor in generic openclaw coolify supabase gitlab strapi prometheus elasticsearch; do
    if ! grep -qx "debian/$flavor" <<< "$AVAILABLE_FLAVORS"; then
        printf 'Dispatcher did not list debian/%s\n' "$flavor" >&2
        exit 1
    fi
done

printf 'test image\n' > "$TMP_ROOT/base.qcow2"

cat > "$TMP_ROOT/qimi" <<'EOF'
#!/bin/bash
set -euo pipefail
[[ "$1" == "exec" ]]
[[ -f "$2" ]]
[[ "$3" == "--nameserver" ]]
[[ "$5" == "--" ]]
[[ "$6" == "/bin/bash" ]]
[[ "$7" == "-c" ]]
printf '%s' "$8" > "$QIMI_CAPTURE_FILE"
EOF
chmod +x "$TMP_ROOT/qimi"

assert_initial_provision_base() {
    local script="$1"

    grep -Fq '/etc/sudoers.d/90-cloud-init-users' "$script"
    grep -Fq 'getent passwd 1000' "$script"
    grep -Fq 'HOME_TEMPLATE=/usr/local/cloud-init/home-template' "$script"
    grep -Fq 'DROPIN_DIR=/usr/local/lib/initial-provision.d' "$script"
    grep -Fq 'cp -a "$HOME_TEMPLATE/." "$login_home/"' "$script"
    grep -Fq 'for dropin in "$DROPIN_DIR"/*.sh; do' "$script"
    grep -Fq '/etc/systemd/system/initial-provision.service' "$script"
    grep -qx 'After=cloud-final.service' "$script"
    grep -qx 'Wants=cloud-final.service' "$script"
    grep -qx 'ConditionPathExists=!/var/lib/initial-provision/.done' "$script"
    grep -qx 'systemctl enable initial-provision.service' "$script"
}

assert_initial_provision_group() {
    local script="$1" group="$2"

    grep -qx "DROPIN_GROUP=$group" "$script"
    grep -Fq "/usr/local/lib/initial-provision.d/\${DROPIN_PRIORITY}-group-\${DROPIN_GROUP}.sh" \
        "$script"
    grep -Fq 'usermod -aG "\$group" "\$login_user"' "$script"
}

assert_credentials_base() {
    # Verifies the preconfigured-credentials library is baked in.
    local script="$1"

    grep -Fq '/usr/local/lib/qaimg-credentials.sh' "$script"
    grep -Fq 'QAIMG_CRED_DEPLOY=/etc/qaimg/credentials' "$script"
    grep -Fq 'QAIMG_CRED_DEFAULT=/usr/local/share/qaimg/credentials.default' "$script"
    grep -Fq 'QAIMG_CRED_GENERATED=/etc/qaimg/credentials.generated' "$script"
    grep -Fq 'qaimg_cred_or_random()' "$script"
}

assert_minecraft_common() {
    local script="$1"

    grep -q '^apt-get install -y ca-certificates curl jq openjdk-17-jre-headless screen$' \
        "$script"
    grep -q 'useradd --system --user-group' "$script"
    grep -q -- '--shell /usr/sbin/nologin minecraft' "$script"
    grep -q '^User=minecraft$' "$script"
    grep -q '^Group=minecraft$' "$script"
    grep -q '^Restart=always$' "$script"
    grep -q '^ExecStart=/usr/bin/screen -D -m -S minecraft /usr/bin/java -jar server.jar nogui$' \
        "$script"
    grep -Fq 'ExecStop=/bin/bash -c "/usr/bin/screen -S minecraft -p 0 -X stuff $$'"'"'stop\\r'"'"'; while /usr/bin/screen -S minecraft -Q windows >/dev/null 2>&1; do sleep 1; done"' \
        "$script"
    grep -q '^WantedBy=multi-user.target$' "$script"
    grep -q '^systemctl enable minecraft.service$' "$script"
    assert_initial_provision_base "$script"
    assert_initial_provision_group "$script" minecraft
    if grep -Eq 'User=debian|ExecStartPre=|server.properties|ufw|iptables' \
        "$script"; then
        printf 'Minecraft flavor contains unexpected customization\n' >&2
        exit 1
    fi
}

BASE_IMAGE="$TMP_ROOT/base.qcow2" \
OUTPUT_DIR="$TMP_ROOT/output" \
QIMI_PATH="$TMP_ROOT/qimi" \
QIMI_USE_SUDO=0 \
QIMI_CAPTURE_FILE="$TMP_ROOT/default-script" \
"$PROJECT_ROOT/flavors/debian/nginx/build.sh" bookworm

OUTPUT_IMAGE="$TMP_ROOT/output/bookworm-generic-amd64-qa.nginx.qcow2"
cmp "$TMP_ROOT/base.qcow2" "$OUTPUT_IMAGE"
grep -q '^apt-get install -y nginx$' "$TMP_ROOT/default-script"
if grep -Eq '/var/www|sites-available|EXTRA_PACKAGES|qemu-guest-agent nginx|nginx -t|systemctl' \
    "$TMP_ROOT/default-script"; then
    printf 'Nginx flavor contains unexpected customization\n' >&2
    exit 1
fi

while read -r flavor package; do
    capture_file="$TMP_ROOT/$flavor-script"
    expected_script="$TMP_ROOT/$flavor-expected-script"

    BASE_IMAGE="$TMP_ROOT/base.qcow2" \
    OUTPUT_DIR="$TMP_ROOT/output" \
    QIMI_PATH="$TMP_ROOT/qimi" \
    QIMI_USE_SUDO=0 \
    QIMI_CAPTURE_FILE="$capture_file" \
    "$PROJECT_ROOT/flavors/debian/$flavor/build.sh" bookworm

    cmp "$TMP_ROOT/base.qcow2" \
        "$TMP_ROOT/output/bookworm-generic-amd64-qa.$flavor.qcow2"
    printf 'set -e\nexport DEBIAN_FRONTEND=noninteractive\n\napt-get update\napt-get install -y %s' \
        "$package" > "$expected_script"
    cmp "$expected_script" "$capture_file"
done <<'EOF'
wireguard wireguard
EOF

# PostgreSQL and MariaDB now install extra tooling and a first-boot credential
# drop-in, so they are checked individually rather than by exact-script cmp.
BASE_IMAGE="$TMP_ROOT/base.qcow2" \
OUTPUT_DIR="$TMP_ROOT/output" \
QIMI_PATH="$TMP_ROOT/qimi" \
QIMI_USE_SUDO=0 \
QIMI_CAPTURE_FILE="$TMP_ROOT/postgresql-script" \
"$PROJECT_ROOT/flavors/debian/postgresql/build.sh" bookworm

cmp "$TMP_ROOT/base.qcow2" \
    "$TMP_ROOT/output/bookworm-generic-amd64-qa.postgresql.qcow2"
bash -n "$TMP_ROOT/postgresql-script"
grep -q '^apt-get install -y postgresql openssl$' "$TMP_ROOT/postgresql-script"
assert_credentials_base "$TMP_ROOT/postgresql-script"
assert_initial_provision_base "$TMP_ROOT/postgresql-script"
grep -Fq '/usr/local/lib/initial-provision.d/40-postgresql-credentials.sh' \
    "$TMP_ROOT/postgresql-script"
grep -Fq 'qaimg_cred_or_random POSTGRES_PASSWORD' "$TMP_ROOT/postgresql-script"
grep -Fq "ALTER USER postgres WITH PASSWORD" "$TMP_ROOT/postgresql-script"

BASE_IMAGE="$TMP_ROOT/base.qcow2" \
OUTPUT_DIR="$TMP_ROOT/output" \
QIMI_PATH="$TMP_ROOT/qimi" \
QIMI_USE_SUDO=0 \
QIMI_CAPTURE_FILE="$TMP_ROOT/mariadb-script" \
"$PROJECT_ROOT/flavors/debian/mariadb/build.sh" bookworm

cmp "$TMP_ROOT/base.qcow2" \
    "$TMP_ROOT/output/bookworm-generic-amd64-qa.mariadb.qcow2"
bash -n "$TMP_ROOT/mariadb-script"
grep -q '^apt-get install -y mariadb-server openssl$' "$TMP_ROOT/mariadb-script"
assert_credentials_base "$TMP_ROOT/mariadb-script"
assert_initial_provision_base "$TMP_ROOT/mariadb-script"
grep -Fq '/usr/local/lib/initial-provision.d/40-mariadb-credentials.sh' \
    "$TMP_ROOT/mariadb-script"
grep -Fq 'qaimg_cred_or_random MARIADB_ROOT_PASSWORD' "$TMP_ROOT/mariadb-script"

# Generic: the reusable first-run machinery only (no app, no service, no group).
BASE_IMAGE="$TMP_ROOT/base.qcow2" \
OUTPUT_DIR="$TMP_ROOT/output" \
QIMI_PATH="$TMP_ROOT/qimi" \
QIMI_USE_SUDO=0 \
QIMI_CAPTURE_FILE="$TMP_ROOT/generic-script" \
"$PROJECT_ROOT/flavors/debian/generic/build.sh" bookworm

cmp "$TMP_ROOT/base.qcow2" \
    "$TMP_ROOT/output/bookworm-generic-amd64-qa.generic.qcow2"
bash -n "$TMP_ROOT/generic-script"
grep -q '^apt-get install -y openssl$' "$TMP_ROOT/generic-script"
assert_credentials_base "$TMP_ROOT/generic-script"
assert_initial_provision_base "$TMP_ROOT/generic-script"
# It enables only initial-provision.service; no app service, user, or app drop-in.
if grep -E '^systemctl enable ' "$TMP_ROOT/generic-script" \
    | grep -qv 'initial-provision.service'; then
    printf 'Generic flavor must not enable an app service\n' >&2
    exit 1
fi
if grep -Eq 'useradd|DROPIN_GROUP=|/usr/local/lib/initial-provision.d/[0-9]+-' \
    "$TMP_ROOT/generic-script"; then
    printf 'Generic flavor must not install an app user or drop-in\n' >&2
    exit 1
fi

BASE_IMAGE="$TMP_ROOT/base.qcow2" \
OUTPUT_DIR="$TMP_ROOT/output" \
QIMI_PATH="$TMP_ROOT/qimi" \
QIMI_USE_SUDO=0 \
QIMI_CAPTURE_FILE="$TMP_ROOT/nodejs-script" \
"$PROJECT_ROOT/flavors/debian/nodejs/build.sh" bookworm

NODEJS_IMAGE="$TMP_ROOT/output/bookworm-generic-amd64-qa.nodejs.qcow2"
cmp "$TMP_ROOT/base.qcow2" "$NODEJS_IMAGE"
bash -n "$TMP_ROOT/nodejs-script"
grep -q '^NODE_MAJOR=24$' "$TMP_ROOT/nodejs-script"
grep -q '^apt-get install -y apt-transport-https ca-certificates curl gnupg$' \
    "$TMP_ROOT/nodejs-script"
grep -Fq 'https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key' \
    "$TMP_ROOT/nodejs-script"
grep -q '^URIs: https://deb.nodesource.com/node_${NODE_MAJOR}\.x$' \
    "$TMP_ROOT/nodejs-script"
grep -q '^Suites: nodistro$' "$TMP_ROOT/nodejs-script"
grep -Fq 'Architectures: $(dpkg --print-architecture)' "$TMP_ROOT/nodejs-script"
grep -q '^Signed-By: /usr/share/keyrings/nodesource.gpg$' "$TMP_ROOT/nodejs-script"
grep -q '^Pin: origin deb.nodesource.com$' "$TMP_ROOT/nodejs-script"
grep -q '^Pin-Priority: 600$' "$TMP_ROOT/nodejs-script"
grep -q '^apt-get install -y nodejs$' "$TMP_ROOT/nodejs-script"
if grep -Eq 'setup_[0-9]+\.x|nodejs\.org|/opt/|/srv/|systemctl|useradd' \
    "$TMP_ROOT/nodejs-script"; then
    printf 'Node.js flavor contains unexpected customization\n' >&2
    exit 1
fi

BASE_IMAGE="$TMP_ROOT/base.qcow2" \
OUTPUT_DIR="$TMP_ROOT/output" \
QIMI_PATH="$TMP_ROOT/qimi" \
QIMI_USE_SUDO=0 \
QIMI_CAPTURE_FILE="$TMP_ROOT/docker-script" \
"$PROJECT_ROOT/flavors/debian/docker/build.sh" bookworm

DOCKER_IMAGE="$TMP_ROOT/output/bookworm-generic-amd64-qa.docker.qcow2"
cmp "$TMP_ROOT/base.qcow2" "$DOCKER_IMAGE"
bash -n "$TMP_ROOT/docker-script"
grep -q '^apt-get install -y ca-certificates curl$' "$TMP_ROOT/docker-script"
grep -Fq 'https://download.docker.com/linux/debian/gpg' "$TMP_ROOT/docker-script"
grep -q '^Types: deb$' "$TMP_ROOT/docker-script"
grep -q '^URIs: https://download.docker.com/linux/debian$' "$TMP_ROOT/docker-script"
grep -q '^Suites: $VERSION_CODENAME$' "$TMP_ROOT/docker-script"
grep -Fq 'Architectures: $(dpkg --print-architecture)' "$TMP_ROOT/docker-script"
grep -q '^Signed-By: /etc/apt/keyrings/docker.asc$' "$TMP_ROOT/docker-script"
grep -q '^apt-get install -y docker-ce docker-ce-cli containerd.io \\$' \
    "$TMP_ROOT/docker-script"
grep -q '^    docker-buildx-plugin docker-compose-plugin$' "$TMP_ROOT/docker-script"
if grep -Eq 'docker\.io|get\.docker\.com|daemon\.json|groupadd|usermod|docker run|systemctl' \
    "$TMP_ROOT/docker-script"; then
    printf 'Docker flavor contains unexpected customization\n' >&2
    exit 1
fi

BASE_IMAGE="$TMP_ROOT/base.qcow2" \
OUTPUT_DIR="$TMP_ROOT/output" \
QIMI_PATH="$TMP_ROOT/qimi" \
QIMI_USE_SUDO=0 \
QIMI_CAPTURE_FILE="$TMP_ROOT/grafana-script" \
"$PROJECT_ROOT/flavors/debian/grafana/build.sh" bookworm

GRAFANA_IMAGE="$TMP_ROOT/output/bookworm-generic-amd64-qa.grafana.qcow2"
cmp "$TMP_ROOT/base.qcow2" "$GRAFANA_IMAGE"
bash -n "$TMP_ROOT/grafana-script"
grep -q '^apt-get install -y apt-transport-https software-properties-common wget$' \
    "$TMP_ROOT/grafana-script"
grep -Fq 'https://apt.grafana.com/gpg.key' "$TMP_ROOT/grafana-script"
grep -Fq 'deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main' \
    "$TMP_ROOT/grafana-script"
grep -q '^apt-get install -y grafana$' "$TMP_ROOT/grafana-script"
if grep -Eq 'grafana-enterprise| beta main|grafana\.ini|plugins|grafana-cli|systemctl' \
    "$TMP_ROOT/grafana-script"; then
    printf 'Grafana flavor contains unexpected customization\n' >&2
    exit 1
fi

BASE_IMAGE="$TMP_ROOT/base.qcow2" \
OUTPUT_DIR="$TMP_ROOT/output" \
QIMI_PATH="$TMP_ROOT/qimi" \
QIMI_USE_SUDO=0 \
QIMI_CAPTURE_FILE="$TMP_ROOT/minecraft-vanilla-script" \
"$PROJECT_ROOT/flavors/debian/minecraft-vanilla/build.sh" bookworm

VANILLA_IMAGE="$TMP_ROOT/output/bookworm-generic-amd64-qa.minecraft-vanilla.qcow2"
cmp "$TMP_ROOT/base.qcow2" "$VANILLA_IMAGE"
bash -n "$TMP_ROOT/minecraft-vanilla-script"
assert_minecraft_common "$TMP_ROOT/minecraft-vanilla-script"
grep -q '^MINECRAFT_VERSION=1.20.4$' "$TMP_ROOT/minecraft-vanilla-script"
grep -Fq 'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json' \
    "$TMP_ROOT/minecraft-vanilla-script"
grep -q 'sha1sum -c -$' "$TMP_ROOT/minecraft-vanilla-script"
if grep -q 'papermc.io' "$TMP_ROOT/minecraft-vanilla-script"; then
    printf 'Minecraft Vanilla flavor contains Paper provisioning\n' >&2
    exit 1
fi

BASE_IMAGE="$TMP_ROOT/base.qcow2" \
OUTPUT_DIR="$TMP_ROOT/output" \
QIMI_PATH="$TMP_ROOT/qimi" \
QIMI_USE_SUDO=0 \
QIMI_CAPTURE_FILE="$TMP_ROOT/minecraft-paper-script" \
"$PROJECT_ROOT/flavors/debian/minecraft-paper/build.sh" bookworm

PAPER_IMAGE="$TMP_ROOT/output/bookworm-generic-amd64-qa.minecraft-paper.qcow2"
cmp "$TMP_ROOT/base.qcow2" "$PAPER_IMAGE"
bash -n "$TMP_ROOT/minecraft-paper-script"
assert_minecraft_common "$TMP_ROOT/minecraft-paper-script"
grep -q '^MINECRAFT_VERSION=1.20.4$' "$TMP_ROOT/minecraft-paper-script"
grep -q '^PAPER_BUILD=499$' "$TMP_ROOT/minecraft-paper-script"
grep -Fq "PAPER_USER_AGENT='qaimg-builder/1.0 (https://github.com/Alex4386/qaimg-builder)'" \
    "$TMP_ROOT/minecraft-paper-script"
grep -Fq 'https://fill.papermc.io/v3/projects/paper/versions/$MINECRAFT_VERSION/builds/$PAPER_BUILD' \
    "$TMP_ROOT/minecraft-paper-script"
grep -Fq "jq -e '.channel == \"STABLE\"'" "$TMP_ROOT/minecraft-paper-script"
grep -q 'sha256sum -c -$' "$TMP_ROOT/minecraft-paper-script"
if grep -q 'piston-meta.mojang.com' "$TMP_ROOT/minecraft-paper-script"; then
    printf 'Minecraft Paper flavor contains Vanilla provisioning\n' >&2
    exit 1
fi

BASE_IMAGE="$TMP_ROOT/base.qcow2" \
OUTPUT_DIR="$TMP_ROOT/output" \
QIMI_PATH="$TMP_ROOT/qimi" \
QIMI_USE_SUDO=0 \
FLAVOR_RESIZE=0 \
QIMI_CAPTURE_FILE="$TMP_ROOT/palworld-script" \
"$PROJECT_ROOT/flavors/debian/palworld/build.sh" bookworm

PALWORLD_IMAGE="$TMP_ROOT/output/bookworm-generic-amd64-qa.palworld.qcow2"
cmp "$TMP_ROOT/base.qcow2" "$PALWORLD_IMAGE"
bash -n "$TMP_ROOT/palworld-script"
grep -q '^STEAM_APP_ID=2394010$' "$TMP_ROOT/palworld-script"
grep -q '^apt-get install -y steamcmd$' "$TMP_ROOT/palworld-script"
grep -q 'useradd --system --user-group' "$TMP_ROOT/palworld-script"
grep -q -- '--shell /usr/sbin/nologin palworld' "$TMP_ROOT/palworld-script"
grep -Fq '+app_update "$STEAM_APP_ID" validate' "$TMP_ROOT/palworld-script"
grep -Fq 'ExecStart=/var/lib/palworld/PalServer.sh' "$TMP_ROOT/palworld-script"
grep -q '^User=palworld$' "$TMP_ROOT/palworld-script"
grep -q '^systemctl enable palworld.service$' "$TMP_ROOT/palworld-script"
assert_initial_provision_base "$TMP_ROOT/palworld-script"
assert_initial_provision_group "$TMP_ROOT/palworld-script" palworld

build_flavor() {
    local flavor="$1"
    # FLAVOR_RESIZE=0 keeps the stub qcow2 (a text file) intact: flavors that set
    # FLAVOR_MIN_DISK_GB log a skip instead of running qemu-img. Build logs are
    # captured to <flavor>-log for resize assertions.
    BASE_IMAGE="$TMP_ROOT/base.qcow2" \
    OUTPUT_DIR="$TMP_ROOT/output" \
    QIMI_PATH="$TMP_ROOT/qimi" \
    QIMI_USE_SUDO=0 \
    FLAVOR_RESIZE=0 \
    QIMI_CAPTURE_FILE="$TMP_ROOT/$flavor-script" \
    "$PROJECT_ROOT/flavors/debian/$flavor/build.sh" bookworm \
        > "$TMP_ROOT/$flavor-log" 2>&1
    cmp "$TMP_ROOT/base.qcow2" \
        "$TMP_ROOT/output/bookworm-generic-amd64-qa.$flavor.qcow2"
    bash -n "$TMP_ROOT/$flavor-script"
}

# Prometheus: Debian package + enabled service + login-user group.
build_flavor prometheus
grep -q '^apt-get install -y prometheus$' "$TMP_ROOT/prometheus-script"
grep -qx 'systemctl enable prometheus.service' "$TMP_ROOT/prometheus-script"
assert_initial_provision_base "$TMP_ROOT/prometheus-script"
assert_initial_provision_group "$TMP_ROOT/prometheus-script" prometheus
if grep -Eq 'github.com/prometheus|/usr/local/bin/prometheus|useradd|tar ' \
    "$TMP_ROOT/prometheus-script"; then
    printf 'Prometheus flavor contains unexpected customization\n' >&2
    exit 1
fi

# Elasticsearch: Elastic 8.x apt repo + enabled service + login-user group.
build_flavor elasticsearch
grep -Fq 'https://artifacts.elastic.co/GPG-KEY-elasticsearch' \
    "$TMP_ROOT/elasticsearch-script"
grep -q '^URIs: https://artifacts.elastic.co/packages/8.x/apt$' \
    "$TMP_ROOT/elasticsearch-script"
grep -q '^Suites: stable$' "$TMP_ROOT/elasticsearch-script"
grep -q '^Signed-By: /usr/share/keyrings/elasticsearch-keyring.gpg$' \
    "$TMP_ROOT/elasticsearch-script"
grep -q '^apt-get install -y elasticsearch$' "$TMP_ROOT/elasticsearch-script"
grep -qx 'systemctl enable elasticsearch.service' \
    "$TMP_ROOT/elasticsearch-script"
assert_initial_provision_base "$TMP_ROOT/elasticsearch-script"
assert_initial_provision_group "$TMP_ROOT/elasticsearch-script" elasticsearch
assert_credentials_base "$TMP_ROOT/elasticsearch-script"
grep -Fq '/usr/local/lib/initial-provision.d/40-elasticsearch-credentials.sh' \
    "$TMP_ROOT/elasticsearch-script"
grep -Fq 'qaimg_cred ELASTIC_PASSWORD' "$TMP_ROOT/elasticsearch-script"
if grep -Eq 'packages/9.x|elasticsearch-[0-9]|dpkg -i|apt-key' \
    "$TMP_ROOT/elasticsearch-script"; then
    printf 'Elasticsearch flavor contains unexpected customization\n' >&2
    exit 1
fi

# GitLab CE: gitlab-ce apt repo, deferred reconfigure drop-in (no EXTERNAL_URL).
build_flavor gitlab
grep -Fq 'https://packages.gitlab.com/gitlab/gitlab-ce/gpgkey' \
    "$TMP_ROOT/gitlab-script"
grep -q '^URIs: https://packages.gitlab.com/gitlab/gitlab-ce/debian/$' \
    "$TMP_ROOT/gitlab-script"
grep -q '^Suites: $VERSION_CODENAME$' "$TMP_ROOT/gitlab-script"
grep -q '^apt-get install -y gitlab-ce$' "$TMP_ROOT/gitlab-script"
grep -Fq 'gitlab-ctl reconfigure' "$TMP_ROOT/gitlab-script"
grep -Fq '/usr/local/lib/initial-provision.d/30-gitlab-reconfigure.sh' \
    "$TMP_ROOT/gitlab-script"
assert_initial_provision_base "$TMP_ROOT/gitlab-script"
assert_credentials_base "$TMP_ROOT/gitlab-script"
grep -Fq 'qaimg_cred GITLAB_EXTERNAL_URL' "$TMP_ROOT/gitlab-script"
grep -Fq 'qaimg_cred GITLAB_ROOT_PASSWORD' "$TMP_ROOT/gitlab-script"
# GitLab declares a build-time minimum disk size; with FLAVOR_RESIZE=0 the runner
# logs a skip that names the requested size.
grep -Fq 'Resize to 8G requested but FLAVOR_RESIZE!=1' "$TMP_ROOT/gitlab-log"
# The build-time install must still NOT bake a fixed external_url in.
if grep -Eq 'EXTERNAL_URL=|script.deb.sh' "$TMP_ROOT/gitlab-script"; then
    printf 'GitLab flavor contains unexpected customization\n' >&2
    exit 1
fi

# Strapi: NodeSource Node.js + scaffolded project + enabled service + group.
build_flavor strapi
grep -q '^NODE_MAJOR=22$' "$TMP_ROOT/strapi-script"
grep -Fq 'https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key' \
    "$TMP_ROOT/strapi-script"
grep -q '^apt-get install -y nodejs$' "$TMP_ROOT/strapi-script"
grep -q 'useradd --system --user-group' "$TMP_ROOT/strapi-script"
grep -q -- '--shell /usr/sbin/nologin strapi' "$TMP_ROOT/strapi-script"
grep -Fq 'create-strapi-app@latest' "$TMP_ROOT/strapi-script"
grep -q '^User=strapi$' "$TMP_ROOT/strapi-script"
grep -q '^systemctl enable strapi.service$' "$TMP_ROOT/strapi-script"
assert_initial_provision_base "$TMP_ROOT/strapi-script"
assert_initial_provision_group "$TMP_ROOT/strapi-script" strapi
assert_credentials_base "$TMP_ROOT/strapi-script"
grep -Fq '/usr/local/lib/initial-provision.d/40-strapi-secrets.sh' \
    "$TMP_ROOT/strapi-script"
grep -Fq 'qaimg_cred_or_random STRAPI_ADMIN_JWT_SECRET' "$TMP_ROOT/strapi-script"
grep -Fq 'set_kv ADMIN_JWT_SECRET' "$TMP_ROOT/strapi-script"
if grep -Eq 'pm2|nginx|ufw' "$TMP_ROOT/strapi-script"; then
    printf 'Strapi flavor contains unexpected customization\n' >&2
    exit 1
fi

# Coolify: bake Docker + defer official installer to first boot + docker group.
build_flavor coolify
grep -Fq 'https://download.docker.com/linux/debian/gpg' "$TMP_ROOT/coolify-script"
grep -q '^apt-get install -y docker-ce docker-ce-cli containerd.io \\$' \
    "$TMP_ROOT/coolify-script"
grep -qx 'systemctl enable docker.service' "$TMP_ROOT/coolify-script"
grep -Fq 'https://cdn.coollabs.io/coolify/install.sh' "$TMP_ROOT/coolify-script"
grep -Fq '/usr/local/lib/initial-provision.d/40-coolify-install.sh' \
    "$TMP_ROOT/coolify-script"
assert_initial_provision_base "$TMP_ROOT/coolify-script"
assert_initial_provision_group "$TMP_ROOT/coolify-script" docker
if grep -Eq 'get.docker.com|docker.io' "$TMP_ROOT/coolify-script"; then
    printf 'Coolify flavor contains unexpected customization\n' >&2
    exit 1
fi

# Supabase: bake Docker + compose stack + enabled service + secrets drop-in.
build_flavor supabase
grep -Fq 'https://download.docker.com/linux/debian/gpg' "$TMP_ROOT/supabase-script"
grep -Fq 'https://github.com/supabase/supabase.git' "$TMP_ROOT/supabase-script"
grep -Fq 'sparse-checkout set docker' "$TMP_ROOT/supabase-script"
grep -q 'useradd --system --user-group' "$TMP_ROOT/supabase-script"
grep -q -- '--shell /usr/sbin/nologin supabase' "$TMP_ROOT/supabase-script"
grep -Fq 'docker compose up -d --wait' "$TMP_ROOT/supabase-script"
grep -q '^systemctl enable supabase.service$' "$TMP_ROOT/supabase-script"
grep -Fq '/usr/local/lib/initial-provision.d/40-supabase-secrets.sh' \
    "$TMP_ROOT/supabase-script"
assert_initial_provision_base "$TMP_ROOT/supabase-script"
assert_initial_provision_group "$TMP_ROOT/supabase-script" docker
assert_credentials_base "$TMP_ROOT/supabase-script"
grep -Fq 'qaimg_cred_or_random POSTGRES_PASSWORD' "$TMP_ROOT/supabase-script"
grep -Fq 'qaimg_cred_or_random JWT_SECRET' "$TMP_ROOT/supabase-script"
if grep -Eq 'supabase.link/setup.sh|get.docker.com' "$TMP_ROOT/supabase-script"; then
    printf 'Supabase flavor contains unexpected customization\n' >&2
    exit 1
fi

# OpenClaw: Node.js AI assistant gateway CLI, per-user daemon, NO system service.
build_flavor openclaw
grep -q '^NODE_MAJOR=24$' "$TMP_ROOT/openclaw-script"
grep -Fq 'https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key' \
    "$TMP_ROOT/openclaw-script"
grep -q '^URIs: https://deb.nodesource.com/node_${NODE_MAJOR}\.x$' \
    "$TMP_ROOT/openclaw-script"
grep -q '^apt-get install -y nodejs$' "$TMP_ROOT/openclaw-script"
grep -q '^npm install -g openclaw@latest$' "$TMP_ROOT/openclaw-script"
grep -Fq '/usr/local/lib/initial-provision.d/30-openclaw-linger.sh' \
    "$TMP_ROOT/openclaw-script"
grep -Fq 'loginctl enable-linger "$login_user"' "$TMP_ROOT/openclaw-script"
grep -Fq '/usr/local/cloud-init/home-template/README-openclaw.md' \
    "$TMP_ROOT/openclaw-script"
assert_initial_provision_base "$TMP_ROOT/openclaw-script"
# Must not carry any Captain Claw / SDL2 game-build remnants.
if grep -Eiq 'CLAW\.REZ|libsdl|cmake|/usr/local/games|openclaw/openclaw\.git' \
    "$TMP_ROOT/openclaw-script"; then
    printf 'OpenClaw flavor contains stale game-build content\n' >&2
    exit 1
fi
# Must not install a system-wide service for openclaw.
if grep -Eq 'systemctl enable openclaw|/etc/systemd/system/openclaw' \
    "$TMP_ROOT/openclaw-script"; then
    printf 'OpenClaw flavor must not install a systemd system service\n' >&2
    exit 1
fi

for readme in \
    "$PROJECT_ROOT/flavors/debian/minecraft-vanilla/README.md" \
    "$PROJECT_ROOT/flavors/debian/minecraft-paper/README.md"; do
    grep -Fq "sudo -u minecraft env SHELL=/bin/sh script -q -c 'screen -r minecraft' /dev/null" \
        "$readme"
done

printf 'Flavor tests passed.\n'
