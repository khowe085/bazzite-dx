#!/usr/bin/bash
# Exercises system_files/usr/share/ublue-os/user-setup.hooks.d/35-portal-tweaks.sh, the per-user
# half of the Bazzite Portal choices, with a temp HOME and stub systemctl and systemd-run.
# Run inside a container with the repo mounted at /src:
#   podman run --rm -v "$PWD:/src:ro,Z" <image> /src/tests/test-portal-tweaks-hook.sh
set -uo pipefail

SRC="${SRC:-/src}"
HOOK="$SRC/system_files/usr/share/ublue-os/user-setup.hooks.d/35-portal-tweaks.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
cat >"$tmp/bin/systemctl" <<'EOF'
#!/usr/bin/bash
echo "systemctl $*" >>"$CALLS"
[[ -n "${SYSTEMCTL_FAIL:-}" ]] && exit 1
exit 0
EOF
# SYSTEMD_RUN_FAIL=1 mimics "Unit jetbrains-toolbox-setup.service already exists".
cat >"$tmp/bin/systemd-run" <<'EOF'
#!/usr/bin/bash
echo "systemd-run $*" >>"$CALLS"
[[ -n "${SYSTEMD_RUN_FAIL:-}" ]] && exit 1
exit 0
EOF
chmod +x "$tmp/bin/"*

fails=0
check() {
	local desc=$1
	shift
	if "$@" >/dev/null 2>&1; then
		echo "ok   - $desc"
	else
		echo "FAIL - $desc"
		fails=$((fails + 1))
	fi
}
# XDG_STATE_HOME deliberately is not $HOME/.local/state, so the variable and its fallback are told apart.
run_hook() { # run_hook [VAR=value ...]
	env HOME="$tmp/home" XDG_STATE_HOME="$tmp/state" PATH="$tmp/bin:$PATH" CALLS="$tmp/calls.log" "$@" bash "$HOOK"
}
run_hook_without_xdg_state_home() {
	env -u XDG_STATE_HOME HOME="$tmp/home" PATH="$tmp/bin:$PATH" CALLS="$tmp/calls.log" bash "$HOOK"
}
hook_fails() { ! run_hook "$@"; }
reset() {
	rm -rf "$tmp/home" "$tmp/state"
	mkdir -p "$tmp/home"
	: >"$tmp/calls.log"
}
called() { grep -qx -- "$1" "$tmp/calls.log"; }
never_called() { ! grep -q -- "$1" "$tmp/calls.log"; }
fsr4="$tmp/home/.config/environment.d/99-proton-fsr4-rdna3.conf"
STEAM_ICONS='systemctl --user enable --now steam-icons-cleanup.service'
TOOLBOX='systemd-run --user --collect --quiet --unit=jetbrains-toolbox-setup /usr/libexec/jetbrains-toolbox-setup'

echo "== first login"
reset
check "hook exits 0" run_hook
check "FSR4 upgrade for RDNA3 is switched on where ujust global-fsr4-rdna3 keeps it" test "$(cat "$fsr4")" = "PROTON_FSR4_RDNA3_UPGRADE=1"
check "Steam desktop icon cleanup is enabled for this user, as ujust steam-icons enable does" called "$STEAM_ICONS"
check "JetBrains Toolbox install is started as a detached user unit, not run inline" called "$TOOLBOX"

echo "== later logins, after both were switched off again with ujust or the Portal"
rm -f "$fsr4"
: >"$tmp/calls.log"
check "hook exits 0" run_hook
check "the FSR4 file is not brought back" test ! -e "$fsr4"
check "the icon cleanup is not enabled again" never_called 'steam-icons-cleanup'
check "the Toolbox install is started again while it has not succeeded" called "$TOOLBOX"

echo "== JetBrains Toolbox is installed (the setup script left its stamp)"
touch "$tmp/state/portal-tweaks/jetbrains-toolbox"
: >"$tmp/calls.log"
check "hook exits 0" run_hook
check "nothing is started" test ! -s "$tmp/calls.log"

echo "== an install from an earlier login is still running"
reset
check "hook still exits 0 when systemd-run refuses the duplicate unit" run_hook SYSTEMD_RUN_FAIL=1

echo "== enabling the icon cleanup fails"
reset
check "hook reports the failure" hook_fails SYSTEMCTL_FAIL=1
check "the FSR4 switch is still applied" test -e "$fsr4"
check "the Toolbox install is still started" called "$TOOLBOX"
: >"$tmp/calls.log"
check "next login: hook exits 0" run_hook
check "the icon cleanup is tried again" called "$STEAM_ICONS"
rm -f "$fsr4"
: >"$tmp/calls.log"
check "login after that: hook exits 0" run_hook
check "and only that once" never_called 'steam-icons-cleanup'
check "the FSR4 switch was not re-applied on the way" test ! -e "$fsr4"

echo "== XDG_STATE_HOME unset: state goes under ~/.local/state"
reset
check "hook exits 0" run_hook_without_xdg_state_home
rm -f "$fsr4"
: >"$tmp/calls.log"
check "hook exits 0" run_hook_without_xdg_state_home
check "the first run is remembered there" test ! -e "$fsr4"
touch "$tmp/home/.local/state/portal-tweaks/jetbrains-toolbox"
: >"$tmp/calls.log"
check "hook exits 0" run_hook_without_xdg_state_home
check "the Toolbox stamp is looked up there too" test ! -s "$tmp/calls.log"

if ((fails > 0)); then
	echo "$fails check(s) failed"
	exit 1
fi
echo "all checks passed"
