#!/usr/bin/bash
# Exercises system_files/usr/share/ublue-os/user-setup.hooks.d/40-claude-distrobox.sh, the launcher
# that starts /usr/libexec/claude-distrobox-setup detached, with a stub systemd-run.
# Run inside a container with the repo mounted at /src:
#   podman run --rm -v "$PWD:/src:ro,Z" <image> /src/tests/test-claude-distrobox-hook.sh
set -uo pipefail

SRC="${SRC:-/src}"
HOOK="$SRC/system_files/usr/share/ublue-os/user-setup.hooks.d/40-claude-distrobox.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home/.local/state" "$tmp/state"
# SYSTEMD_RUN_FAIL=1 mimics "Unit claude-distrobox-setup.service already exists".
cat >"$tmp/bin/systemd-run" <<'EOF'
#!/usr/bin/bash
echo "$*" >>"$CALLS"
[[ -n "${SYSTEMD_RUN_FAIL:-}" ]] && exit 1
exit 0
EOF
chmod +x "$tmp/bin/systemd-run"

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
LAUNCH='--user --collect --quiet --unit=claude-distrobox-setup /usr/libexec/claude-distrobox-setup'

echo "== first login"
: >"$tmp/calls.log"
check "hook exits 0" run_hook
check "setup started as a detached user unit, not run inline" grep -qx -- "$LAUNCH" "$tmp/calls.log"

echo "== a setup from an earlier login is still running"
: >"$tmp/calls.log"
check "hook still exits 0 when systemd-run refuses the duplicate unit" run_hook SYSTEMD_RUN_FAIL=1

echo "== box already created (stamp under XDG_STATE_HOME)"
: >"$tmp/calls.log"
touch "$tmp/state/claude-distrobox.created"
check "hook exits 0" run_hook
check "no unit is started" test ! -s "$tmp/calls.log"

echo "== XDG_STATE_HOME unset: the stamp is looked up under ~/.local/state"
: >"$tmp/calls.log"
check "hook exits 0" run_hook_without_xdg_state_home
check "stamp under XDG_STATE_HOME is not consulted, so the unit starts" grep -qx -- "$LAUNCH" "$tmp/calls.log"
: >"$tmp/calls.log"
touch "$tmp/home/.local/state/claude-distrobox.created"
check "hook exits 0" run_hook_without_xdg_state_home
check "stamp under ~/.local/state stops it" test ! -s "$tmp/calls.log"

if ((fails > 0)); then
	echo "$fails check(s) failed"
	exit 1
fi
echo "all checks passed"
