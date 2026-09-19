#!/usr/bin/bash
set -euxo pipefail

# EmuDeck expects the user to supply Eden, so ship the latest release; the first-login hook
# copies it to ~/Applications/Eden.AppImage where EmuDeck looks for it.
EDEN_VARIANT="${EDEN_VARIANT:-amd64-clang-pgo}"

# One jq pass so the (huge) release JSON never lands in the xtrace log.
read -r tag url < <(curl -fsSL https://git.eden-emu.dev/api/v1/repos/eden-emu/eden/releases/latest |
	jq -r --arg v "$EDEN_VARIANT" \
		'[.tag_name, ([.assets[] | select(.name | test("^Eden-Linux-v.*-" + $v + "\\.AppImage$")) | .browser_download_url][0] // "")] | @tsv')
if [[ -z "${url:-}" ]]; then
	echo "no Eden ${EDEN_VARIANT} AppImage in release ${tag}" >&2
	exit 1
fi

install -d /usr/lib/eden
curl -fsSL "$url" -o /usr/lib/eden/Eden.AppImage
chmod 0755 /usr/lib/eden/Eden.AppImage
# The variant is part of the stamp so a rebuild with another flavour reaches users on the same tag.
echo "${tag}-${EDEN_VARIANT}" >/usr/lib/eden/VERSION
