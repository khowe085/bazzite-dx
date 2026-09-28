#!/usr/bin/bash
# Exercises system_files/usr/share/ublue-os/user-setup.hooks.d/45-crunchyroll.sh with a temp HOME,
# a fake image directory and the repository's image-appimage (tests/test-image-appimage.sh covers
# the placement rules; this checks the hook's wiring and that it needs no network).
# Run inside a container with the repo mounted at /src:
#   podman run --rm -v "$PWD:/src:ro,Z" <image> /src/tests/test-crunchyroll-hook.sh
set -uo pipefail

SRC="${SRC:-/src}"
HOOK="$SRC/system_files/usr/share/ublue-os/user-setup.hooks.d/45-crunchyroll.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home" "$tmp/image"

# Any network use is a failure: curl and wget are stubs that log and fail.
for tool in curl wget; do
	printf '#!/usr/bin/bash\necho "%s $*" >>"%s/net.log"\nexit 7\n' "$tool" "$tmp" >"$tmp/bin/$tool"
done
chmod +x "$tmp/bin/"*
cat >"$tmp/image/Crunchyroll.AppImage" <<'APP'
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
chmod +x "$tmp/image/Crunchyroll.AppImage"
echo v1.2.3 >"$tmp/image/VERSION"

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
run_hook() {
	env HOME="$tmp/home" PATH="$tmp/bin:$PATH" CRUNCHYROLL_IMAGE_DIR="$tmp/image" \
		IMAGE_APPIMAGE="$SRC/system_files/usr/libexec/image-appimage" bash "$HOOK"
}
apps="$tmp/home/Applications"
app="$apps/Crunchyroll.AppImage"
desktop="$tmp/home/.local/share/applications/Crunchyroll.desktop"

echo "== first login"
check "hook exits 0" run_hook
check "AppImage copied from the image to ~/Applications/Crunchyroll.AppImage" cmp -s "$tmp/image/Crunchyroll.AppImage" "$app"
check "desktop entry launches it" grep -qx "Exec=\"$app\" %U" "$desktop"
check "desktop entry keeps its name, comment and categories" bash -c "grep -qx 'Name=Crunchyroll' '$desktop' && grep -qx 'Comment=Anime streaming' '$desktop' && grep -qx 'Categories=AudioVideo;Video;' '$desktop'"
check "icon named crunchyroll" test "$(cat "$tmp/home/.local/share/icons/hicolor/256x256/apps/crunchyroll.png")" = PNG
check "stamped with the image version" test "$(sed -n 2p "$apps/.crunchyroll.image-version")" = v1.2.3
check "nothing downloaded" test ! -e "$tmp/net.log"

echo "== a Crunchyroll AppImage of the user's own (any capitalisation) is respected"
rm -rf "$tmp/home"
mkdir -p "$apps"
echo MINE >"$apps/crunchyroll-linux.AppImage"
check "hook exits 0" run_hook
check "nothing placed next to it" test ! -e "$app"

echo "== downloaded by the earlier hook (file Crunchyroll.AppImage, stamp naming the release asset)"
rm -rf "$tmp/home"
mkdir -p "$apps"
cp "$tmp/image/Crunchyroll.AppImage" "$app"
echo "Crunchyroll_v1.1.6_linux.AppImage" >"$apps/.crunchyroll.image-placed"
check "hook exits 0" run_hook
check "taken over and replaced by the image's copy" cmp -s "$tmp/image/Crunchyroll.AppImage" "$app"
check "stamped with the image version" test "$(sed -n 2p "$apps/.crunchyroll.image-version")" = v1.2.3

echo "== the hook uses the image's paths by default"
check "image directory /usr/lib/crunchyroll" grep -qF 'CRUNCHYROLL_IMAGE_DIR:-/usr/lib/crunchyroll}' "$HOOK"
check "tool /usr/libexec/image-appimage" grep -qF 'IMAGE_APPIMAGE:-/usr/libexec/image-appimage}' "$HOOK"

if ((fails > 0)); then
	echo "$fails check(s) failed"
	exit 1
fi
echo "all checks passed"
