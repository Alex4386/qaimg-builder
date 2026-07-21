# Debian PostgreSQL flavor

This flavor installs the stock Debian `postgresql` package and applies
preconfigured credentials on first boot.

```bash
./flavors/build.sh debian postgresql bookworm
```

The output is `bookworm-generic-amd64-qa.postgresql.qcow2`.

## Credentials

On first boot the `40-postgresql-credentials.sh` drop-in sets the `postgres`
superuser password and, optionally, creates an application database and role.
Values come from `/etc/qaimg/credentials` (delivered via cloud-init, see
[`examples/vendor.yaml`](../../../examples/vendor.yaml)); anything omitted is
generated randomly and persisted to `/etc/qaimg/credentials.generated`.

| Key | Purpose |
|-----|---------|
| `POSTGRES_PASSWORD` | `postgres` superuser password (random if unset) |
| `POSTGRES_APP_DB` | optional application database to create |
| `POSTGRES_APP_USER` | optional application role to create |
| `POSTGRES_APP_PASSWORD` | password for the application role (random if unset) |

### Example: provision passwords via cloud-init

Pass this as the instance's vendor-data or user-data at deploy time:

```yaml
#cloud-config
write_files:
  - path: /etc/qaimg/credentials
    owner: root:root
    permissions: '0600'
    content: |
      POSTGRES_PASSWORD=super-secret-postgres
      POSTGRES_APP_DB=appdb
      POSTGRES_APP_USER=appuser
      POSTGRES_APP_PASSWORD=super-secret-app
```

On first boot the `postgres` password is set and `appdb`/`appuser` are created.
Verify with:

```bash
PGPASSWORD=super-secret-app psql -h localhost -U appuser -d appdb -c '\conninfo'
```

See [`flavors/README.md`](../../README.md) for the full credentials mechanism.
