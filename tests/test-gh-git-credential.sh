#!/usr/bin/bash
# Exercises build_files/82-gh-git-credential.sh against a scratch system gitconfig (GIT_CONFIG_SYSTEM).
# Run inside a container with the repo mounted at /src:
#   podman run --rm -v "$PWD:/src:ro,Z" <image> /src/tests/test-gh-git-credential.sh
set -uo pipefail

SRC="${SRC:-/src}"
STEP="$SRC/build_files/82-gh-git-credential.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

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
sysgit() { GIT_CONFIG_SYSTEM="$tmp/gitconfig" git config --system "$@"; }
helpers() { sysgit --get-all "credential.$1.helper" | paste -sd'|'; }
GH='|!/usr/bin/gh auth git-credential'

echo "== system git config"
# Settings already there (the signing step runs first) have to survive.
printf '[commit]\n\tgpgsign = true\n' >"$tmp/gitconfig"
check "build step exits 0" env GIT_CONFIG_SYSTEM="$tmp/gitconfig" bash "$STEP"
check "github.com: the list is cleared, then gh" test "$(helpers https://github.com)" = "$GH"
check "gist.github.com: the same" test "$(helpers https://gist.github.com)" = "$GH"
check "settings already in the file survive" test "$(sysgit --type=bool commit.gpgsign)" = true
check "second run exits 0" env GIT_CONFIG_SYSTEM="$tmp/gitconfig" bash "$STEP"
check "second run adds nothing" test "$(helpers https://github.com)" = "$GH"
sysgit --add credential.https://github.com.helper stale
check "a helper added before is replaced" env GIT_CONFIG_SYSTEM="$tmp/gitconfig" bash "$STEP"
check "and gone afterwards" test "$(helpers https://github.com)" = "$GH"
check "build step creates the system config when there is none" env GIT_CONFIG_SYSTEM="$tmp/fresh" bash "$STEP"

echo "== which helpers git runs"
# A helper from a lower-priority config must not run for github.com: the empty value resets the list.
# It only logs that it ran; gh (absent, or not logged in here) answers nothing, so fill fails.
printf '[credential]\n\thelper = "!f() { echo ran >>%s/pre.log; }; f"\n' "$tmp" >"$tmp/combined"
cat "$tmp/gitconfig" >>"$tmp/combined"
fill() {
	printf 'url=%s\n\n' "$1" | env GIT_CONFIG_SYSTEM="$tmp/combined" GIT_CONFIG_GLOBAL=/dev/null \
		GIT_TERMINAL_PROMPT=0 GIT_ASKPASS= SSH_ASKPASS= GH_TOKEN= GITHUB_TOKEN= git credential fill
}
fill https://github.com/owner/repo >/dev/null 2>&1
check "the earlier helper is skipped for github.com" test ! -e "$tmp/pre.log"
fill https://gist.github.com/owner/1 >/dev/null 2>&1
check "and for gist.github.com" test ! -e "$tmp/pre.log"
fill https://example.com/repo >/dev/null 2>&1
check "other hosts still use it" test -s "$tmp/pre.log"

if ((fails > 0)); then
	echo "$fails check(s) failed"
	exit 1
fi
echo "all checks passed"
