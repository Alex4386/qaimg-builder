# Debian Prometheus flavor

This flavor installs the [Prometheus](https://prometheus.io/) monitoring system
from Debian's official repository and enables it as a systemd service.

## Build

```bash
./flavors/build.sh debian prometheus bookworm
```

The output is `bookworm-generic-amd64-qa.prometheus.qcow2`.

The service is enabled in the image and runs as the dedicated, non-login
`prometheus` system user created by the Debian package.

## Ports

- `9090/tcp` Prometheus web UI and API

Prometheus ships with no authentication. Keep `9090/tcp` closed on your
security group or firewall, or place Prometheus behind an authenticated reverse
proxy before exposing it.

## Service

```bash
sudo systemctl status prometheus
sudo systemctl restart prometheus
sudo systemctl stop prometheus
```

## Configuration

The Debian package stores its files in the standard locations:

- `/etc/prometheus/prometheus.yml` main configuration
- `/etc/default/prometheus` startup flags (e.g. listen address)
- `/var/lib/prometheus` time-series data

Reload after editing the configuration:

```bash
sudo systemctl reload prometheus
```

## Login user access

The default login user does not exist when the image is built. A generic oneshot
`initial-provision.service` runs at first boot (ordered `After=cloud-final.service`)
and adds the cloud-init login user to the `prometheus` group via a drop-in in
`/usr/local/lib/initial-provision.d`, giving it access to the configuration and
data. Re-log in after the first boot for the new group to take effect. See
[`flavors/README.md`](../../README.md) for the full first-boot provisioning
mechanism.
