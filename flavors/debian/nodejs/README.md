# Debian Node.js flavor

This flavor installs Node.js 24 LTS from NodeSource's Debian repository. The
NodeSource package includes npm. The flavor does not create an application or
add a service.

## Build

```bash
./flavors/build.sh debian nodejs bookworm
```

The output is `bookworm-generic-amd64-qa.nodejs.qcow2`.

Verify the installed runtime with:

```bash
node --version
```
