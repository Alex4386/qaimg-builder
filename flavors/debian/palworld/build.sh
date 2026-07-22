#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/../../lib/debian.sh"

palworld_provisioning_script() {
    cat <<'FLAVOR_SCRIPT'
set -e
export DEBIAN_FRONTEND=noninteractive

PALWORLD_DIR=/var/lib/palworld
STEAM_APP_ID=2394010

apt-get update
apt-get install -y ca-certificates curl

# steamcmd ships in Debian's contrib/non-free components. Debian cloud images
# use the deb822 sources format, so enable the components there directly rather
# than relying on apt-add-repository (which does not edit *.sources reliably).
enable_components() {
    if [ -f /etc/apt/sources.list.d/debian.sources ]; then
        sed -i -E \
            's/^Components:.*/Components: main contrib non-free non-free-firmware/' \
            /etc/apt/sources.list.d/debian.sources
    fi
    if [ -f /etc/apt/sources.list ]; then
        sed -i -E \
            '/ (main|contrib|non-free)/ s/[[:space:]]+main([[:space:]].*)?$/ main contrib non-free non-free-firmware/' \
            /etc/apt/sources.list
    fi
}
enable_components

dpkg --add-architecture i386
apt-get update
echo steam steam/question select "I AGREE" | debconf-set-selections
echo steam steam/license note '' | debconf-set-selections
apt-get install -y steamcmd

if ! id -u palworld >/dev/null 2>&1; then
    useradd --system --user-group --home-dir "$PALWORLD_DIR" \
        --shell /usr/sbin/nologin palworld
fi
install -d -o palworld -g palworld "$PALWORLD_DIR"

# SteamCMD bootstraps into $HOME/.steam, so HOME must point at the palworld
# home. Run login shell env (-H sets HOME to the target user's home).
#
# Prime SteamCMD once so it self-updates and writes its config before any real
# work. On a fresh client, issuing +force_install_dir/+app_update in the same
# invocation as the very first bootstrap fails with "Missing configuration"
# (exit 8), which is exactly what CI hit.
sudo -u palworld -H env HOME="$PALWORLD_DIR" /usr/games/steamcmd +quit

# +force_install_dir MUST come before +login; SteamCMD refuses to install with
# "Please use force_install_dir before logon!" and aborts with exit 8 when the
# install dir is set after login.
sudo -u palworld -H env HOME="$PALWORLD_DIR" /usr/games/steamcmd \
    +@sSteamCmdForcePlatformType linux \
    +force_install_dir "$PALWORLD_DIR" \
    +login anonymous \
    +app_update "$STEAM_APP_ID" validate \
    +quit

test -x "$PALWORLD_DIR/PalServer.sh"

install -d -o palworld -g palworld "$PALWORLD_DIR/.steam/sdk64"
if [ -f "$PALWORLD_DIR/linux64/steamclient.so" ]; then
    install -o palworld -g palworld -m 0644 \
        "$PALWORLD_DIR/linux64/steamclient.so" \
        "$PALWORLD_DIR/.steam/sdk64/steamclient.so"
fi
chown -R palworld:palworld "$PALWORLD_DIR"

cat > /etc/systemd/system/palworld.service <<'UNIT'
[Unit]
Description=Palworld Dedicated Server
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=palworld
Group=palworld
WorkingDirectory=/var/lib/palworld
Environment=HOME=/var/lib/palworld
Environment=LD_LIBRARY_PATH=/var/lib/palworld/linux64
ExecStart=/var/lib/palworld/PalServer.sh -useperfthreads -NoAsyncLoadingThread -UseMultithreadForDS
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

systemctl enable palworld.service
FLAVOR_SCRIPT

    flavor_initial_provision_base_snippet
    flavor_initial_provision_group_dropin palworld
}

# The Palworld dedicated server is ~8 GB installed, and SteamCMD needs extra
# staging space while downloading, so the ~3 GB base image is far too small.
# Grow the build image (operator can override with FLAVOR_MIN_DISK_GB).
export FLAVOR_MIN_DISK_GB="${FLAVOR_MIN_DISK_GB:-16}"

palworld_provisioning_script | build_debian_flavor "$@"
