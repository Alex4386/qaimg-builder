# Debian GitLab CE flavor

This flavor installs [GitLab Community Edition](https://about.gitlab.com/)
(the omnibus package) from GitLab's official APT repository.

## Build

```bash
./flavors/build.sh debian gitlab bookworm
```

The output is `bookworm-generic-amd64-qa.gitlab.qcow2`.

GitLab omnibus bundles and supervises its own services (Puma, Sidekiq,
PostgreSQL, Redis, Gitaly, NGINX, etc.) under the `gitlab-runsvdir.service`
systemd unit installed by the package. The bundled services run as the
omnibus-managed `git`, `gitlab-*`, and related system users; you do not manage
them individually.

## Ports

- `80/tcp` bundled NGINX (HTTP)
- `443/tcp` bundled NGINX (HTTPS, if configured)
- `22/tcp` Git over SSH (shares the host SSH port)

## First boot

The omnibus package is installed **without** `EXTERNAL_URL`, so the expensive
`gitlab-ctl reconfigure` does not run during the image build. Instead, a generic
oneshot `initial-provision.service` runs at first boot (ordered
`After=cloud-final.service`) and executes the `30-gitlab-reconfigure.sh` drop-in
that applies preconfigured credentials and then runs `gitlab-ctl reconfigure`
once.

Credentials come from `/etc/qaimg/credentials` (delivered via cloud-init, see
[`examples/vendor.yaml`](../../../examples/vendor.yaml)):

| Key | Purpose |
|-----|---------|
| `GITLAB_EXTERNAL_URL` | written to `gitlab.rb` before reconfigure (kept as-is if unset) |
| `GITLAB_ROOT_PASSWORD` | initial `root` password, honored only on the first reconfigure |

If `GITLAB_ROOT_PASSWORD` is not provided, the initial root password is
generated at reconfigure time and written to `/etc/gitlab/initial_root_password`
(valid for 24 hours). See [`flavors/README.md`](../../README.md) for the full
credentials mechanism.

To change the external URL later:

```bash
sudo sed -i "s|^external_url .*|external_url 'https://gitlab.example.com'|" \
    /etc/gitlab/gitlab.rb
sudo gitlab-ctl reconfigure
```

## Service management

```bash
sudo gitlab-ctl status
sudo gitlab-ctl restart
sudo gitlab-ctl stop
sudo systemctl status gitlab-runsvdir
```

## Configuration

- `/etc/gitlab/gitlab.rb` main configuration (run `gitlab-ctl reconfigure` after
  edits)
- `/var/opt/gitlab` application data
- `/var/log/gitlab` logs

## Caveats

- GitLab omnibus is resource hungry: at least 4 GB RAM (8 GB recommended) and
  several GB of disk are required for a usable instance. The build grows the
  image to `FLAVOR_MIN_DISK_GB` (default 8 GiB) so the package installs and
  reconfigures with headroom; override it if needed, e.g.
  `FLAVOR_MIN_DISK_GB=40 ./flavors/build.sh debian gitlab bookworm`.
- The first `gitlab-ctl reconfigure` at boot can take several minutes; GitLab is
  not reachable until it finishes.
- The omnibus package is published for `amd64` and `arm64` only.
