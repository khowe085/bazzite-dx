#!/usr/bin/bash
set -euxo pipefail

# EmuDeck and Crunchyroll (the Bazzite Portal's picks), shipped in the image like Eden (40-eden.sh):
# the first-login hooks copy them into ~/Applications without a network, and an image built after
# a new release brings the update (/usr/libexec/image-appimage). Each build takes the latest release.
# Run by the Containerfile in a RUN of its own, the only one given the GITHUB_TOKEN build secret;
# build.sh does not run it (no NN- prefix).
APPIMAGE_ROOT="${APPIMAGE_ROOT:-/usr/lib}"
TOKEN_FILE="${TOKEN_FILE:-/run/secrets/GITHUB_TOKEN}"

# Unauthenticated, GitHub allows 60 API calls an hour per address, which CI runners share; the
# workflow passes its token as a build secret. It goes to curl in a config file, so the xtrace log
# shows only the file's name.
auth=()
if [[ -s "$TOKEN_FILE" ]]; then
	auth_config="$(mktemp)"
	trap 'rm -f "$auth_config"' EXIT
	{ printf 'header = "Authorization: Bearer %s"\n' "$(<"$TOKEN_FILE")" >"$auth_config"; } 2>/dev/null
	auth=(-K "$auth_config")
fi

ship() { # ship <owner/repo> <directory under APPIMAGE_ROOT> <file name>
	local repo=$1 dir="${APPIMAGE_ROOT}/$2" name=$3 tag url digest
	# One jq pass so the release JSON never lands in the xtrace log. "-" stands in for a missing
	# field, because read collapses empty tab-separated fields.
	read -r tag url digest < <(curl -fsSL --retry 3 "${auth[@]}" "https://api.github.com/repos/${repo}/releases/latest" |
		jq -r '(.assets | map(select(.name | endswith(".AppImage") and (test("arm64|aarch64") | not))) | .[0]) as $a
			| [.tag_name // "-", ($a.browser_download_url // "-"), ($a.digest // "-")] | @tsv')
	if [[ "${url:--}" == - || "${tag:--}" == - ]]; then
		echo "no x86_64 AppImage in the latest release of ${repo}" >&2
		return 1
	fi
	install -d "$dir"
	curl -fsSL --retry 3 "$url" -o "${dir}/${name}"
	# GitHub records a sha256 for assets uploaded since mid-2025; older ones (EmuDeck's) have none.
	if [[ "$digest" == sha256:* ]]; then
		echo "${digest#sha256:}  ${dir}/${name}" | sha256sum -c -
	fi
	chmod 0755 "${dir}/${name}"
	echo "$tag" >"${dir}/VERSION"
}

ship EmuDeck/emudeck-electron emudeck EmuDeck.AppImage
ship aarron-lee/crunchyroll-linux crunchyroll Crunchyroll.AppImage
