#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/../../lib/debian.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../common-minecraft.sh"

minecraft_provisioning_script <<'FLAVOR_SCRIPT' | build_debian_flavor "$@"
MINECRAFT_VERSION=1.20.4
PAPER_BUILD=499
PAPER_USER_AGENT='qaimg-builder/1.0 (https://github.com/Alex4386/qaimg-builder)'

build_metadata="$(mktemp)"
trap 'rm -f "$build_metadata"' EXIT

curl -fsSL -H "User-Agent: $PAPER_USER_AGENT" \
    "https://fill.papermc.io/v3/projects/paper/versions/$MINECRAFT_VERSION/builds/$PAPER_BUILD" \
    -o "$build_metadata"
jq -e '.channel == "STABLE"' "$build_metadata" >/dev/null

server_url="$(jq -er '.downloads["server:default"].url' "$build_metadata")"
server_sha256="$(jq -er '.downloads["server:default"].checksums.sha256' "$build_metadata")"
curl -fsSL -H "User-Agent: $PAPER_USER_AGENT" \
    "$server_url" -o "$MINECRAFT_DIR/server.jar"
printf '%s  %s\n' "$server_sha256" "$MINECRAFT_DIR/server.jar" | sha256sum -c -
FLAVOR_SCRIPT
