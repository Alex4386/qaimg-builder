# Debian MariaDB flavor

This flavor installs the stock Debian `mariadb-server` package and applies
preconfigured credentials on first boot.

```bash
./flavors/build.sh debian mariadb bookworm
```

The output is `bookworm-generic-amd64-qa.mariadb.qcow2`.

## Credentials

On first boot the `40-mariadb-credentials.sh` drop-in sets the `root` password
and, optionally, creates an application database and user. Values come from
`/etc/qaimg/credentials` (delivered via cloud-init, see
[`examples/vendor.yaml`](../../../examples/vendor.yaml)); anything omitted is
generated randomly and persisted to `/etc/qaimg/credentials.generated`.

| Key | Purpose |
|-----|---------|
| `MARIADB_ROOT_PASSWORD` | `root@localhost` password (random if unset) |
| `MARIADB_APP_DB` | optional application database to create |
| `MARIADB_APP_USER` | optional application user (`'user'@'%'`) to create |
| `MARIADB_APP_PASSWORD` | password for the application user (random if unset) |

### Example: provision passwords via cloud-init

Pass this as the instance's vendor-data or user-data at deploy time:

```yaml
#cloud-config
write_files:
  - path: /etc/qaimg/credentials
    owner: root:root
    permissions: '0600'
    content: |
      MARIADB_ROOT_PASSWORD=super-secret-root
      MARIADB_APP_DB=appdb
      MARIADB_APP_USER=appuser
      MARIADB_APP_PASSWORD=super-secret-app
```

On first boot the `root` password is set and `appdb`/`appuser` are created.
Verify with:

```bash
mariadb -u appuser -p'super-secret-app' appdb -e 'SELECT 1;'
```

Note: setting a `root` password switches `root` to password auth; the local
`root` socket login (unix_socket) continues to work for the system root user.
See [`flavors/README.md`](../../README.md) for the full credentials mechanism.
