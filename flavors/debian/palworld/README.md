# Debian Palworld flavor

This flavor installs a Palworld dedicated server (Steam AppID `2394010`) via
SteamCMD and enables it as a systemd service.

## Build

```bash
./flavors/build.sh debian palworld bookworm
```

The output is `bookworm-generic-amd64-qa.palworld.qcow2`.

The server runs as the dedicated, non-login `palworld` system user. Server data
and configuration live in `/var/lib/palworld`.

The dedicated server is several GB, so the build grows the image to
`FLAVOR_MIN_DISK_GB` (default 16 GiB) before the SteamCMD download; override it
if needed, e.g. `FLAVOR_MIN_DISK_GB=24 ./flavors/build.sh debian palworld bookworm`.

## Ports

Palworld uses UDP by default:

- `8211/udp` game port
- `27015/udp` Steam query port

Open these on your platform's security group or firewall for players to connect.

## Configuration

Edit the server settings, then restart the service:

```text
/var/lib/palworld/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini
```

The stock defaults ship in
`/var/lib/palworld/DefaultPalWorldSettings.ini`. Copy the `[/Script/Pal.PalGameWorldSettings]`
block into `PalWorldSettings.ini` to override values.

## Service

```bash
sudo systemctl status palworld
sudo systemctl restart palworld
sudo systemctl stop palworld
```

## Login user access

The default login user does not exist when the image is built. A generic oneshot
`initial-provision.service` runs at first boot (ordered `After=cloud-final.service`)
and adds the cloud-init login user to the `palworld` group via a drop-in in
`/usr/local/lib/initial-provision.d`, giving it access to the server files under
`/var/lib/palworld`. Re-log in after the first boot for the new group to take
effect. See [`flavors/README.md`](../../README.md) for the full first-boot
provisioning mechanism.

## Updating

Re-run SteamCMD to pull the latest server build:

```bash
sudo systemctl stop palworld
sudo -u palworld -H env HOME=/var/lib/palworld /usr/games/steamcmd \
    +@sSteamCmdForcePlatformType linux \
    +force_install_dir /var/lib/palworld \
    +login anonymous +app_update 2394010 validate +quit
sudo systemctl start palworld
```

Building and using this image implies acceptance of the
[Steam Subscriber Agreement](https://store.steampowered.com/subscriber_agreement/).
