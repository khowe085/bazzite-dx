#!/usr/bin/bash
# Exercises system_files/usr/libexec/claude-distrobox-init, the script the "ubuntu" distrobox runs
# as its init hook, with stub curl/gpg/apt-get/dpkg-query/luarocks, redirected keyring/sources paths, and
# scratch roots standing in for the host (/run/host) and the box's own /.
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
[[ -z "${APT_FAIL:-}" ]]
EOF
# dpkg-query answers "installed" for every package when DPKG_INSTALLED=1, except the ones named in
# DPKG_MISSING; otherwise nothing is installed.
cat >"$tmp/bin/dpkg-query" <<'EOF'
#!/usr/bin/bash
echo "dpkg-query $*" >>"$CALLS.dpkg"
package="${!#}"
if [[ -n "${DPKG_INSTALLED:-}" && " ${DPKG_MISSING:-} " != *" $package "* ]]; then
	printf 'installed'
	exit 0
fi
echo "dpkg-query: no packages found matching $package" >&2
exit 1
EOF
# luarocks: `show busted` succeeds when DPKG_INSTALLED=1 (everything present) unless BUSTED_MISSING=1;
# installs are logged, and fail with LUAROCKS_FAIL=1.
cat >"$tmp/bin/luarocks" <<'EOF'
#!/usr/bin/bash
if [[ " $* " == *" show "* ]]; then
	[[ -n "${DPKG_INSTALLED:-}" && -z "${BUSTED_MISSING:-}" ]]
	exit
fi
echo "luarocks $*" >>"$CALLS"
[[ -z "${LUAROCKS_FAIL:-}" ]]
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
		CLAUDE_HOST_ROOT="$HOSTROOT" CLAUDE_BOX_ROOT="$BOXROOT" "$@" bash "$INIT"
}
init_fails() { ! run_init "$@"; }
HOSTROOT="$tmp/host"
BOXROOT="$tmp/box"
DROPIN=etc/ssh/ssh_config.d/60-1password-agent.conf
# The host as this image makes it: 1Password under /usr/lib/opt, the system Git settings of
# 25-1password-git-signing.sh and the SSH agent drop-in from system_files. The box starts empty.
reset() {
	rm -rf "$tmp/keyrings" "$tmp/sources" "$HOSTROOT" "$BOXROOT"
	mkdir -p "$tmp/sources" "$HOSTROOT/usr/lib/opt/1Password" "$HOSTROOT/etc/ssh/ssh_config.d" "$BOXROOT"
	printf '#!/bin/sh\n' >"$HOSTROOT/usr/lib/opt/1Password/op-ssh-sign"
	mkdir -p "$HOSTROOT/usr/bin"
	for tool in gh tea; do
		printf '#!/bin/sh\n' >"$HOSTROOT/usr/bin/$tool"
		chmod +x "$HOSTROOT/usr/bin/$tool"
	done
	git config --file "$HOSTROOT/etc/gitconfig" gpg.format ssh
	git config --file "$HOSTROOT/etc/gitconfig" gpg.ssh.program /opt/1Password/op-ssh-sign
	git config --file "$HOSTROOT/etc/gitconfig" commit.gpgsign true
	cp "$SRC/system_files/$DROPIN" "$HOSTROOT/$DROPIN"
	: >"$tmp/calls.log"
}
boxgit() { git config --file "$BOXROOT/etc/gitconfig" "$@"; }
check_host_tools() {
	check "gh in the box is the host's, where Git's credential helper looks for it" test "$(readlink "$BOXROOT/usr/bin/gh")" = "$HOSTROOT/usr/bin/gh"
	check "tea in the box is the host's" test "$(readlink "$BOXROOT/usr/bin/tea")" = "$HOSTROOT/usr/bin/tea"
}
check_signing() {
	check "the box reaches 1Password's signer where the host's Git settings name it" test "$(readlink "$BOXROOT/opt/1Password")" = "$HOSTROOT/usr/lib/opt/1Password"
	check "Git in the box signs with SSH" test "$(boxgit --get gpg.format)" = ssh
	check "through 1Password's signer" test "$(boxgit --get gpg.ssh.program)" = /opt/1Password/op-ssh-sign
	check "and signs commits by default" test "$(boxgit --get commit.gpgsign)" = true
	check "ssh in the box uses 1Password's agent, with the host's drop-in" cmp -s "$HOSTROOT/$DROPIN" "$BOXROOT/$DROPIN"
}

echo "== first start of the box"
reset
check "init exits 0" run_init
check "key fetched from Anthropic" grep -qx 'curl https://downloads.claude.ai/claude-desktop/key.asc' "$tmp/calls.log"
check "keyring installed" grep -qx 'FAKE-KEY' "$tmp/keyrings/claude.asc"
check "apt source is the documented line, signed by that keyring" grep -qx "deb \[arch=amd64,arm64 signed-by=$tmp/keyrings/claude.asc\] https://downloads.claude.ai/claude-desktop/apt/stable stable main" "$tmp/sources/claude-desktop.list"
check "apt-get update runs before the install" bash -c "grep -n '^apt-get' '$tmp/calls.log' | head -1 | grep -q 'apt-get update'"
check "claude-desktop installed with apt, as the docs describe" grep -qx 'apt-get install -y claude-desktop' "$tmp/calls.log"
check "Lua 5.1 with its headers, LuaRocks, luacheck and a compiler installed from Ubuntu" grep -qx 'apt-get install -y lua5.1 liblua5.1-0-dev luarocks lua-check build-essential' "$tmp/calls.log"
check "the package lists are updated once" test "$(grep -c '^apt-get update' "$tmp/calls.log")" = 1
check "busted installed from LuaRocks for Lua 5.1" grep -qx 'luarocks --lua-version 5.1 install busted' "$tmp/calls.log"
check_signing
check_host_tools

