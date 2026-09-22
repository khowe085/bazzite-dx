#!/usr/bin/bash
# Exercises system_files/usr/libexec/portal-brew-casks-setup, the per-user install of the Homebrew
# casks this image takes from the Bazzite Portal (JetBrains Toolbox, LM Studio), with a temp HOME
# and a stub brew.
# Run inside a container with the repo mounted at /src:
#   podman run --rm -v "$PWD:/src:ro,Z" <image> /src/tests/test-portal-brew-casks-setup.sh
set -uo pipefail

SRC="${SRC:-/src}"
SETUP="$SRC/system_files/usr/libexec/portal-brew-casks-setup"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/brew/bin" "$tmp/home"
# Like the real one, brew is not on PATH until its `shellenv` output has been eval'd.
# BREW_FAIL names the subcommand that fails, BREW_FAIL_CASK the cask whose install fails.
cat >"$tmp/brew/bin/brew" <<'EOF'
#!/usr/bin/bash
echo "$*" >>"$CALLS"
[[ "${BREW_FAIL:-}" == "$1" ]] && exit 1
[[ "$1" == install && "${BREW_FAIL_CASK:-}" == "$3" ]] && exit 1
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
run_setup() { # run_setup [VAR=value ...] [-- script arguments]
	local vars=()
	while (($# > 0)) && [[ "$1" != -- ]]; do
		vars+=("$1")
		shift
	done
	(($# > 0)) && shift
	env HOME="$tmp/home" XDG_STATE_HOME="$tmp/state" CALLS="$tmp/calls.log" \
		PORTAL_BREW="$tmp/brew/bin/brew" "${vars[@]}" bash "$SETUP" "$@"
}
run_setup_without_xdg_state_home() {
	env -u XDG_STATE_HOME HOME="$tmp/home" CALLS="$tmp/calls.log" PORTAL_BREW="$tmp/brew/bin/brew" bash "$SETUP"
}
setup_fails() { ! run_setup "$@"; }
reset() {
	rm -rf "$tmp/home" "$tmp/state"
	mkdir -p "$tmp/home"
	: >"$tmp/calls.log"
}
calls() { tr '\n' ';' <"$tmp/calls.log"; }
toolbox="$tmp/state/portal-tweaks/jetbrains-toolbox"
lmstudio="$tmp/state/portal-tweaks/lm-studio"
PREPARE='shellenv;trust ublue-os/tap;tap ublue-os/tap;'

echo "== first run"
reset
check "setup exits 0" run_setup
# The command behind the Portal's entries, step by step, with both casks.
check "runs the Portal's brew steps in its order, once for both casks" test "$(calls)" = "${PREPARE}install --cask jetbrains-toolbox-linux;install --cask lm-studio-linux;"
check "JetBrains Toolbox stamped under the name earlier images used" test -e "$toolbox"
check "LM Studio stamped" test -e "$lmstudio"

echo "== later runs"
: >"$tmp/calls.log"
check "setup exits 0" run_setup
check "brew is not called once everything is stamped" test ! -s "$tmp/calls.log"

echo "== a machine that got JetBrains Toolbox from an earlier image"
reset
mkdir -p "$(dirname "$toolbox")"
touch "$toolbox"
check "setup exits 0" run_setup
check "only LM Studio is installed" test "$(calls)" = "${PREPARE}install --cask lm-studio-linux;"

echo "== --pending: the login hook's question, answered without touching brew"
reset
check "something to do on a fresh profile" run_setup -- --pending
check "brew is left alone" test ! -s "$tmp/calls.log"
check "setup exits 0" run_setup
: >"$tmp/calls.log"
check "nothing to do once both are stamped" setup_fails -- --pending
check "brew is left alone" test ! -s "$tmp/calls.log"

echo "== Homebrew is not there yet (brew-setup.service has not finished)"
reset
check "setup fails" setup_fails PORTAL_BREW="$tmp/no-such/brew"
check "nothing stamped, so the next login tries again" test ! -e "$toolbox" -a ! -e "$lmstudio"

for step in shellenv trust tap; do
	echo "== brew $step fails"
	reset
	check "setup fails" setup_fails BREW_FAIL="$step"
	check "nothing stamped" test ! -e "$toolbox" -a ! -e "$lmstudio"
	check "nothing is installed from a tap that is not set up" bash -c "! grep -q '^install' '$tmp/calls.log'"
done

echo "== one cask fails to install (download error)"
reset
check "setup fails" setup_fails BREW_FAIL_CASK=jetbrains-toolbox-linux
check "the other cask is still installed and stamped" test -e "$lmstudio"
check "the failed one is not stamped" test ! -e "$toolbox"
: >"$tmp/calls.log"
check "next login: setup exits 0" run_setup
check "and only the missing cask is installed" test "$(calls)" = "${PREPARE}install --cask jetbrains-toolbox-linux;"

echo "== XDG_STATE_HOME unset: the stamps go under ~/.local/state"
reset
check "setup exits 0" run_setup_without_xdg_state_home
check "stamped under ~/.local/state" test -e "$tmp/home/.local/state/portal-tweaks/lm-studio"

if ((fails > 0)); then
	echo "$fails check(s) failed"
	exit 1
fi
echo "all checks passed"
