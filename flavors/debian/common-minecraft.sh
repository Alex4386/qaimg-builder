#!/bin/bash

minecraft_provisioning_script() {
    local server_script
    server_script="$(cat)"

    cat <<'COMMON_PREFIX'
set -e
export DEBIAN_FRONTEND=noninteractive

MINECRAFT_DIR=/var/lib/minecraft

apt-get update
apt-get install -y ca-certificates curl jq openjdk-17-jre-headless screen

if ! id -u minecraft >/dev/null 2>&1; then
    useradd --system --user-group --home-dir "$MINECRAFT_DIR" \
        --shell /usr/sbin/nologin minecraft
fi
install -d -o minecraft -g minecraft "$MINECRAFT_DIR"
COMMON_PREFIX

    printf '%s\n' "$server_script"

    cat <<'COMMON_SUFFIX'
test -s "$MINECRAFT_DIR/server.jar"
chown minecraft:minecraft "$MINECRAFT_DIR/server.jar"

printf 'eula=true\n' > "$MINECRAFT_DIR/eula.txt"
chown minecraft:minecraft "$MINECRAFT_DIR/eula.txt"

cat > /etc/systemd/system/minecraft.service <<'UNIT'
[Unit]
Description=Minecraft Server
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=minecraft
Group=minecraft
WorkingDirectory=/var/lib/minecraft
ExecStart=/usr/bin/screen -D -m -S minecraft /usr/bin/java -jar server.jar nogui
ExecStop=/bin/bash -c "/usr/bin/screen -S minecraft -p 0 -X stuff $$'stop\\r'; while /usr/bin/screen -S minecraft -Q windows >/dev/null 2>&1; do sleep 1; done"
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

systemctl enable minecraft.service
COMMON_SUFFIX

    flavor_initial_provision_base_snippet
    flavor_initial_provision_group_dropin minecraft
}
