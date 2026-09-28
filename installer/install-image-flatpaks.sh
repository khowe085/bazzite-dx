#!/usr/bin/bash
# Installs the flatpaks this image lists in its preinstall.d into the live image, next to Bazzite's
# own (build.sh), so the installer's install-flatpaks.ks copies them to the new system with the rest
# of /var/lib/flatpak. The image also installs them at boot (custom-flatpak-preinstall.service), but
# on a machine whose only network is a Wi-Fi set up in the first-boot setup, that boot is offline and
# `flatpak preinstall` finds nothing to do.
#
# `flatpak preinstall` marks what it installs as preinstalled, as the service would, so the service
# on the installed system skips these, and an app uninstalled later stays uninstalled.
#
# Not part of Bazzite's installer/: the Containerfile runs it after build.sh, with this repository's
# system_files/ at $IMAGE_FILES.
set -exo pipefail

IMAGE_FILES=${IMAGE_FILES:?}
BETA_REMOTE="$IMAGE_FILES/etc/flatpak/remotes.d/flathub-beta.flatpakrepo"
# Where flatpak reads preinstall files; overridable only for tests.
PREINSTALL_DIR="${PREINSTALL_DIR:-/usr/share/flatpak/preinstall.d}"

# bwrap writes /proc/sys/user/max_user_namespaces, which is mounted read-only (as in build.sh).
mount -o remount,rw /proc/sys

# Firefox beta comes from Flathub's beta remote, added as the image's preinstall unit adds it.
flatpak remote-add --system --if-not-exists flathub-beta "$BETA_REMOTE"

shopt -s nullglob
lists=("$IMAGE_FILES"/usr/share/flatpak/preinstall.d/*.preinstall)
if ((${#lists[@]} == 0)); then
    echo "No preinstall files in $IMAGE_FILES/usr/share/flatpak/preinstall.d" >&2
    exit 1
fi
install -Dm644 -t "$PREINSTALL_DIR" "${lists[@]}"
flatpak preinstall --system -y --noninteractive
