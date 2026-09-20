#!/usr/bin/bash
# Exercises build_files/install-tea.sh, which downloads Gitea's tea CLI at image build time, with a
# stub curl and a redirected install destination. sha256sum is the real one.
# Run inside a container with the repo mounted at /src:
#   podman run --rm -v "$PWD:/src:ro,Z" <image> /src/tests/test-install-tea.sh
set -uo pipefail

SRC="${SRC:-/src}"
INSTALL="$SRC/build_files/install-tea.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

# The stub plays three roles: the releases/latest redirect (printed for -w '%{redirect_url}'), the
# binary, and its .sha256 file. TEA_REDIRECT overrides the redirect target, TEA_BAD_SUM=1 publishes
# a checksum for different bytes, TEA_DOWNLOAD_FAIL=1 fails the binary download, TEA_SUM_FAIL=1
# fails the checksum download.
cat >"$tmp/bin/curl" <<'EOF'
#!/usr/bin/bash
out=""; url=""; write_out=""
while [[ $# -gt 0 ]]; do
	case "$1" in
	-o) out="$2"; shift ;;
	-w) write_out="$2"; shift ;;
	http*) url="$1" ;;
	esac
	shift
done
echo "$url" >>"$CALLS"
# The fake binary starts with a shebang because Git Bash on Windows derives the executable bit from
# file content; on Linux the -x check below still depends on the mode install-tea.sh sets.
payload() { printf '#!/usr/bin/bash\n# %s\n' "$1"; }
case "$url" in
*/releases/latest)
	[[ "$write_out" == '%{redirect_url}' ]] || { echo "stub: expected -w %{redirect_url}" >&2; exit 2; }
	printf '%s' "${TEA_REDIRECT-https://gitea.com/gitea/tea/releases/tag/v9.8.7}"
	;;
*.sha256)
	[[ -n "${TEA_SUM_FAIL:-}" ]] && exit 22
	name="$(basename "${url%.sha256}")"
	if [[ -n "${TEA_BAD_SUM:-}" ]]; then bytes="SOMETHING-ELSE"; else bytes="TEA-BINARY"; fi
	printf '%s  %s\n' "$(payload "$bytes" | sha256sum | cut -d' ' -f1)" "$name" >"$out"
	;;
*)
	[[ -n "${TEA_DOWNLOAD_FAIL:-}" ]] && exit 22
	payload TEA-BINARY >"$out"
	;;
esac
EOF
chmod +x "$tmp/bin/curl"

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
run_install() { # run_install [VAR=value ...]
	env PATH="$tmp/bin:$PATH" CALLS="$tmp/calls.log" TEA_DEST="$tmp/dest/tea" "$@" bash "$INSTALL"
}
install_fails() { ! run_install "$@"; }
reset() {
	rm -rf "$tmp/dest"
	mkdir -p "$tmp/dest"
	: >"$tmp/calls.log"
}

echo "== latest release is v9.8.7"
reset
check "install exits 0" run_install
check "version looked up through the releases/latest redirect" grep -qx 'https://gitea.com/gitea/tea/releases/latest' "$tmp/calls.log"
check "binary fetched for that version" grep -qx 'https://dl.gitea.com/tea/9.8.7/tea-9.8.7-linux-amd64' "$tmp/calls.log"
check "its published checksum fetched" grep -qx 'https://dl.gitea.com/tea/9.8.7/tea-9.8.7-linux-amd64.sha256' "$tmp/calls.log"
check "tea installed with the downloaded bytes" grep -qx '# TEA-BINARY' "$tmp/dest/tea"
check "tea is executable" test -x "$tmp/dest/tea"

echo "== published checksum does not match the download"
reset
check "install fails" install_fails TEA_BAD_SUM=1
check "nothing installed" test ! -e "$tmp/dest/tea"

echo "== releases/latest does not lead to a version"
reset
check "install fails on a redirect without a version" install_fails TEA_REDIRECT=https://gitea.com/user/login
check "nothing downloaded on a guess" test "$(wc -l <"$tmp/calls.log")" = 1
check "nothing installed" test ! -e "$tmp/dest/tea"
reset
check "install fails when there is no redirect at all" install_fails TEA_REDIRECT=
check "nothing installed" test ! -e "$tmp/dest/tea"

echo "== latest release is a prerelease-style tag"
reset
check "install fails rather than guess at v0.17.0-rc1" install_fails TEA_REDIRECT=https://gitea.com/gitea/tea/releases/tag/v0.17.0-rc1
check "nothing installed" test ! -e "$tmp/dest/tea"

echo "== checksum file is missing upstream"
reset
check "install fails without a checksum to verify against" install_fails TEA_SUM_FAIL=1
check "nothing installed" test ! -e "$tmp/dest/tea"

echo "== binary download fails"
reset
check "install fails" install_fails TEA_DOWNLOAD_FAIL=1
check "nothing installed" test ! -e "$tmp/dest/tea"

if ((fails > 0)); then
	echo "$fails check(s) failed"
	exit 1
fi
echo "all checks passed"
