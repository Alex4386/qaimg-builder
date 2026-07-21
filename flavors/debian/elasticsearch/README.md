# Debian Elasticsearch flavor

This flavor installs [Elasticsearch](https://www.elastic.co/elasticsearch) 8.x
from Elastic's official APT repository and enables it as a systemd service.

## Build

```bash
./flavors/build.sh debian elasticsearch bookworm
```

The output is `bookworm-generic-amd64-qa.elasticsearch.qcow2`.

The service is enabled in the image and runs as the dedicated, non-login
`elasticsearch` system user created by the Debian package.

## Ports

- `9200/tcp` REST API
- `9300/tcp` transport (node-to-node)

By default Elasticsearch 8.x binds to localhost and enables the security layer
(TLS and authentication) on first start. Keep these ports closed on your
security group or firewall unless you have configured network access
deliberately.

## Service

```bash
sudo systemctl status elasticsearch
sudo systemctl restart elasticsearch
sudo systemctl stop elasticsearch
```

## Configuration

- `/etc/elasticsearch/elasticsearch.yml` main configuration
- `/etc/elasticsearch/jvm.options.d/` JVM heap and options
- `/var/lib/elasticsearch` data
- `/var/log/elasticsearch` logs

On first start, Elasticsearch 8.x auto-generates security credentials. Reset the
`elastic` superuser password with:

```bash
sudo /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic
```

## Login user access

The default login user does not exist when the image is built. A generic oneshot
`initial-provision.service` runs at first boot (ordered `After=cloud-final.service`)
and adds the cloud-init login user to the `elasticsearch` group via a drop-in in
`/usr/local/lib/initial-provision.d`, giving it access to the configuration under
`/etc/elasticsearch`. Re-log in after the first boot for the new group to take
effect. See [`flavors/README.md`](../../README.md) for the full first-boot
provisioning mechanism.

## Caveat

The `elasticsearch` package is published for `amd64` and `arm64` only.
