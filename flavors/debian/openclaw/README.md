# Debian OpenClaw flavor

This flavor installs [OpenClaw](https://github.com/openclaw/openclaw) — "your own
personal AI assistant. Any OS. Any Platform. The lobster way." OpenClaw is a
Node.js personal AI assistant **Gateway** (a control plane) that connects to
messaging channels such as WhatsApp, Telegram, Slack, and Discord.

## Build

```bash
./flavors/build.sh debian openclaw bookworm
```

The output is `bookworm-generic-amd64-qa.openclaw.qcow2`.

Node.js 24.x (from NodeSource, satisfying OpenClaw's 24.15+ recommendation) and
the `openclaw` CLI are pre-baked globally into the image
(`npm install -g openclaw@latest`, with npm bundled in the Node.js package).

OpenClaw runs as a **systemd user service** (`systemctl --user`), not a
system-wide service, so there is intentionally no system service in this image.
Onboarding is an interactive wizard and cannot run at build time, so the login
user completes setup after first boot.

## First-login setup

After logging in for the first time, run the interactive onboarding wizard, which
sets up the gateway, workspace, channels, skills, and model/API auth:

```bash
openclaw onboard --install-daemon
openclaw gateway status
```

`--install-daemon` installs the Gateway as a systemd *user* service. Lingering is
already enabled for the login user on this image (see below), so the Gateway
keeps running after you log out.

## Lingering (first boot)

The default login user does not exist when the image is built. A generic oneshot
`initial-provision.service` runs at first boot (ordered `After=cloud-final.service`)
and:

1. copies staged files from `/usr/local/cloud-init/home-template/` into the login
   user's home (here, `README-openclaw.md` with these instructions), and
2. runs a drop-in in `/usr/local/lib/initial-provision.d` that executes
   `loginctl enable-linger "$LOGIN_USER"` for the resolved login user, so a
   systemd user service can run without an active session.

See [`flavors/README.md`](../../README.md) for the full first-boot provisioning
mechanism.

## Configuration

- `~/.openclaw/openclaw.json` main configuration
- `~/.openclaw/workspace` workspace

## You must provide

OpenClaw needs model/provider API credentials (e.g. an OpenAI API key) to
function. The onboarding wizard prompts for these; they are not shipped in the
image.

## Security

OpenClaw connects to real messaging surfaces and treats inbound DMs as
**untrusted**; the default DM policy is pairing-based. Review your channel and DM
settings before exposing the assistant to public messaging, and supply provider
credentials only for accounts you control.
