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
and executes a drop-in in `/usr/local/lib/initial-provision.d` that regenerates
`POSTGRES_PASSWORD`, `DASHBOARD_PASSWORD`, and `SECRET_KEY_BASE` with random
per-instance values so images do not share well-known credentials. The first
boot pulls the Supabase images and needs internet access.

The login user is also added to the `docker` group at first boot. Re-log in for
the new group to take effect.

## Caveats

- The default configuration is **not production secure**. Beyond the regenerated
  passwords, you must still rotate the JWT/API keys (`ANON_KEY`, `SERVICE_ROLE_KEY`,
  `JWT_SECRET`) per the
  [Supabase self-hosting docs](https://supabase.com/docs/guides/self-hosting/docker),
  set your public URLs, and front the stack with a secure proxy.
- The compose config is cloned from the Supabase repo's `master` branch at build
  time, so the exact service versions are whatever is current then.
- Membership in the `docker` group is equivalent to root on the host.
