#!/usr/bin/bash
# First login: the per-user half of the Bazzite Portal choices this image makes. Each one is applied
# once and then left to its ujust/Portal toggle, so switching it off there sticks.
set -uo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/portal-tweaks"
mkdir -p "$STATE_DIR"

once() { # once <name> <command...>: run the command at every login until it has succeeded once
	local stamp="$STATE_DIR/$1"
	shift
	if [[ -e "$stamp" ]]; then
		return 0
	fi
	"$@" && touch "$stamp"
}

# "Enable globally upgrading FSR3.1+ to FSR4 - for RDNA3 graphics cards": the file
# `ujust global-fsr4-rdna3 enable` writes, and the one its status and disable look at.
enable_fsr4_rdna3() {
	mkdir -p "$HOME/.config/environment.d" &&
		echo "PROTON_FSR4_RDNA3_UPGRADE=1" >"$HOME/.config/environment.d/99-proton-fsr4-rdna3.conf"
}
# "Clean Steam desktop icons automatically" = `ujust steam-icons enable`. Enabled per user and not
# with `systemctl --global`, which `ujust steam-icons disable` could not undo.
enable_steam_icons_cleanup() { systemctl --user enable --now steam-icons-cleanup.service; }

rc=0
once fsr4-rdna3 enable_fsr4_rdna3 || rc=1
once steam-icons enable_steam_icons_cleanup || rc=1

# "JetBrains Toolbox" is a Homebrew install that takes minutes, and ublue-user-setup runs its hooks
# one after another, so it goes into a detached user unit. Follow it with:
#   journalctl --user -u jetbrains-toolbox-setup
# If an install from an earlier login is still running, the unit name is taken and systemd-run
# refuses. That is not a failure of this hook: there is nothing to add.
if [[ ! -e "$STATE_DIR/jetbrains-toolbox" ]]; then
	if ! systemd-run --user --collect --quiet --unit=jetbrains-toolbox-setup /usr/libexec/jetbrains-toolbox-setup; then
		echo "jetbrains-toolbox-setup was not started; it is probably still running from an earlier login"
	fi
fi
exit "$rc"
