# Debian Minecraft Paper flavor

This flavor installs Paper for Minecraft Java Edition 1.20.4, stable build 499,
with OpenJDK 17 and GNU Screen.

## Build

```bash
./flavors/build.sh debian minecraft-paper bookworm
```

The output is `bookworm-generic-amd64-qa.minecraft-paper.qcow2`.

The service is enabled in the image and runs as the dedicated, non-login
`minecraft` system user. Server data is stored in `/var/lib/minecraft`, Paper
plugins belong in `/var/lib/minecraft/plugins`, and the default server port is
`25565`.

## Service and console

```bash
sudo systemctl status minecraft
sudo systemctl restart minecraft
sudo systemctl stop minecraft
```

Attach to the server console from the cloud-init user with:

```bash
sudo -u minecraft env SHELL=/bin/sh script -q -c 'screen -r minecraft' /dev/null
```

Press `Ctrl-A`, then `D`, to detach without stopping the server.

The flavor writes `eula=true` to `/var/lib/minecraft/eula.txt`. Build and use
this image only if you accept the
[Minecraft End User License Agreement](https://www.minecraft.net/eula).
