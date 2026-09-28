#!/usr/bin/bash
# Exercises build_files/fetch-appimages.sh with a stub curl (fake GitHub releases + fake AppImage bytes).
# Run inside a container with the repo mounted at /src (needs jq, as the image build does):
#   podman run --rm -v "$PWD:/src:ro,Z" <image> /src/tests/test-appimages-build.sh
set -uo pipefail

SRC="${SRC:-/src}"
STEP="$SRC/build_files/fetch-appimages.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

# Stub curl: release JSON for the GitHub API, "<asset name> BYTES" for downloads.
# CURL_NO_ASSET=1 serves releases without an x86_64 AppImage; CURL_BAD_DIGEST=1 serves a digest that
# does not match; CURL_FAIL_DOWNLOAD=1 fails the downloads.
cat >"$tmp/bin/curl" <<'EOF'
#!/usr/bin/bash
out=""; url=""
while [[ $# -gt 0 ]]; do
	case "$1" in
	-o) out="$2"; shift ;;
	--retry) shift ;;
	-K) grep -q "Authorization: Bearer" "$2" && echo "auth $(sed -n 's/.*Bearer \([^"]*\)".*/\1/p' "$2")" >>"$CURL_LOG"; shift ;;
	http*) url="$1" ;;
	esac
	shift
done
echo "$url" >>"$CURL_LOG"
digest() { # sha256 of what the download of $1 returns
	if [[ -n "${CURL_BAD_DIGEST:-}" ]]; then echo "sha256:$(printf x | sha256sum | cut -d' ' -f1)"; else echo "sha256:$(printf '%s BYTES\n' "$1" | sha256sum | cut -d' ' -f1)"; fi
}
case "$url" in
*/EmuDeck/emudeck-electron/releases/latest)
	app='{"name":"EmuDeck-9.9.9.AppImage","browser_download_url":"https://example.invalid/EmuDeck-9.9.9.AppImage"}'
	exe='{"name":"EmuDeck-Setup-9.9.9.exe","browser_download_url":"https://example.invalid/EmuDeck-Setup-9.9.9.exe"}'
	if [[ -n "${CURL_NO_ASSET:-}" ]]; then echo "{\"tag_name\":\"v9.9.9\",\"assets\":[$exe]}"; else echo "{\"tag_name\":\"v9.9.9\",\"assets\":[$exe,$app]}"; fi ;;
*/aarron-lee/crunchyroll-linux/releases/latest)
	zip='{"name":"crunchyroll_unpacked.zip","browser_download_url":"https://example.invalid/crunchyroll_unpacked.zip","digest":null}'
	arm="{\"name\":\"Crunchyroll_v1.2.3_linux_arm64.AppImage\",\"browser_download_url\":\"https://example.invalid/Crunchyroll_v1.2.3_linux_arm64.AppImage\",\"digest\":\"$(digest Crunchyroll_v1.2.3_linux_arm64.AppImage)\"}"
	x86="{\"name\":\"Crunchyroll_v1.2.3_linux.AppImage\",\"browser_download_url\":\"https://example.invalid/Crunchyroll_v1.2.3_linux.AppImage\",\"digest\":\"$(digest Crunchyroll_v1.2.3_linux.AppImage)\"}"
	echo "{\"tag_name\":\"v1.2.3\",\"assets\":[$zip,$arm,$x86]}" ;;
*)
	[[ -n "${CURL_FAIL_DOWNLOAD:-}" ]] && exit 22
	printf '%s BYTES\n' "${url##*/}" >"$out" ;;
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
run_step() { # run_step [VAR=value ...]
	rm -rf "$tmp/root"
	: >"$tmp/curl.log"
	env PATH="$tmp/bin:$PATH" CURL_LOG="$tmp/curl.log" APPIMAGE_ROOT="$tmp/root" TOKEN_FILE="$tmp/no-token" "$@" bash "$STEP" 2>"$tmp/trace"
}
step_fails() { ! run_step "$@"; }
root="$tmp/root"

echo "== both releases available"
check "step exits 0" run_step
check "EmuDeck shipped under a fixed name" test -x "$root/emudeck/EmuDeck.AppImage"
check "it is the x86_64 AppImage" test "$(cat "$root/emudeck/EmuDeck.AppImage")" = "EmuDeck-9.9.9.AppImage BYTES"
check "EmuDeck version is the release tag" test "$(cat "$root/emudeck/VERSION")" = v9.9.9
check "Crunchyroll shipped under a fixed name" test -x "$root/crunchyroll/Crunchyroll.AppImage"
check "it is the x86_64 AppImage, not the arm64 one listed first" test "$(cat "$root/crunchyroll/Crunchyroll.AppImage")" = "Crunchyroll_v1.2.3_linux.AppImage BYTES"
check "Crunchyroll version is the release tag" test "$(cat "$root/crunchyroll/VERSION")" = v1.2.3
check "asks the project the Bazzite Portal downloads Crunchyroll from" grep -qx 'https://api.github.com/repos/aarron-lee/crunchyroll-linux/releases/latest' "$tmp/curl.log"
check "no token, no Authorization header" bash -c "! grep -q '^auth' '$tmp/curl.log'"

echo "== with the workflow's token as a build secret"
echo "s3cr3t-token" >"$tmp/token"
check "step exits 0" run_step TOKEN_FILE="$tmp/token"
check "both release lookups send it" test "$(grep -cx 'auth s3cr3t-token' "$tmp/curl.log")" = 2
check "the token stays out of the xtrace log" bash -c "! grep -q s3cr3t-token '$tmp/trace'"

echo "== release has no x86_64 AppImage"
check "step fails" step_fails CURL_NO_ASSET=1

echo "== download does not match GitHub's digest"
check "step fails" step_fails CURL_BAD_DIGEST=1

echo "== download fails"
check "step fails" step_fails CURL_FAIL_DOWNLOAD=1

if ((fails > 0)); then
	echo "$fails check(s) failed"
	exit 1
fi
echo "all checks passed"
