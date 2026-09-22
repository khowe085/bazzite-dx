#!/usr/bin/bash
# Exercises system_files/usr/share/ublue-os/user-setup.hooks.d/45-crunchyroll.sh with a temp HOME
# and a stub curl (fake GitHub release + fake AppImage bytes).
# Run inside a container with the repo mounted at /src:
#   podman run --rm -v "$PWD:/src:ro,Z" <image> /src/tests/test-crunchyroll-hook.sh
set -uo pipefail

SRC="${SRC:-/src}"
HOOK="$SRC/system_files/usr/share/ublue-os/user-setup.hooks.d/45-crunchyroll.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home"

# Stub curl: release JSON for the GitHub API URL, fake bytes for the AppImage URL.
# CURL_FAIL=1 fails every call; CURL_FAIL_DOWNLOAD=1 fails only the AppImage download after writing
# a partial file, like a dropped connection; CURL_NO_ASSET=1 serves a release without an AppImage;
# CURL_ARM_FIRST=1 lists an arm64 AppImage before the x86_64 one.
cat >"$tmp/bin/curl" <<'EOF'
#!/usr/bin/bash
out=""; url=""
while [[ $# -gt 0 ]]; do
	case "$1" in
	-o) out="$2"; shift ;;
	http*) url="$1" ;;
	esac
	shift
done
echo "$url" >>"$CURL_LOG"
[[ -n "${CURL_FAIL:-}" ]] && exit 22
zip='{"name":"crunchyroll_unpacked.zip","browser_download_url":"https://example.invalid/crunchyroll_unpacked.zip"}'
x86='{"name":"Crunchyroll_v9.9.9_linux.AppImage","browser_download_url":"https://example.invalid/Crunchyroll_v9.9.9_linux.AppImage"}'
arm='{"name":"Crunchyroll_v9.9.9_linux_arm64.AppImage","browser_download_url":"https://example.invalid/Crunchyroll_v9.9.9_linux_arm64.AppImage"}'
if [[ "$url" == */releases/latest ]]; then
	if [[ -n "${CURL_NO_ASSET:-}" ]]; then
		echo "{\"tag_name\":\"v9.9.9\",\"assets\":[$zip]}"
	elif [[ -n "${CURL_ARM_FIRST:-}" ]]; then
		echo "{\"tag_name\":\"v9.9.9\",\"assets\":[$arm,$zip,$x86]}"
	else
		echo "{\"tag_name\":\"v9.9.9\",\"assets\":[$zip,$x86]}"
	fi
else
	echo "PARTIAL" >"$out"
	[[ -n "${CURL_FAIL_DOWNLOAD:-}" ]] && exit 22
	# The "AppImage" is a script that only knows --appimage-extract, enough to exercise the icon path.
	cat >"$out" <<'APP'
#!/usr/bin/bash
# fake AppImage: CRUNCHYROLL-BYTES
if [[ "${1:-}" == "--appimage-extract" ]]; then
	mkdir -p squashfs-root
	case "${2:-}" in
	.DirIcon) ln -sf crunchyroll.png squashfs-root/.DirIcon ;;
	crunchyroll.png) echo PNG >squashfs-root/crunchyroll.png ;;
	esac
fi
APP
fi
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
run_hook() { # run_hook [VAR=value ...]
	env HOME="$tmp/home" PATH="$tmp/bin:$PATH" CURL_LOG="$tmp/curl.log" "$@" bash "$HOOK"
}
hook_fails() { ! run_hook "$@"; }
fresh_home() {
	rm -rf "$tmp/home"
	mkdir -p "$tmp/home"
	: >"$tmp/curl.log"
}
apps="$tmp/home/Applications"
app="$apps/Crunchyroll.AppImage"
desktop="$tmp/home/.local/share/applications/Crunchyroll.desktop"
stamp="$apps/.crunchyroll.image-placed"

echo "== first login"
fresh_home
check "hook exits 0" run_hook
check "asks the project the Bazzite Portal downloads from" grep -qx 'https://api.github.com/repos/aarron-lee/crunchyroll-linux/releases/latest' "$tmp/curl.log"
check "AppImage placed under the name the Portal gives it" test -x "$app"
check "it has the downloaded bytes" grep -q 'CRUNCHYROLL-BYTES' "$app"
check "desktop entry launches the AppImage" grep -qx "Exec=\"$app\" %U" "$desktop"
check "desktop entry names the icon" grep -qx 'Icon=crunchyroll' "$desktop"
check "icon extracted from the AppImage (through the .DirIcon symlink)" test "$(cat "$tmp/home/.local/share/icons/hicolor/256x256/apps/crunchyroll.png")" = PNG
check "placement stamped" test -e "$stamp"
check "one release lookup and one download" test "$(wc -l <"$tmp/curl.log")" = 2

echo "== second login"
check "hook exits 0" run_hook
check "nothing downloaded again" test "$(wc -l <"$tmp/curl.log")" = 2

echo "== moved out of ~/Applications (Gear Lever) or deleted"
rm "$app" "$desktop"
check "hook exits 0" run_hook
check "it is placed once per user, not re-downloaded" test "$(wc -l <"$tmp/curl.log")" = 2
check "desktop entry not recreated" test ! -e "$desktop"

echo "== the user already has a Crunchyroll AppImage there (from the Portal)"
fresh_home
mkdir -p "$apps"
echo MINE >"$apps/crunchyroll-linux.AppImage"
check "hook exits 0" run_hook
check "nothing is downloaded next to it" test ! -s "$tmp/curl.log"
check "theirs is left alone" test "$(cat "$apps/crunchyroll-linux.AppImage")" = MINE

echo "== release lists an arm64 AppImage before the x86_64 one"
fresh_home
check "hook exits 0" run_hook CURL_ARM_FIRST=1
check "the x86_64 AppImage is the one downloaded" grep -qx 'https://example.invalid/Crunchyroll_v9.9.9_linux.AppImage' "$tmp/curl.log"

echo "== release has no AppImage asset"
fresh_home
check "hook fails" hook_fails CURL_NO_ASSET=1
check "nothing left behind" test ! -e "$app"
check "not stamped, so the next login retries" test ! -e "$stamp"

echo "== release lookup fails (no network yet)"
fresh_home
check "hook fails" hook_fails CURL_FAIL=1
check "not stamped" test ! -e "$stamp"

echo "== the download drops"
fresh_home
check "hook fails" hook_fails CURL_FAIL_DOWNLOAD=1
check "no partial file left behind" bash -c "! compgen -G '$apps/*runchyroll*' >/dev/null"
check "no desktop entry for a file that is not there" test ! -e "$desktop"
check "not stamped" test ! -e "$stamp"

if ((fails > 0)); then
	echo "$fails check(s) failed"
	exit 1
fi
echo "all checks passed"