echo "== later starts (package already installed)"
reset
check "init exits 0" run_init DPKG_INSTALLED=1
check "nothing is downloaded or installed again" test ! -s "$tmp/calls.log"
check "the guard asked dpkg about the package, not PATH about a binary" grep -q 'claude-desktop' "$tmp/calls.log.dpkg"
check_signing
check_host_tools

echo "== a box from before the Lua tools (Claude Desktop installed, the rest missing)"
reset
check "init exits 0" run_init DPKG_INSTALLED=1 DPKG_MISSING="lua5.1 lua-check" BUSTED_MISSING=1
check "Claude Desktop's repository is left alone" bash -c "! grep -q '^curl' '$tmp/calls.log'"
check "only the missing packages are installed, after an update" test "$(grep '^apt-get' "$tmp/calls.log" | paste -sd'|')" = 'apt-get update|apt-get install -y lua5.1 lua-check'
check "busted installed" grep -qx 'luarocks --lua-version 5.1 install busted' "$tmp/calls.log"

echo "== only busted missing"
reset
check "init exits 0" run_init DPKG_INSTALLED=1 BUSTED_MISSING=1
check "busted installed" grep -qx 'luarocks --lua-version 5.1 install busted' "$tmp/calls.log"
check "apt is not touched" bash -c "! grep -q '^apt-get' '$tmp/calls.log'"

echo "== offline start of such a box"
reset
check "init still exits 0, so the box starts" run_init DPKG_INSTALLED=1 DPKG_MISSING=lua5.1 BUSTED_MISSING=1 APT_FAIL=1 LUAROCKS_FAIL=1
check "signing is still set up" test "$(boxgit --get gpg.format)" = ssh

echo "== a start after an earlier one set up signing"
boxgit user.name "Box Only"
check "init exits 0" run_init DPKG_INSTALLED=1
check_signing
check "each Git setting is there once" test "$(boxgit --get-all gpg.ssh.program | wc -l)" = 1
check "the box's own Git settings are kept" test "$(boxgit --get user.name)" = "Box Only"

echo "== the box's Git config holds a key twice (git config --system --add in the box)"
reset
mkdir -p "$BOXROOT/etc"
boxgit --add commit.gpgsign false
boxgit --add commit.gpgsign false
check "init exits 0" run_init DPKG_INSTALLED=1
check "the key holds the host's value, once" test "$(boxgit --get-all commit.gpgsign)" = true

echo "== the host stops setting one of the keys"
boxgit gpg.format ssh
git config --file "$HOSTROOT/etc/gitconfig" --unset commit.gpgsign
check "init exits 0" run_init DPKG_INSTALLED=1
check "the box drops it too" bash -c "! git config --file '$BOXROOT/etc/gitconfig' --get commit.gpgsign"
check "and keeps the others" test "$(boxgit --get gpg.format)" = ssh

echo "== the box's Git config cannot be written (a stale lock)"
reset
mkdir -p "$BOXROOT/etc"
: >"$BOXROOT/etc/gitconfig.lock"
check "init still exits 0, so the box starts" run_init DPKG_INSTALLED=1
check "and says why" bash -c "env PATH='$tmp/bin:$PATH' CALLS='$tmp/calls.log' CLAUDE_HOST_ROOT='$HOSTROOT' CLAUDE_BOX_ROOT='$BOXROOT' DPKG_INSTALLED=1 bash '$INIT' 2>&1 | grep -q 'could not set'"
check "the rest is still done" cmp -s "$HOSTROOT/$DROPIN" "$BOXROOT/$DROPIN"
rm -f "$BOXROOT/etc/gitconfig.lock"

echo "== first start, the box's Git config cannot be written"
reset
mkdir -p "$BOXROOT/etc"
: >"$BOXROOT/etc/gitconfig.lock"
check "Claude Desktop is still installed" bash -c "$(declare -f run_init); tmp='$tmp' GOOD_FPR='$GOOD_FPR' HOSTROOT='$HOSTROOT' BOXROOT='$BOXROOT' INIT='$INIT'; run_init && grep -qx 'apt-get install -y claude-desktop' '$tmp/calls.log'"

echo "== 1Password installed inside the box itself"
reset
mkdir -p "$BOXROOT/opt/1Password"
check "init exits 0" run_init DPKG_INSTALLED=1
check "the box's own 1Password is left alone" bash -c "test -d '$BOXROOT/opt/1Password' && test ! -L '$BOXROOT/opt/1Password'"

echo "== gh installed inside the box itself"
reset
mkdir -p "$BOXROOT/usr/bin"
printf 'ubuntu gh\n' >"$BOXROOT/usr/bin/gh"
check "init exits 0" run_init DPKG_INSTALLED=1
check "the box's own gh is left alone" grep -qx 'ubuntu gh' "$BOXROOT/usr/bin/gh"
check "tea is still linked" test -L "$BOXROOT/usr/bin/tea"

echo "== tea in the box is a link of the box's own (e.g. update-alternatives)"
reset
mkdir -p "$BOXROOT/usr/bin"
ln -s /etc/alternatives/tea "$BOXROOT/usr/bin/tea"
check "init exits 0" run_init DPKG_INSTALLED=1
check "that link is left alone" test "$(readlink "$BOXROOT/usr/bin/tea")" = /etc/alternatives/tea

echo "== a host without 1Password, its Git settings or the drop-in"
reset
rm -rf "$HOSTROOT"
mkdir -p "$HOSTROOT"
check "init exits 0" run_init DPKG_INSTALLED=1
check "nothing is made up in the box" test -z "$(find "$BOXROOT" -mindepth 1 -print -quit)"

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
