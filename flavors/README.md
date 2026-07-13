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
./flavors/build.sh debian nginx bookworm
./flavors/build.sh debian nodejs bookworm
./flavors/build.sh debian wireguard bookworm
./flavors/build.sh debian docker bookworm
./flavors/build.sh debian minecraft-vanilla bookworm
./flavors/build.sh debian minecraft-paper bookworm
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
