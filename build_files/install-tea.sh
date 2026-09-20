#!/usr/bin/bash
# Installs the latest release of tea, Gitea's CLI (it talks to Forgejo too). Neither Fedora nor
# Terra packages it, so this takes Gitea's release binary. Run by 80-forge-clis.sh.
set -euxo pipefail

DEST="${TEA_DEST:-/usr/bin/tea}"

# releases/latest answers with a redirect to releases/tag/v<version>, which spares the API and JSON.
latest="$(curl -fsS -o /dev/null -w '%{redirect_url}' https://gitea.com/gitea/tea/releases/latest)"
version="${latest##*/v}"
if [[ ! "$version" =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
	echo "could not work out the latest tea version from '${latest}'" >&2
	exit 1
fi

name="tea-${version}-linux-amd64"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
curl -fsSL -o "$work/$name" "https://dl.gitea.com/tea/${version}/${name}"
curl -fsSL -o "$work/$name.sha256" "https://dl.gitea.com/tea/${version}/${name}.sha256"
# The checksum is served by the same host as the binary: it catches a broken download, not a
# compromised server. Gitea publishes no signature for tea.
(cd "$work" && sha256sum -c "$name.sha256")
install -m 0755 "$work/$name" "$DEST"
echo "tea ${version} installed at ${DEST}"
