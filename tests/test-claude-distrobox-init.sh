#!/usr/bin/bash
# Exercises system_files/usr/libexec/claude-distrobox-init, the script the "claude" distrobox runs
# as its init hook, with stub curl/gpg/apt-get/dpkg-query and redirected keyring/sources paths.
# Run inside a container with the repo mounted at /src:
#   podman run --rm -v "$PWD:/src:ro,Z" <image> /src/tests/test-claude-distrobox-init.sh
set -uo pipefail

SRC="${SRC:-/src}"
INIT="$SRC/system_files/usr/libexec/claude-distrobox-init"
GOOD_FPR=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

# curl writes a fake key; gpg reports whatever fingerprint GPG_FPR names; apt-get only logs.
cat >"$tmp/bin/curl" <<'EOF'
#!/usr/bin/bash
out=""; url=""
while [[ $# -gt 0 ]]; do
	case "$1" in
	-o) out="$2"; shift ;;
	-*o) out="$2"; shift ;;
	http*) url="$1" ;;
	esac
	shift
done
echo "curl $url" >>"$CALLS"
[[ -n "${CURL_FAIL:-}" ]] && exit 22
echo "FAKE-KEY" >"$out"
EOF
cat >"$tmp/bin/gpg" <<'EOF'
#!/usr/bin/bash
echo "gpg $*" >>"$CALLS"
echo "pub:-:255:22:BAA929FF1A7ECACE:1700000000:::-:::scESC:::::ed25519:::0:"
echo "fpr:::::::::${GPG_FPR}:"
# GPG_EXTRA_KEY=1: the file is a bundle that also carries somebody else's key.
if [[ -n "${GPG_EXTRA_KEY:-}" ]]; then
	echo "pub:-:255:22:1111111111111111:1700000000:::-:::scESC:::::ed25519:::0:"
	echo "fpr:::::::::2222222222222222222222222222222222222222:"
fi
EOF
cat >"$tmp/bin/apt-get" <<'EOF'
#!/usr/bin/bash
echo "apt-get $*" >>"$CALLS"
EOF
# dpkg-query answers for the claude-desktop package: "installed" when DPKG_INSTALLED=1, else unknown.
cat >"$tmp/bin/dpkg-query" <<'EOF'
#!/usr/bin/bash
echo "dpkg-query $*" >>"$CALLS.dpkg"
[[ -n "${DPKG_INSTALLED:-}" ]] && { printf 'installed'; exit 0; }
echo "dpkg-query: no packages found matching claude-desktop" >&2
exit 1
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
run_init() { # run_init [VAR=value ...]
	env PATH="$tmp/bin:$PATH" CALLS="$tmp/calls.log" GPG_FPR="$GOOD_FPR" \
		CLAUDE_KEYRING="$tmp/keyrings/claude.asc" CLAUDE_SOURCES="$tmp/sources/claude-desktop.list" \
		"$@" bash "$INIT"
}
init_fails() { ! run_init "$@"; }
reset() {
	rm -rf "$tmp/keyrings" "$tmp/sources"
	mkdir -p "$tmp/sources"
	: >"$tmp/calls.log"
}

echo "== first start of the box"
reset
check "init exits 0" run_init
check "key fetched from Anthropic" grep -qx 'curl https://downloads.claude.ai/claude-desktop/key.asc' "$tmp/calls.log"
check "keyring installed" grep -qx 'FAKE-KEY' "$tmp/keyrings/claude.asc"
check "apt source is the documented line, signed by that keyring" grep -qx "deb \[arch=amd64,arm64 signed-by=$tmp/keyrings/claude.asc\] https://downloads.claude.ai/claude-desktop/apt/stable stable main" "$tmp/sources/claude-desktop.list"
check "apt-get update runs before the install" bash -c "grep -n '^apt-get' '$tmp/calls.log' | head -1 | grep -q 'apt-get update'"
check "claude-desktop installed with apt, as the docs describe" grep -qx 'apt-get install -y claude-desktop' "$tmp/calls.log"

echo "== later starts (package already installed)"
reset
check "init exits 0" run_init DPKG_INSTALLED=1
check "nothing is downloaded or installed again" test ! -s "$tmp/calls.log"
check "the guard asked dpkg about the package, not PATH about a binary" grep -q 'claude-desktop' "$tmp/calls.log.dpkg"

echo "== signing key with an unexpected fingerprint"
reset
check "init fails" init_fails GPG_FPR=0000000000000000000000000000000000000000
check "untrusted key is not installed" test ! -e "$tmp/keyrings/claude.asc"
check "no apt source written" test ! -e "$tmp/sources/claude-desktop.list"
check "nothing installed" bash -c "! grep -q '^apt-get' '$tmp/calls.log'"

echo "== key file carries Anthropic's key plus a second one"
reset
check "init fails" init_fails GPG_EXTRA_KEY=1
check "the bundle is not installed as a keyring" test ! -e "$tmp/keyrings/claude.asc"
check "nothing installed" bash -c "! grep -q '^apt-get' '$tmp/calls.log'"

echo "== key download fails"
reset
check "init fails" init_fails CURL_FAIL=1
check "no keyring, no apt source" bash -c "test ! -e '$tmp/keyrings/claude.asc' && test ! -e '$tmp/sources/claude-desktop.list'"
check "nothing installed" bash -c "! grep -q '^apt-get' '$tmp/calls.log'"

if ((fails > 0)); then
	echo "$fails check(s) failed"
	exit 1
fi
echo "all checks passed"
