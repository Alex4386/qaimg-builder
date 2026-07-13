#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/../../lib/debian.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../common-minecraft.sh"

minecraft_provisioning_script <<'FLAVOR_SCRIPT' | build_debian_flavor "$@"
MINECRAFT_VERSION=1.20.4

version_manifest="$(mktemp)"
version_metadata="$(mktemp)"
trap 'rm -f "$version_manifest" "$version_metadata"' EXIT

curl -fsSL \
    https://piston-meta.mojang.com/mc/game/version_manifest_v2.json \
    -o "$version_manifest"
version_url="$(jq -er --arg version "$MINECRAFT_VERSION" \
    'first(.versions[] | select(.id == $version) | .url)' \
    "$version_manifest")"
curl -fsSL "$version_url" -o "$version_metadata"

server_url="$(jq -er '.downloads.server.url' "$version_metadata")"
server_sha1="$(jq -er '.downloads.server.sha1' "$version_metadata")"
curl -fsSL "$server_url" -o "$MINECRAFT_DIR/server.jar"
printf '%s  %s\n' "$server_sha1" "$MINECRAFT_DIR/server.jar" | sha1sum -c -
FLAVOR_SCRIPT
