#!/usr/bin/bash
# Exercises system_files/usr/libexec/claude-distrobox-setup, the per-user creation of the "claude"
# distrobox, with a temp HOME and a stub distrobox.
# Run inside a container with the repo mounted at /src:
#   podman run --rm -v "$PWD:/src:ro,Z" <image> /src/tests/test-claude-distrobox-setup.sh
set -uo pipefail

SRC="${SRC:-/src}"
SETUP="$SRC/system_files/usr/libexec/claude-distrobox-setup"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home"

# `list` prints distrobox's real table, with an ubuntu row once $STATE/box exists.
# `assemble` modes (DBX_ASSEMBLE): ok (default) creates the box; noop exits 0 without creating, as
# distrobox does when the manifest lacks the section; fail-early fails before a box exists;
# fail-late creates the box and then fails, as a failed init or export does.
# `enter ... distrobox-export` fails when DBX_EXPORT_FAIL=1.
cat >"$tmp/bin/distrobox" <<'EOF'
#!/usr/bin/bash
echo "$*" >>"$CALLS"
case "$1" in
list)
	printf '%-12s | %-20s | %-18s | %-30s\n' ID NAME STATUS IMAGE
	printf '%-12s | %-20s | %-18s | %-30s\n' 0123456789ab ubuntu-dev "Up 2 hours" ghcr.io/ublue-os/fedora-toolbox:latest
	if [[ -e "$STATE/box" ]]; then
		printf '%-12s | %-20s | %-18s | %-30s\n' ba9876543210 ubuntu "Up 1 minute" ghcr.io/ublue-os/ubuntu-toolbox:latest
	fi
	;;
assemble)
	case "${DBX_ASSEMBLE:-ok}" in
	ok) touch "$STATE/box" ;;
	noop) ;;
	fail-early) exit 1 ;;
	fail-late) touch "$STATE/box"; exit 1 ;;
	esac
	;;
enter) [[ -n "${DBX_EXPORT_FAIL:-}" ]] && exit 1 ;;
esac
exit 0
EOF
chmod +x "$tmp/bin/distrobox"

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
run_setup() { # run_setup [VAR=value ...]
	env HOME="$tmp/home" XDG_STATE_HOME="$tmp/state" PATH="$tmp/bin:$PATH" \
		CALLS="$tmp/calls.log" STATE="$tmp" "$@" bash "$SETUP"
}
run_setup_without_xdg_state_home() {
	env -u XDG_STATE_HOME HOME="$tmp/home" PATH="$tmp/bin:$PATH" CALLS="$tmp/calls.log" STATE="$tmp" bash "$SETUP"
}
setup_fails() { ! run_setup "$@"; }
reset() {
	rm -rf "$tmp/home" "$tmp/state" "$tmp/box"
	mkdir -p "$tmp/home"
	: >"$tmp/calls.log"
}
stamp="$tmp/state/ubuntu-distrobox.created"
creating="$tmp/state/ubuntu-distrobox.creating"
ASSEMBLE='assemble create --file /usr/share/claude-distrobox/claude.ini --name ubuntu'
EXPORT='enter ubuntu -- distrobox-export --app claude-desktop'

echo "== first run"
reset
check "setup exits 0" run_setup
check "box assembled from the manifest under /usr, without --replace" grep -qx "$ASSEMBLE" "$tmp/calls.log"
check "app exported to the menu" grep -qx "$EXPORT" "$tmp/calls.log"
check "stamped" test -e "$stamp"
check "the in-progress marker is gone once the box is done" test ! -e "$creating"

echo "== XDG_STATE_HOME unset: state goes under ~/.local/state"
reset
check "setup exits 0" run_setup_without_xdg_state_home
check "stamped under ~/.local/state" test -e "$tmp/home/.local/state/ubuntu-distrobox.created"
reset
check "setup exits 0" run_setup

echo "== later runs"
: >"$tmp/calls.log"
check "setup exits 0" run_setup
check "distrobox is not even queried once stamped" test ! -s "$tmp/calls.log"

echo "== a box named ubuntu already exists (made by hand or via ujust)"
reset
touch "$tmp/box"
check "setup exits 0" run_setup
check "foreign box is neither assembled over nor entered" bash -c "! grep -q '^assemble\|^enter\|^rm' '$tmp/calls.log'"
check "stamped so later logins skip the check" test -e "$stamp"

echo "== a box with a similar name does not count as existing"
reset
check "setup exits 0" run_setup
check "ubuntu-dev in the list did not stop the assemble" grep -qx "$ASSEMBLE" "$tmp/calls.log"

echo "== assemble exits 0 without creating anything (manifest lacks the section)"
reset
check "setup fails" setup_fails DBX_ASSEMBLE=noop
check "not stamped, so the absence is not made permanent" test ! -e "$stamp"
check "no export attempted on a box that is not there" bash -c "! grep -q '^enter' '$tmp/calls.log'"

echo "== assemble fails before a box exists (no network for the image pull)"
reset
check "setup fails" setup_fails DBX_ASSEMBLE=fail-early
check "not stamped" test ! -e "$stamp"

echo "== assemble fails after creating the box, and the export keeps failing"
reset
check "setup fails" setup_fails DBX_ASSEMBLE=fail-late DBX_EXPORT_FAIL=1
check "not stamped" test ! -e "$stamp"
check "the box is never removed" bash -c "! grep -q '^rm' '$tmp/calls.log'"
check "the in-progress marker stays, so the next login knows the box is ours" test -e "$creating"
: >"$tmp/calls.log"
echo "== next login: our half-made box is finished, not rebuilt"
check "setup exits 0" run_setup
check "no second assemble (no second 1 GB download)" bash -c "! grep -q '^assemble' '$tmp/calls.log'"
check "entering re-runs the init hook and exports the app" grep -qx "$EXPORT" "$tmp/calls.log"
check "stamped after the successful retry" test -e "$stamp"

if ((fails > 0)); then
	echo "$fails check(s) failed"
	exit 1
fi
echo "all checks passed"
