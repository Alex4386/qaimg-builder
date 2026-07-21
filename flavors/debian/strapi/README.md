# Debian Strapi flavor

This flavor installs [Strapi](https://strapi.io/) (the open-source headless CMS)
on Node.js LTS, scaffolds a production project, and enables it as a systemd
service.

## Build

```bash
./flavors/build.sh debian strapi bookworm
```

The output is `bookworm-generic-amd64-qa.strapi.qcow2`.

The service is enabled in the image and runs as the dedicated, non-login
`strapi` system user. The application lives in `/opt/strapi/app`.

## Ports

- `1337/tcp` Strapi HTTP server (admin panel and content API)

Strapi has no built-in TLS. Put it behind an authenticated reverse proxy before
exposing it, and keep `1337/tcp` closed on your security group or firewall
otherwise.

## Service

```bash
sudo systemctl status strapi
sudo systemctl restart strapi
sudo systemctl stop strapi
```

## Configuration

- `/opt/strapi/app` project root
- `/opt/strapi/app/.env` runtime configuration (secrets, database client, host,
  port)
- `/opt/strapi/app/config/` server, database, and admin configuration

The project is scaffolded with the bundled SQLite database so the image is
self-contained. For production, switch `DATABASE_CLIENT` (and the related
`DATABASE_*` variables) in `.env` to PostgreSQL or MySQL, then rebuild:

```bash
sudo -u strapi -H env HOME=/opt/strapi NODE_ENV=production \
    npm --prefix /opt/strapi/app run build
sudo systemctl restart strapi
```

Create the first admin user by visiting `http://<host>:1337/admin` after the
first boot.

## Credentials

`create-strapi-app` bakes Strapi's secrets (`APP_KEYS`, `*_SALT`, `*_SECRET`)
into `.env` at build time, so every image built from the same run would
otherwise share identical secrets. The `40-strapi-secrets.sh` drop-in fixes this
at first boot: it applies preconfigured values or generates per-instance random
ones, then restarts Strapi. Values come from `/etc/qaimg/credentials` (see
[`examples/vendor.yaml`](../../../examples/vendor.yaml)):

| Key | `.env` value |
|-----|--------------|
| `STRAPI_APP_KEYS` | `APP_KEYS` |
| `STRAPI_API_TOKEN_SALT` | `API_TOKEN_SALT` |
| `STRAPI_ADMIN_JWT_SECRET` | `ADMIN_JWT_SECRET` |
| `STRAPI_TRANSFER_TOKEN_SALT` | `TRANSFER_TOKEN_SALT` |
| `STRAPI_JWT_SECRET` | `JWT_SECRET` |

Anything omitted is generated randomly and persisted to
`/etc/qaimg/credentials.generated`. See [`flavors/README.md`](../../README.md)
for the full credentials mechanism.

## Login user access

The default login user does not exist when the image is built. A generic oneshot
`initial-provision.service` runs at first boot (ordered `After=cloud-final.service`)
and adds the cloud-init login user to the `strapi` group via a drop-in in
`/usr/local/lib/initial-provision.d`, giving it access to the app files under
`/opt/strapi`. Re-log in after the first boot for the new group to take effect.
See [`flavors/README.md`](../../README.md) for the full first-boot provisioning
mechanism.

## Caveat

Project scaffolding runs `create-strapi-app` at build time, which downloads npm
dependencies from the network. The exact Strapi version baked in is whatever is
current when the image is built.
