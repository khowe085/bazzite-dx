#!/usr/bin/bash
set -euxo pipefail

# Task Manager TMOG from its Linux tar.gz (tmog.org/rtm). The site publishes no checksum, so the
# SHA-256 of the file as first downloaded is pinned, since the image runs it as root: this version
# uploaded again, or taken down, fails the build. Nothing notices a new release (the site has no
# "latest" link); taking one means updating both values here. The menu entry and polkit action that
# run it as root are in system_files.
TMOG_VERSION=1.0.0
TMOG_SHA256="${TMOG_SHA256:-a147c613d4a6f5c0ec16eaf52965593de523f9f0231e09c241460cc63352f325}"
PREFIX="${TMOG_PREFIX:-/usr}"

name="TaskManagerOG-${TMOG_VERSION}-linux-x86_64"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
curl -fsSL --retry 3 -o "$work/$name.tar.gz" "https://tmog.org/rtm/downloads/$name.tar.gz"
echo "${TMOG_SHA256}  $work/$name.tar.gz" | sha256sum -c -
tar -xzf "$work/$name.tar.gz" -C "$work"
src="$work/$name"

# The task manager only: the tarball's XScreenSaver engine, its registration script and their menu
# entries are for desktops that run XScreenSaver, which KDE does not.
install -Dm0755 "$src/bin/tmog-task-manager" "$PREFIX/bin/tmog-task-manager"
for icon in "$src"/share/icons/hicolor/*/apps/tmog-task-manager.png; do
	install -Dm0644 "$icon" "$PREFIX/share/icons/hicolor/${icon#"$src/share/icons/hicolor/"}"
done
install -Dm0644 -t "$PREFIX/share/metainfo" "$src/share/metainfo/com.tmog.taskmanager.metainfo.xml"
install -Dm0644 -t "$PREFIX/share/doc/tmog" "$src"/share/doc/tmog/*
# The base's icon cache does not list the new icon, and with every file in the image dated alike
# nothing marks the cache as stale, so Qt would trust it; refresh it as a package install does.
gtk-update-icon-cache -qtf "$PREFIX/share/icons/hicolor"
# kglobalacceld takes default shortcuts (X-KDE-Shortcuts) only from desktop files in this directory,
# not from the menu's; Dolphin and Spectacle link theirs the same way.
install -d "$PREFIX/share/kglobalaccel"
ln -sfn /usr/share/applications/com.tmog.taskmanager.desktop "$PREFIX/share/kglobalaccel/com.tmog.taskmanager.desktop"
