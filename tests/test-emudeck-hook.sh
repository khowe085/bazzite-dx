#!/usr/bin/bash
# Exercises system_files/usr/share/ublue-os/user-setup.hooks.d/30-emudeck.sh with a temp HOME,
# a stub curl (fake GitHub release + fake AppImage bytes) and a fake Eden image dir.
# Run inside a container with the repo mounted at /src:
#   podman run --rm -v "$PWD:/src:ro,Z" <image> /src/tests/test-emudeck-hook.sh
set -uo pipefail

SRC="${SRC:-/src}"
HOOK="$SRC/system_files/usr/share/ublue-os/user-setup.hooks.d/30-emudeck.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/eden" "$tmp/home"
echo "eden-v1" >"$tmp/eden/VERSION"
echo "EDEN-V1" >"$tmp/eden/Eden.AppImage"
chmod +x "$tmp/eden/Eden.AppImage"

# Stub curl: release JSON for the GitHub API URL, fake bytes for the AppImage URL.
# CURL_FAIL=1 fails every call; CURL_FAIL_DOWNLOAD=1 fails only the AppImage download
# after writing a partial file, like a dropped connection.
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
if [[ "$url" == */releases/latest ]]; then
	if [[ -n "${CURL_NO_ASSET:-}" ]]; then
		echo '{"tag_name":"v9.9.9","assets":[{"name":"EmuDeck-Setup-9.9.9.exe","browser_download_url":"https://example.invalid/EmuDeck-Setup-9.9.9.exe"}]}'
	elif [[ -n "${CURL_ARM_FIRST:-}" ]]; then
		echo '{"tag_name":"v9.9.9","assets":[{"name":"EmuDeck-9.9.9-arm64.AppImage","browser_download_url":"https://example.invalid/EmuDeck-9.9.9-arm64.AppImage"},{"name":"EmuDeck-9.9.9.AppImage","browser_download_url":"https://example.invalid/EmuDeck-9.9.9.AppImage"}]}'
	else
		echo '{"tag_name":"v9.9.9","assets":[{"name":"EmuDeck-Setup-9.9.9.exe","browser_download_url":"https://example.invalid/EmuDeck-Setup-9.9.9.exe"},{"name":"EmuDeck-9.9.9.AppImage","browser_download_url":"https://example.invalid/EmuDeck-9.9.9.AppImage"}]}'
	fi
else
	echo "PARTIAL" >"$out"
	[[ -n "${CURL_FAIL_DOWNLOAD:-}" ]] && exit 22
	# The "AppImage" is a script that only knows --appimage-extract, enough to exercise the icon path.
	cat >"$out" <<'APP'
#!/usr/bin/bash
# fake AppImage: EMUDECK-BYTES
if [[ "${1:-}" == "--appimage-extract" ]]; then
	mkdir -p squashfs-root
	case "${2:-}" in
	.DirIcon) ln -sf emudeck.png squashfs-root/.DirIcon ;;
	emudeck.png) echo PNG >squashfs-root/emudeck.png ;;
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
	env HOME="$tmp/home" PATH="$tmp/bin:$PATH" CURL_LOG="$tmp/curl.log" EDEN_IMAGE_DIR="$tmp/eden" "$@" bash "$HOOK"
}
hook_fails() { ! run_hook "$@"; }
apps="$tmp/home/Applications"
desktop="$tmp/home/.local/share/applications/EmuDeck.desktop"

echo "== first login"
check "hook exits 0" run_hook
check "Eden copied to ~/Applications/Eden.AppImage" cmp -s "$tmp/eden/Eden.AppImage" "$apps/Eden.AppImage"
check "Eden is executable" test -x "$apps/Eden.AppImage"
check "Eden image version stamped" test "$(cat "$apps/.eden.image-version")" = eden-v1
check "EmuDeck AppImage downloaded under its upstream name" test -x "$apps/EmuDeck-9.9.9.AppImage"
check "EmuDeck AppImage has the downloaded bytes" grep -q 'EMUDECK-BYTES' "$apps/EmuDeck-9.9.9.AppImage"
check "desktop entry launches the AppImage" grep -qx "Exec=\"$apps/EmuDeck-9.9.9.AppImage\" %U" "$desktop"
check "desktop entry names the icon" grep -qx 'Icon=emudeck' "$desktop"
check "icon extracted from the AppImage (through the .DirIcon symlink)" test "$(cat "$tmp/home/.local/share/icons/hicolor/256x256/apps/emudeck.png")" = PNG
check "EmuDeck placement stamped" test -e "$apps/.emudeck.image-placed"
check "one release lookup and one download" test "$(wc -l <"$tmp/curl.log")" = 2

