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

for flavor in nodejs wireguard docker; do
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

if grep -q 'common-minecraft' <<< "$AVAILABLE_FLAVORS"; then
    printf 'Dispatcher listed the shared Minecraft routines as a flavor\n' >&2
    exit 1
fi

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
    if grep -Eq 'User=debian|cloud-final|ExecStartPre=|chown -R|server.properties|ufw|iptables' \
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

for readme in \
    "$PROJECT_ROOT/flavors/debian/minecraft-vanilla/README.md" \
    "$PROJECT_ROOT/flavors/debian/minecraft-paper/README.md"; do
    grep -Fq "sudo -u minecraft env SHELL=/bin/sh script -q -c 'screen -r minecraft' /dev/null" \
        "$readme"
done

printf 'Flavor tests passed.\n'
