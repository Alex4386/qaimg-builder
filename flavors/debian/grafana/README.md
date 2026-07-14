# Debian Grafana flavor

This flavor installs Grafana OSS from Grafana's stable APT repository. It does
not install Grafana Enterprise or beta releases, and it does not change Grafana
configuration or install plugins.

## Build

```bash
./flavors/build.sh debian grafana bookworm
```

The output is `bookworm-generic-amd64-qa.grafana.qcow2`.

Manage the packaged service with:

```bash
sudo systemctl enable --now grafana-server
sudo systemctl status grafana-server
```
