#!/usr/bin/bash
# First login: the Bazzite Portal's "Crunchyroll" (ujust get-media-app Crunchyroll) without its GUI
# step. The Portal downloads the AppImage from the same project and hands it to Gear Lever; this
# puts it into ~/Applications with a menu entry, the way 30-emudeck.sh places EmuDeck. It runs
# after the other hooks because ublue-user-setup runs them one by one and this is a 110 MB download.
set -euo pipefail

APPS_DIR="${HOME}/Applications"
DESKTOP_DIR="${HOME}/.local/share/applications"
ICON_DIR="${HOME}/.local/share/icons/hicolor/256x256/apps"
RELEASES_API="https://api.github.com/repos/aarron-lee/crunchyroll-linux/releases/latest"
TARGET="${APPS_DIR}/Crunchyroll.AppImage"
STAMP="${APPS_DIR}/.crunchyroll.image-placed"

extract_icon() { # extract_icon <appimage>
	local tmp
	tmp="$(mktemp -d)"
	# .DirIcon is usually a symlink into the payload, so pull its target too.
	(
		cd "$tmp" &&
			"$1" --appimage-extract .DirIcon >/dev/null 2>&1 &&
			if [[ -L squashfs-root/.DirIcon ]]; then "$1" --appimage-extract "$(readlink squashfs-root/.DirIcon)" >/dev/null 2>&1; fi &&
			install -Dm0644 squashfs-root/.DirIcon "${ICON_DIR}/crunchyroll.png"
	) || echo "could not extract the Crunchyroll icon; the menu entry will use a generic one" >&2
	rm -rf "$tmp"
}

# Placed once per user. Afterwards Gear Lever (which moves the file out of ~/Applications) or the
# user own it, so a missing file is not a reason to download it again. Any Crunchyroll AppImage
# already there, whatever its exact name, came from the user.
if [[ -e "$STAMP" ]] || compgen -G "${APPS_DIR}/*[Cc]runchyroll*.AppImage" >/dev/null; then
	exit 0
fi
mkdir -p "$APPS_DIR" "$DESKTOP_DIR" "$ICON_DIR"

url="$(curl -fsSL "$RELEASES_API" |
	jq -r '[.assets[] | select(.name | endswith(".AppImage") and (test("arm64|aarch64") | not)) | .browser_download_url][0] // empty')"
if [[ -z "$url" ]]; then
	echo "could not find a Crunchyroll AppImage in the latest release" >&2
	exit 1
fi
if ! curl -fsSL "$url" -o "${TARGET}.part"; then
	rm -f "${TARGET}.part"
	echo "Crunchyroll download failed; it will be retried at the next login" >&2
	exit 1
fi
chmod 0755 "${TARGET}.part"
mv "${TARGET}.part" "$TARGET"
extract_icon "$TARGET"
cat >"${DESKTOP_DIR}/Crunchyroll.desktop" <<-EOF
	[Desktop Entry]
	Type=Application
	Name=Crunchyroll
	Comment=Anime streaming
	Exec="${TARGET}" %U
	Icon=crunchyroll
	Categories=AudioVideo;Video;
	Terminal=false
EOF
echo "${url##*/}" >"$STAMP"
echo "Crunchyroll placed at ${TARGET}"
