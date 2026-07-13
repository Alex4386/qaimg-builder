# Debian WireGuard flavor

This flavor installs Debian's stock `wireguard` package. It does not create
keys, tunnel configuration, firewall rules, or network interfaces.

## Build

```bash
./flavors/build.sh debian wireguard bookworm
```

The output is `bookworm-generic-amd64-qa.wireguard.qcow2`.

Verify the installed tools with:

```bash
wg --version
```
