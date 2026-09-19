#!/usr/bin/bash
# First-login setup for EmuDeck: puts EmuDeck and Eden into ~/Applications, the folder EmuDeck
# uses for AppImages. EmuDeck comes from GitHub like `ujust get-emudeck` does, but without Gear
# Lever's GUI steps so this can run unattended; Eden is copied from the image because EmuDeck
# does not download it. Runs on every login and only acts when something is missing or outdated.
set -euo pipefail

APPS_DIR="${HOME}/Applications"
DESKTOP_DIR="${HOME}/.local/share/applications"
ICON_DIR="${HOME}/.local/share/icons/hicolor/256x256/apps"
EDEN_IMAGE_DIR="${EDEN_IMAGE_DIR:-/usr/lib/eden}"
EMUDECK_RELEASES_API="${EMUDECK_RELEASES_API:-https://api.github.com/repos/EmuDeck/emudeck-electron/releases/latest}"

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

extract_icon() { # extract_icon <appimage>
	local tmp
	tmp="$(mktemp -d)"
	# .DirIcon is usually a symlink into the payload, so pull its target too.
	(
		cd "$tmp" &&
			"$1" --appimage-extract .DirIcon >/dev/null 2>&1 &&
			if [[ -L squashfs-root/.DirIcon ]]; then "$1" --appimage-extract "$(readlink squashfs-root/.DirIcon)" >/dev/null 2>&1; fi &&
			install -Dm0644 squashfs-root/.DirIcon "${ICON_DIR}/emudeck.png"
	) || echo "could not extract the EmuDeck icon; the menu entry will use a generic one" >&2
	rm -rf "$tmp"
}

install_emudeck() {
	local stamp="${APPS_DIR}/.emudeck.image-placed"
	# Placed once per user. Afterwards EmuDeck's own updater, Gear Lever (which moves the file out
	# of ~/Applications) or `ujust get-emudeck` own it, so a missing file is not a reason to re-download.
	if [[ -e "$stamp" ]] || compgen -G "${APPS_DIR}/*EmuDeck*.AppImage" >/dev/null; then
		return
	fi
	local url
	url="$(curl -fsSL "$EMUDECK_RELEASES_API" |
		jq -r '[.assets[] | select(.name | endswith(".AppImage") and (test("arm64|aarch64") | not)) | .browser_download_url][0] // empty')"
	if [[ -z "$url" ]]; then
		echo "could not find an EmuDeck AppImage in the latest release" >&2
		return 1
	fi
	local file="${APPS_DIR}/${url##*/}"
	if ! curl -fsSL "$url" -o "${file}.part"; then
		rm -f "${file}.part"
		echo "EmuDeck download failed; it will be retried at the next login" >&2
		return 1
	fi
	chmod 0755 "${file}.part"
	mv "${file}.part" "$file"
	extract_icon "$file"
	cat >"${DESKTOP_DIR}/EmuDeck.desktop" <<-EOF
		[Desktop Entry]
		Type=Application
		Name=EmuDeck
		Comment=Emulator setup and management
		Exec="${file}" %U
		Icon=emudeck
		Categories=Game;Utility;
		Terminal=false
	EOF
	echo "${file##*/}" >"$stamp"
	echo "EmuDeck placed at ${file}"
}

mkdir -p "$APPS_DIR" "$DESKTOP_DIR" "$ICON_DIR"
install_eden
install_emudeck
