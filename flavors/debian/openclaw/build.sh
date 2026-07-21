#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/../../lib/debian.sh"

openclaw_provisioning_script() {
    cat <<'FLAVOR_SCRIPT'
set -e
export DEBIAN_FRONTEND=noninteractive

NODE_MAJOR=24

apt-get update
apt-get install -y apt-transport-https ca-certificates curl gnupg

# OpenClaw is a Node.js app; Node 24.x satisfies its 24.15+ recommendation.
# Install from NodeSource the same deb822 way the nodejs/strapi flavors do.
install -m 0755 -d /usr/share/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | \
    gpg --dearmor --batch --yes -o /usr/share/keyrings/nodesource.gpg
chmod a+r /usr/share/keyrings/nodesource.gpg

cat > /etc/apt/sources.list.d/nodesource.sources <<EOF
Types: deb
URIs: https://deb.nodesource.com/node_${NODE_MAJOR}.x
Suites: nodistro
Components: main
Architectures: $(dpkg --print-architecture)
Signed-By: /usr/share/keyrings/nodesource.gpg
EOF

cat > /etc/apt/preferences.d/nodejs <<'EOF'
Package: nodejs
Pin: origin deb.nodesource.com
Pin-Priority: 600
EOF

apt-get update
apt-get install -y nodejs

# Bake the OpenClaw CLI globally (npm ships with the nodejs package). The
# per-user Gateway daemon and interactive onboarding are set up by the login
# user after first boot, not here.
npm install -g openclaw@latest
FLAVOR_SCRIPT

    flavor_initial_provision_base_snippet

    # OpenClaw runs as a systemd *user* service. Enable lingering for the
    # resolved login user at first boot so the Gateway keeps running without an
    # active login session. Also stage setup instructions into the user's home.
    cat <<'EOF'
cat > /usr/local/lib/initial-provision.d/30-openclaw-linger.sh <<'DROPIN'
#!/bin/bash
set -e
login_user="$1"
if [ -n "$login_user" ] && id -u "$login_user" >/dev/null 2>&1 \
    && command -v loginctl >/dev/null 2>&1; then
    loginctl enable-linger "$login_user"
fi
DROPIN
chmod 0755 /usr/local/lib/initial-provision.d/30-openclaw-linger.sh

install -d /usr/local/cloud-init/home-template
cat > /usr/local/cloud-init/home-template/README-openclaw.md <<'NOTE'
# OpenClaw on this image

OpenClaw is your own personal AI assistant Gateway (a Node.js control plane that
connects to messaging channels like WhatsApp, Telegram, Slack, and Discord).

Node.js 24.x and the `openclaw` CLI are already installed globally. OpenClaw runs
as a **systemd user service** (`systemctl --user`), not a system-wide service.

## First-login setup

Onboarding is an interactive wizard, so run it yourself after logging in:

```bash
openclaw onboard --install-daemon
openclaw gateway status
```

`--install-daemon` installs the Gateway as a systemd *user* service. Lingering is
already enabled for your account on this image, so the Gateway keeps running
after you log out.

## You must provide

- Model/provider API credentials (e.g. an OpenAI API key). The onboarding wizard
  prompts for these; OpenClaw will not work without them.

## Security

OpenClaw connects to real messaging surfaces and treats inbound DMs as
**untrusted**. The default DM policy is pairing-based. Review channel and DM
settings before exposing the assistant to public messaging.

Config lives at `~/.openclaw/openclaw.json`; the workspace at
`~/.openclaw/workspace`.
NOTE
EOF
}

openclaw_provisioning_script | build_debian_flavor "$@"
