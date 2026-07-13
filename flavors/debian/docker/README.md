# Debian Docker flavor

This flavor installs Docker Engine using Docker's
[official Debian repository](https://docs.docker.com/engine/install/debian/).
It includes Docker Engine, the Docker CLI, containerd, Buildx, and the Docker
Compose plugin. It does not change daemon settings, modify users or groups, or
create containers.

## Build

```bash
./flavors/build.sh debian docker bookworm
```

The output is `bookworm-generic-amd64-qa.docker.qcow2`.

Check the packaged service with:

```bash
sudo systemctl status docker
```
