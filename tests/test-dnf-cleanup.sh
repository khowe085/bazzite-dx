#!/usr/bin/bash
# Exercises build_files/85-dnf-cleanup.sh, which removes the bookkeeping the build's dnf runs leave
# behind, against a scratch root.
# Run inside a container with the repo mounted at /src:
#   podman run --rm -v "$PWD:/src:ro,Z" <image> /src/tests/test-dnf-cleanup.sh
set -uo pipefail

SRC="${SRC:-/src}"
STEP="$SRC/build_files/85-dnf-cleanup.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
ROOT="$tmp/root"
LIBDNF5="$ROOT/usr/lib/sysimage/libdnf5"

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
run_step() { env DNF_CLEANUP_ROOT="$ROOT" bash "$STEP"; }
# What an image has after this build's dnf installs: the base ships no /var/lib/dnf, and its dnf5
# history and package state in /usr/lib/sysimage/libdnf5.
write_root() {
	rm -rf "$ROOT"
	mkdir -p "$ROOT/var/lib/dnf/repos/fedora-cff72538bc9825a4" "$LIBDNF5"
	printf '0 0 345600 2' >"$ROOT/var/lib/dnf/repos/fedora-cff72538bc9825a4/countme"
	for f in transaction_history.sqlite transaction_history.sqlite-shm transaction_history.sqlite-wal \
		packages.toml nevras.toml system.toml; do
		echo "$f" >"$LIBDNF5/$f"
	done
}

echo "== after the build's dnf installs"
write_root
check "step exits 0" run_step
check "dnf's usage counter and repo state under /var/lib/dnf are gone" test ! -e "$ROOT/var/lib/dnf"
check "so is dnf's install history" bash -c "! ls '$LIBDNF5'/transaction_history.sqlite* 2>/dev/null"
check "dnf's package state is kept" bash -c "test -f '$LIBDNF5/packages.toml' && test -f '$LIBDNF5/nevras.toml' && test -f '$LIBDNF5/system.toml'"

echo "== nothing left to remove"
check "step exits 0" run_step

if ((fails > 0)); then
	echo "$fails check(s) failed"
	exit 1
fi
echo "all checks passed"
