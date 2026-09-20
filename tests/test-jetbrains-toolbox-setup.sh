#!/usr/bin/bash
# Exercises system_files/usr/libexec/jetbrains-toolbox-setup, the per-user JetBrains Toolbox
# install through Homebrew, with a temp HOME and a stub brew.
# Run inside a container with the repo mounted at /src:
#   podman run --rm -v "$PWD:/src:ro,Z" <image> /src/tests/test-jetbrains-toolbox-setup.sh
set -uo pipefail

SRC="${SRC:-/src}"
SETUP="$SRC/system_files/usr/libexec/jetbrains-toolbox-setup"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/brew/bin" "$tmp/home"
# Like the real one, brew is not on PATH until its `shellenv` output has been eval'd.
# BREW_FAIL names the subcommand that fails.
cat >"$tmp/brew/bin/brew" <<'EOF'
#!/usr/bin/bash
echo "$*" >>"$CALLS"
[[ "${BREW_FAIL:-}" == "$1" ]] && exit 1
if [[ "$1" == shellenv ]]; then
	echo "export PATH=\"$(dirname "$0"):\$PATH\";"
fi
exit 0
EOF
chmod +x "$tmp/brew/bin/brew"

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
	env HOME="$tmp/home" XDG_STATE_HOME="$tmp/state" CALLS="$tmp/calls.log" \
		JETBRAINS_TOOLBOX_BREW="$tmp/brew/bin/brew" "$@" bash "$SETUP"
}
run_setup_without_xdg_state_home() {
	env -u XDG_STATE_HOME HOME="$tmp/home" CALLS="$tmp/calls.log" JETBRAINS_TOOLBOX_BREW="$tmp/brew/bin/brew" bash "$SETUP"
}
setup_fails() { ! run_setup "$@"; }
reset() {
	rm -rf "$tmp/home" "$tmp/state"
	mkdir -p "$tmp/home"
	: >"$tmp/calls.log"
}
stamp="$tmp/state/portal-tweaks/jetbrains-toolbox"

echo "== first run"
reset
check "setup exits 0" run_setup
# The command behind the Portal's "JetBrains Toolbox" entry, step by step.
check "runs the Portal's brew steps in its order" test "$(tr '\n' ';' <"$tmp/calls.log")" = "shellenv;trust ublue-os/tap;tap ublue-os/tap;install --cask jetbrains-toolbox-linux;"
check "stamped where the login hook looks" test -e "$stamp"

echo "== later runs"
: >"$tmp/calls.log"
check "setup exits 0" run_setup
check "brew is not called once stamped" test ! -s "$tmp/calls.log"

echo "== Homebrew is not there yet (brew-setup.service has not finished)"
reset
check "setup fails" setup_fails JETBRAINS_TOOLBOX_BREW="$tmp/no-such/brew"
check "not stamped, so the next login tries again" test ! -e "$stamp"

for step in shellenv trust tap install; do
	echo "== brew $step fails"
	reset
	check "setup fails" setup_fails BREW_FAIL="$step"
	check "not stamped, so the next login tries again" test ! -e "$stamp"
done
reset
check "setup fails when the tap cannot be added" setup_fails BREW_FAIL=tap
check "and the steps after it are not run" bash -c "! grep -q '^install' '$tmp/calls.log'"

echo "== XDG_STATE_HOME unset: the stamp goes under ~/.local/state"
reset
check "setup exits 0" run_setup_without_xdg_state_home
check "stamped under ~/.local/state" test -e "$tmp/home/.local/state/portal-tweaks/jetbrains-toolbox"

if ((fails > 0)); then
	echo "$fails check(s) failed"
	exit 1
fi
echo "all checks passed"
