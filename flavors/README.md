# Application image flavors

Flavors turn a distribution cloud image into an application blueprint, such as
an Nginx, WordPress, Node.js, or LAMP image. Each flavor owns its provisioning
logic under:

```text
flavors/<distribution>/<flavor>/build.sh
```

## Building a flavor

Use the dispatcher or invoke a flavor directly:

```bash
./flavors/build.sh debian generic bookworm
./flavors/build.sh debian nginx bookworm
./flavors/build.sh debian nodejs bookworm
./flavors/build.sh debian wireguard bookworm
./flavors/build.sh debian docker bookworm
./flavors/build.sh debian grafana bookworm
./flavors/build.sh debian mariadb bookworm
./flavors/build.sh debian postgresql bookworm
./flavors/build.sh debian minecraft-vanilla bookworm
./flavors/build.sh debian minecraft-paper bookworm
./flavors/build.sh debian palworld bookworm
./flavors/build.sh debian openclaw bookworm
./flavors/build.sh debian coolify bookworm
./flavors/build.sh debian supabase bookworm
./flavors/build.sh debian gitlab bookworm
./flavors/build.sh debian strapi bookworm
./flavors/build.sh debian prometheus bookworm
./flavors/build.sh debian elasticsearch bookworm
./flavors/debian/nginx/build.sh bookworm
```

Flavor-specific setup and usage belongs in each flavor directory's `README.md`.

To reuse a base image instead of downloading it:

```bash
BASE_IMAGE=/images/bookworm-generic-amd64-qa.qcow2 \
  ./flavors/build.sh debian nginx bookworm
```

## Adding a flavor

Create `flavors/<distribution>/<flavor>/build.sh` and make it executable. For
Debian, source `flavors/lib/debian.sh` and pass only the provisioning script to
`build_debian_flavor`:

```bash
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/debian.sh"

build_debian_flavor "$@" <<'FLAVOR_SCRIPT'
apt-get update
apt-get install -y example-package
FLAVOR_SCRIPT
```

The shared runner handles the QA base image, qimi, work directories, output
naming, and publication.

The dispatcher discovers executable scripts at that exact path automatically.

## First-boot provisioning (the login user)

The cloud-init login user (`debian`, `ubuntu`, etc.) does not exist when the
image is built, so anything that depends on it must run on the booted instance.
`flavors/lib/common.sh` provides a generic mechanism for this. Emit its snippet
into your provisioning script:

```bash
flavor_initial_provision_base_snippet
```

This installs a oneshot `initial-provision.service`, ordered
`After=cloud-final.service`, that runs once on first boot and:

1. resolves the login user cloud-init created (reads
   `/etc/sudoers.d/90-cloud-init-users`, falling back to UID 1000),
2. copies `/usr/local/cloud-init/home-template/` into that user's home,
   chowned to the user, and
3. runs every executable `*.sh` drop-in in
   `/usr/local/lib/initial-provision.d/`, passing the login user as `$1` and
   exporting `LOGIN_USER`.

To stage files into the login user's home, drop them under
`/usr/local/cloud-init/home-template/` at build time. For runtime-aware logic,
write a drop-in. A ready-made helper adds the login user to a group (useful for
letting a human manage a service that runs as a dedicated system user):

```bash
flavor_initial_provision_base_snippet
flavor_initial_provision_group_dropin minecraft   # optional: priority as $2
```

Prefer `/etc/skel` for purely static home files: cloud-init's `useradd -m`
copies it at account-creation time with no service needed. Use this mechanism
when you need the resolved username, files outside home, group ownership, or
re-runnable logic.

## Disk sizing (build-time image growth)

The upstream cloud images ship a small virtual disk (~3 GB), which is too small
to *build* heavy flavors like GitLab. A flavor can declare a minimum image size,
and `build_debian_flavor` grows the working image to at least that **before**
provisioning — resizing the virtual disk (`qemu-img resize`), then the root
partition (`growpart`) and filesystem (`resize2fs`) on the build host via
`qemu-nbd`.

Declare it in the flavor's `build.sh`, before the `build_debian_flavor` call:

```bash
export FLAVOR_MIN_DISK_GB="${FLAVOR_MIN_DISK_GB:-16}"   # operator can override
```

Notes:

- The default expression lets an operator override the size at build time:
  `FLAVOR_MIN_DISK_GB=40 ./flavors/build.sh debian gitlab bookworm`.
- If the image is already at least that large, the resize is a no-op.
- `FLAVOR_RESIZE=0` disables the resize (used by the test suite, which builds
  against a stub image).
- Growing needs `growpart` (cloud-guest-utils) and `resize2fs` (e2fsprogs) on
  the build host, and root/sudo for `qemu-nbd` — `common/setup-deps.sh` installs
  the build-host packages.
- This is separate from **runtime** growth: the upstream images keep cloud-init's
  `growpart`/`resizefs`, so a deployed instance still expands its root filesystem
  to fill whatever (larger) disk the hypervisor provides.

## Preconfigured credentials

Flavors that manage secrets (database passwords, app tokens, admin passwords)
resolve them at first boot instead of baking fixed values into the image, so no
two instances share the same well-known credentials. Emit the credentials
library into your provisioning script, then read values inside an
`initial-provision` drop-in:

```bash
flavor_credentials_base_snippet     # installs /usr/local/lib/qaimg-credentials.sh
flavor_initial_provision_base_snippet
```

Inside a drop-in:

```bash
. /usr/local/lib/qaimg-credentials.sh
pw="$(qaimg_cred_or_random POSTGRES_PASSWORD)"   # provided value, else random+persisted
url="$(qaimg_cred GITLAB_EXTERNAL_URL || true)"  # provided value, else empty
```

Resolution precedence for each key:

1. **Deploy-time** — `/etc/qaimg/credentials`, delivered by the operator via
   cloud-init (see [`examples/vendor.yaml`](../examples/vendor.yaml)).
2. **Build-time** — `/usr/local/share/qaimg/credentials.default`, an optional
   fallback baked into the image.
3. **Random** — `qaimg_cred_or_random` generates a value and persists it to
   `/etc/qaimg/credentials.generated` (mode `0600`) so it is stable across
   reboots and retrievable by the operator.

All three files are flat `KEY=VALUE` (values may be quoted). Deliver deploy-time
credentials as cloud-init vendor-data or user-data with a `write_files` entry
for `/etc/qaimg/credentials` (owner `root:root`, mode `0600`).
