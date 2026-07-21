# Debian Coolify flavor

This flavor bakes [Docker Engine](https://docs.docker.com/engine/) into the
image and runs [Coolify](https://coolify.io/)'s official installer at first boot.
Coolify is a self-hostable PaaS that deploys and manages applications on Docker.

## Build

```bash
./flavors/build.sh debian coolify bookworm
```

The output is `bookworm-generic-amd64-qa.coolify.qcow2`.

Docker is installed from Docker's official APT repository (same as the `docker`
flavor) and enabled. Coolify itself runs as a set of Docker containers managed
by its own installer under `/data/coolify`.

## Ports

- `8000/tcp` Coolify dashboard
- `80/tcp`, `443/tcp` Traefik/Caddy proxy for deployed apps
- `6001/tcp`, `6002/tcp` realtime and terminal websockets

## First boot

Coolify's installer (`https://cdn.coollabs.io/coolify/install.sh`) requires a
running Docker daemon, so it cannot run during the image build. A generic
oneshot `initial-provision.service` runs at first boot (ordered
`After=cloud-final.service`) and executes a drop-in in
`/usr/local/lib/initial-provision.d` that runs the installer once. The installer
creates `/data/coolify`, generates SSH keys, and starts the dashboard on port
`8000`.

The first boot needs outbound internet access to pull the Coolify images and can
take several minutes. Open `http://<host>:8000` afterwards to create the admin
account.

## Service management

Coolify is managed through Docker Compose in its data directory:

```bash
cd /data/coolify/source
sudo docker compose ps
sudo docker compose restart
```

## Login user access

The default login user does not exist when the image is built. A generic oneshot
`initial-provision.service` runs at first boot and adds the cloud-init login
user to the `docker` group via a drop-in in
`/usr/local/lib/initial-provision.d`. Re-log in after the first boot for the new
group to take effect. See [`flavors/README.md`](../../README.md) for the full
first-boot provisioning mechanism.

## Caveats

- Coolify requires at least 2 CPUs, 2 GB RAM, and 30 GB of storage.
- The install step runs a `curl | bash` from `cdn.coollabs.io` at first boot and
  needs internet access. Review the installer before use if that is a concern.
- Membership in the `docker` group is equivalent to root on the host.
