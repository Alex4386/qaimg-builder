# Debian generic (first-run) flavor

This flavor ships the reusable **first-run** machinery on its own, without any
application. Use it as a base image when you want to attach your own first-boot
logic via cloud-init instead of adopting a full app flavor.

It bakes in:

- the **initial-provision** oneshot service (`After=cloud-final.service`) that,
  on first boot, resolves the cloud-init login user, copies
  `/usr/local/cloud-init/home-template/` into that user's home, and runs every
  executable `*.sh` drop-in in `/usr/local/lib/initial-provision.d/`;
- the **preconfigured-credentials** library at
  `/usr/local/lib/qaimg-credentials.sh` (reads `/etc/qaimg/credentials`, falls
  back to a baked default, then to persisted random values).

## Build

```bash
./flavors/build.sh debian generic bookworm
```

The output is `bookworm-generic-amd64-qa.generic.qcow2`.

## Adding your own first-run logic

Deliver a drop-in and (optionally) credentials through cloud-init. The drop-in
receives the login user as `$1` and `LOGIN_USER` in the environment, and may
source the credentials library:

```yaml
#cloud-config
write_files:
  - path: /etc/qaimg/credentials
    owner: root:root
    permissions: '0600'
    content: |
      MY_APP_TOKEN=s3cr3t
  - path: /usr/local/lib/initial-provision.d/50-my-setup.sh
    owner: root:root
    permissions: '0755'
    content: |
      #!/bin/bash
      set -e
      . /usr/local/lib/qaimg-credentials.sh
      token="$(qaimg_cred_or_random MY_APP_TOKEN)"
      echo "configuring for login user: $LOGIN_USER"
      # ...your setup here...
```

Drop-ins run in filename order; the app flavors use `20`–`40` prefixes, so use
`50`+ to run after them. The runner marks itself done via
`/var/lib/initial-provision/.done` and runs only once.

See [`flavors/README.md`](../../README.md) for the full first-boot and
credentials mechanism, and [`examples/vendor.yaml`](../../../examples/vendor.yaml)
for a credentials example.
