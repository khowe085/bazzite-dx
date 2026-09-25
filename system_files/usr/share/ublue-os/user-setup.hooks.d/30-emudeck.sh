#!/usr/bin/bash
# First-login setup for EmuDeck: puts EmuDeck and Eden into ~/Applications, the folder EmuDeck
# uses for AppImages. Both are copied from the image, so nothing is downloaded at login: EmuDeck is
# the AppImage `ujust get-emudeck` would fetch (placed without Gear Lever's GUI steps), and Eden is
# shipped because EmuDeck does not download it. Runs on every login and only acts when something is
# missing or the image has a newer version.
set -euo pipefail

APPS_DIR="${HOME}/Applications"
EDEN_IMAGE_DIR="${EDEN_IMAGE_DIR:-/usr/lib/eden}"
EMUDECK_IMAGE_DIR="${EMUDECK_IMAGE_DIR:-/usr/lib/emudeck}"
IMAGE_APPIMAGE="${IMAGE_APPIMAGE:-/usr/libexec/image-appimage}"

install_eden() {
	local stamp="${APPS_DIR}/.eden.image-version"
	local target="${APPS_DIR}/Eden.AppImage"
	local image_version
	if [[ ! -r "${EDEN_IMAGE_DIR}/VERSION" ]]; then
		echo "no Eden in this image (${EDEN_IMAGE_DIR}/VERSION missing); skipping" >&2
		return
	fi
	image_version="$(<"${EDEN_IMAGE_DIR}/VERSION")"

	# No stamp next to an existing Eden means the user put it there; never replace that.
	# A managed copy that went missing is restored: EmuDeck launches ~/Applications/Eden.AppImage
	# directly, so unlike EmuDeck itself there is no other place it can legitimately live.
	if [[ -e "$target" && ! -e "$stamp" ]]; then
		echo "Eden.AppImage is not managed by this image; leaving it alone"
		return
	fi
	if [[ -e "$target" && -e "$stamp" && "$(<"$stamp")" == "$image_version" ]]; then
		return
	fi
	install -m 0755 "${EDEN_IMAGE_DIR}/Eden.AppImage" "$target"
	echo "$image_version" >"$stamp"
	echo "Eden ${image_version} placed at ${target}"
}

mkdir -p "$APPS_DIR"
install_eden
# If EmuDeck updates itself, image-appimage leaves its copy alone from then on.
"$IMAGE_APPIMAGE" emudeck "$EMUDECK_IMAGE_DIR" EmuDeck.AppImage '*EmuDeck*.AppImage' \
	EmuDeck "Emulator setup and management" "Game;Utility;"