echo "== second login"
check "hook exits 0" run_hook
check "nothing downloaded again" test "$(wc -l <"$tmp/curl.log")" = 2
check "Eden untouched" test "$(cat "$apps/.eden.image-version")" = eden-v1

echo "== EmuDeck moved out of ~/Applications (Gear Lever) or deleted"
rm "$apps/EmuDeck-9.9.9.AppImage" "$desktop"
check "hook exits 0" run_hook
check "EmuDeck is placed once per user, not re-downloaded" test "$(wc -l <"$tmp/curl.log")" = 2
check "desktop entry not recreated for a moved AppImage" test ! -e "$desktop"

echo "== image ships a newer Eden"
echo "eden-v2" >"$tmp/eden/VERSION"
echo "EDEN-V2" >"$tmp/eden/Eden.AppImage"
check "hook exits 0" run_hook
check "managed Eden replaced by the newer image copy" cmp -s "$tmp/eden/Eden.AppImage" "$apps/Eden.AppImage"
check "stamp follows the image version" test "$(cat "$apps/.eden.image-version")" = eden-v2

echo "== user manages Eden themselves"
rm "$apps/.eden.image-version"
echo "MINE" >"$apps/Eden.AppImage"
echo "eden-v3" >"$tmp/eden/VERSION"
check "hook exits 0" run_hook
check "unmanaged Eden (no stamp) is left alone" test "$(cat "$apps/Eden.AppImage")" = MINE

echo "== managed Eden removed, stamp left behind (Gear Lever moves AppImages)"
rm -rf "$tmp/home"
mkdir -p "$tmp/home"
echo "eden-v4" >"$tmp/eden/VERSION"
echo "EDEN-V4" >"$tmp/eden/Eden.AppImage"
check "hook exits 0" run_hook
rm "$apps/Eden.AppImage"
check "hook exits 0" run_hook
check "managed Eden restored when the file is gone but the stamp remains" cmp -s "$tmp/eden/Eden.AppImage" "$apps/Eden.AppImage"

echo "== release lists an arm64 AppImage before the x86_64 one"
rm -rf "$tmp/home"
mkdir -p "$tmp/home"
check "hook exits 0" run_hook CURL_ARM_FIRST=1
check "the non-arm AppImage is the one placed" test -x "$apps/EmuDeck-9.9.9.AppImage"
check "no arm64 AppImage placed" bash -c "! compgen -G '$apps/*arm64*' >/dev/null"

echo "== image without an Eden (VERSION missing)"
rm -rf "$tmp/home"
mkdir -p "$tmp/home"
check "hook exits 0 without Eden in the image" run_hook EDEN_IMAGE_DIR="$tmp/no-such-dir"
check "EmuDeck still placed" test -x "$apps/EmuDeck-9.9.9.AppImage"
check "no Eden placed" test ! -e "$apps/Eden.AppImage"

echo "== release has no AppImage asset"
rm -rf "$tmp/home"
mkdir -p "$tmp/home"
check "hook fails when the release has no AppImage" hook_fails CURL_NO_ASSET=1
check "no EmuDeck file left behind" bash -c "! compgen -G '$apps/*EmuDeck*' >/dev/null"
check "not stamped, so the next login retries" test ! -e "$apps/.emudeck.image-placed"

echo "== EmuDeck download fails"
rm -rf "$tmp/home"
mkdir -p "$tmp/home"
: >"$tmp/curl.log"
check "hook fails when the release lookup fails" hook_fails CURL_FAIL=1
check "Eden still placed before the failing download" test -x "$apps/Eden.AppImage"
check "no EmuDeck file left behind" bash -c "! compgen -G '$apps/*EmuDeck*' >/dev/null"

rm -rf "$tmp/home"
mkdir -p "$tmp/home"
check "hook fails when the AppImage download drops" hook_fails CURL_FAIL_DOWNLOAD=1
check "no partial EmuDeck file left behind" bash -c "! compgen -G '$apps/*EmuDeck*' >/dev/null"
check "not stamped after a dropped download" test ! -e "$apps/.emudeck.image-placed"

if ((fails > 0)); then
	echo "$fails check(s) failed"
	exit 1
fi
echo "all checks passed"
