# Debian Supabase flavor

This flavor bakes [Docker Engine](https://docs.docker.com/engine/) and the
official [Supabase](https://supabase.com/) self-hosting Docker Compose stack into
the image, and enables it as a systemd service.

## Build

```bash
./flavors/build.sh debian supabase bookworm
```

The output is `bookworm-generic-amd64-qa.supabase.qcow2`.

Docker is installed from Docker's official APT repository (same as the `docker`
flavor) and enabled. The compose project is staged under `/opt/supabase/project`
and owned by the dedicated, non-login `supabase` system user. A
`supabase.service` systemd unit runs `docker compose up -d --wait` on boot.

## Ports

- `8000/tcp` Kong API gateway and Studio dashboard
- `5432/tcp` PostgreSQL (via Supavisor)

Keep these ports closed on your security group or firewall until you have
secured the instance.

## Service

```bash
sudo systemctl status supabase
sudo systemctl restart supabase
sudo systemctl stop supabase
```

Under the hood the stack is plain Docker Compose:

```bash
cd /opt/supabase/project
sudo docker compose ps
```

## Configuration

- `/opt/supabase/project/.env` secrets and settings
- `/opt/supabase/project/docker-compose.yml` service definitions
- `/opt/supabase/project/volumes/` mounted service configuration

## First boot

The image ships the upstream `.env.example` values. A generic oneshot
`initial-provision.service` runs at first boot (ordered `After=cloud-final.service`)
and executes the `40-supabase-secrets.sh` drop-in that fills the stack's secrets
before the first `docker compose up`. The first boot pulls the Supabase images
and needs internet access.

Secrets come from `/etc/qaimg/credentials` (delivered via cloud-init, see
[`examples/vendor.yaml`](../../../examples/vendor.yaml)); anything omitted is
generated randomly and persisted to `/etc/qaimg/credentials.generated`:

| Key | Purpose |
|-----|---------|
| `POSTGRES_PASSWORD` | database superuser password |
| `DASHBOARD_USERNAME` | Studio dashboard user (default `supabase`) |
| `DASHBOARD_PASSWORD` | Studio dashboard password |
| `SECRET_KEY_BASE` | stack secret key base |
| `JWT_SECRET` | JWT signing secret |

### Example: provision secrets via cloud-init

Pass this as the instance's vendor-data or user-data at deploy time:

```yaml
#cloud-config
write_files:
  - path: /etc/qaimg/credentials
    owner: root:root
    permissions: '0600'
    content: |
      POSTGRES_PASSWORD=super-secret-postgres
      DASHBOARD_USERNAME=admin
      DASHBOARD_PASSWORD=super-secret-dashboard
      JWT_SECRET=a-very-long-random-jwt-secret-at-least-32-chars
```

These land in `/opt/supabase/project/.env` before the stack starts. Log in to
Studio at `http://<host>:8000` with the dashboard username/password above.

The login user is also added to the `docker` group at first boot. Re-log in for
the new group to take effect. See [`flavors/README.md`](../../README.md) for the
full credentials mechanism.

## Caveats

- The default configuration is **not production secure**. `JWT_SECRET` is set
  from credentials (or randomized), but the pre-signed `ANON_KEY` and
  `SERVICE_ROLE_KEY` JWTs in `.env` are **not** re-signed automatically — if you
  change `JWT_SECRET` you must regenerate those two tokens per the
  [Supabase self-hosting docs](https://supabase.com/docs/guides/self-hosting/docker),
  set your public URLs, and front the stack with a secure proxy.
- The compose config is cloned from the Supabase repo's `master` branch at build
  time, so the exact service versions are whatever is current then.
- Membership in the `docker` group is equivalent to root on the host.
