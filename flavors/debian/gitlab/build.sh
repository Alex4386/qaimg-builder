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

    flavor_initial_provision_base_snippet

    cat <<'EOF'
cat > /usr/local/lib/initial-provision.d/30-gitlab-reconfigure.sh <<'DROPIN'
#!/bin/bash
set -e
# Run the omnibus reconfigure once on first boot using whatever external_url is
# set in /etc/gitlab/gitlab.rb (defaults to http://gitlab.example.com). The
# operator should edit gitlab.rb and re-run `gitlab-ctl reconfigure` afterwards.
if command -v gitlab-ctl >/dev/null 2>&1; then
    gitlab-ctl reconfigure
fi
DROPIN
chmod 0755 /usr/local/lib/initial-provision.d/30-gitlab-reconfigure.sh
EOF
}

gitlab_provisioning_script | build_debian_flavor "$@"
