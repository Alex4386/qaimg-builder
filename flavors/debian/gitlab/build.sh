#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/../../lib/debian.sh"

gitlab_provisioning_script() {
    cat <<'FLAVOR_SCRIPT'
set -e
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y ca-certificates curl gnupg

install -m 0755 -d /usr/share/keyrings
curl -fsSL https://packages.gitlab.com/gitlab/gitlab-ce/gpgkey | \
    gpg --dearmor --batch --yes \
    -o /usr/share/keyrings/gitlab_gitlab-ce-archive-keyring.gpg
chmod a+r /usr/share/keyrings/gitlab_gitlab-ce-archive-keyring.gpg

. /etc/os-release
cat > /etc/apt/sources.list.d/gitlab_gitlab-ce.sources <<EOF
Types: deb
URIs: https://packages.gitlab.com/gitlab/gitlab-ce/debian/
Suites: $VERSION_CODENAME
Components: main
Architectures: $(dpkg --print-architecture)
Signed-By: /usr/share/keyrings/gitlab_gitlab-ce-archive-keyring.gpg
EOF

# Install the omnibus package without EXTERNAL_URL so the heavy
# `gitlab-ctl reconfigure` does not run inside the image build; it is deferred
# to first boot, where the instance's real address is known. The package
# enables gitlab-runsvdir.service, which supervises the bundled services.
apt-get update
apt-get install -y gitlab-ce
FLAVOR_SCRIPT

    flavor_credentials_base_snippet
    flavor_initial_provision_base_snippet

    cat <<'EOF'
cat > /usr/local/lib/initial-provision.d/30-gitlab-reconfigure.sh <<'DROPIN'
#!/bin/bash
set -e
# On first boot, apply preconfigured GITLAB_EXTERNAL_URL and GITLAB_ROOT_PASSWORD
# (from /etc/qaimg/credentials) then run the omnibus reconfigure once. If no
# external_url is provided, the value already in gitlab.rb is kept.
command -v gitlab-ctl >/dev/null 2>&1 || exit 0
. /usr/local/lib/qaimg-credentials.sh

ext_url="$(qaimg_cred GITLAB_EXTERNAL_URL || true)"
if [ -n "$ext_url" ]; then
    if grep -qE "^\s*external_url " /etc/gitlab/gitlab.rb; then
        sed -i -E "s|^\s*external_url .*|external_url \"${ext_url}\"|" \
            /etc/gitlab/gitlab.rb
    else
        printf 'external_url "%s"\n' "$ext_url" >> /etc/gitlab/gitlab.rb
    fi
fi

# initial_root_password is only honored on the FIRST reconfigure (before the
# DB is seeded), so set it via the documented environment variable.
root_pw="$(qaimg_cred GITLAB_ROOT_PASSWORD || true)"
if [ -n "$root_pw" ] && [ ! -f /etc/gitlab/initial_root_password ]; then
    GITLAB_ROOT_PASSWORD="$root_pw" gitlab-ctl reconfigure
else
    gitlab-ctl reconfigure
fi
DROPIN
chmod 0755 /usr/local/lib/initial-provision.d/30-gitlab-reconfigure.sh
EOF
}

# GitLab omnibus needs several GB just to install and reconfigure. Grow the
# image at build time (operator can override with FLAVOR_MIN_DISK_GB).
export FLAVOR_MIN_DISK_GB="${FLAVOR_MIN_DISK_GB:-8}"

gitlab_provisioning_script | build_debian_flavor "$@"
