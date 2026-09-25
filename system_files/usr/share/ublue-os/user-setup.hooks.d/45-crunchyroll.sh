#!/usr/bin/bash
# First login: the Bazzite Portal's "Crunchyroll" (ujust get-media-app Crunchyroll) without its GUI
# step. The Portal downloads the AppImage from github.com/aarron-lee/crunchyroll-linux and hands it
# to Gear Lever; the image ships the same AppImage (build_files/fetch-appimages.sh) and this puts it into
# ~/Applications/Crunchyroll.AppImage with a menu entry, the way 30-emudeck.sh places EmuDeck. Runs on
# every login: a newer image updates the copy it placed, and a copy that is moved, deleted or
# replaced stays that way.
set -euo pipefail

CRUNCHYROLL_IMAGE_DIR="${CRUNCHYROLL_IMAGE_DIR:-/usr/lib/crunchyroll}"
IMAGE_APPIMAGE="${IMAGE_APPIMAGE:-/usr/libexec/image-appimage}"

"$IMAGE_APPIMAGE" crunchyroll "$CRUNCHYROLL_IMAGE_DIR" Crunchyroll.AppImage '*[Cc]runchyroll*.AppImage' \
	Crunchyroll "Anime streaming" "AudioVideo;Video;"
