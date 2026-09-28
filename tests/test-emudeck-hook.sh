#!/usr/bin/bash
# Exercises system_files/usr/share/ublue-os/user-setup.hooks.d/30-emudeck.sh with a temp HOME and
# fake Eden and EmuDeck image dirs; EmuDeck goes through the repository's image-appimage
# (tests/test-image-appimage.sh covers its placement rules). curl and wget are stubs that fail, so
# any network use shows up.
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

for tool in curl wget; do
	printf '#!/usr/bin/bash\necho "%s $*" >>"%s/net.log"\nexit 7\n' "$tool" "$tmp" >"$tmp/bin/$tool"
done
chmod +x "$tmp/bin/"*
mkdir -p "$tmp/emudeck"
# The "AppImage" is a script that only knows --appimage-extract, enough to exercise the icon path.
cat >"$tmp/emudeck/EmuDeck.AppImage" <<'APP'
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
chmod +x "$tmp/emudeck/EmuDeck.AppImage"
echo v9.9.9 >"$tmp/emudeck/VERSION"

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
	env HOME="$tmp/home" PATH="$tmp/bin:$PATH" EDEN_IMAGE_DIR="$tmp/eden" EMUDECK_IMAGE_DIR="$tmp/emudeck" \
		IMAGE_APPIMAGE="$SRC/system_files/usr/libexec/image-appimage" "$@" bash "$HOOK"
}
hook_fails() { ! run_hook "$@"; }
apps="$tmp/home/Applications"
desktop="$tmp/home/.local/share/applications/EmuDeck.desktop"

echo "== first login"
check "hook exits 0" run_hook
check "Eden copied to ~/Applications/Eden.AppImage" cmp -s "$tmp/eden/Eden.AppImage" "$apps/Eden.AppImage"
check "Eden is executable" test -x "$apps/Eden.AppImage"
check "Eden image version stamped" test "$(cat "$apps/.eden.image-version")" = eden-v1
check "EmuDeck copied from the image to ~/Applications/EmuDeck.AppImage" cmp -s "$tmp/emudeck/EmuDeck.AppImage" "$apps/EmuDeck.AppImage"
check "desktop entry launches the AppImage" grep -qx "Exec=\"$apps/EmuDeck.AppImage\" %U" "$desktop"
check "desktop entry keeps its name, comment and categories" bash -c "grep -qx 'Name=EmuDeck' '$desktop' && grep -qx 'Comment=Emulator setup and management' '$desktop' && grep -qx 'Categories=Game;Utility;' '$desktop'"
check "desktop entry names the icon" grep -qx 'Icon=emudeck' "$desktop"
check "icon extracted from the AppImage" test "$(cat "$tmp/home/.local/share/icons/hicolor/256x256/apps/emudeck.png")" = PNG
check "EmuDeck stamped with the image version" test "$(sed -n 2p "$apps/.emudeck.image-version")" = v9.9.9
check "nothing downloaded" test ! -e "$tmp/net.log"

echo "== second login"
check "hook exits 0" run_hook
check "Eden untouched" test "$(cat "$apps/.eden.image-version")" = eden-v1

echo "== EmuDeck already there from the earlier download hook"
rm -rf "$tmp/home"
mkdir -p "$apps"
cp "$tmp/emudeck/EmuDeck.AppImage" "$apps/EmuDeck-2.5.0.AppImage"
echo "EmuDeck-2.5.0.AppImage" >"$apps/.emudeck.image-placed"
check "hook exits 0" run_hook
check "taken over and replaced by the image's copy" cmp -s "$tmp/emudeck/EmuDeck.AppImage" "$apps/EmuDeck.AppImage"
check "the old download is removed" test ! -e "$apps/EmuDeck-2.5.0.AppImage"

echo "== EmuDeck moved out of ~/Applications (Gear Lever) or deleted"
rm "$apps/EmuDeck.AppImage" "$desktop"
check "hook exits 0" run_hook
check "EmuDeck is not put back" test ! -e "$apps/EmuDeck.AppImage"
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

echo "== image without an Eden (VERSION missing)"
rm -rf "$tmp/home"
mkdir -p "$tmp/home"
check "hook exits 0 without Eden in the image" run_hook EDEN_IMAGE_DIR="$tmp/no-such-dir"
check "EmuDeck still placed" test -x "$apps/EmuDeck.AppImage"
check "no Eden placed" test ! -e "$apps/Eden.AppImage"

echo "== image without EmuDeck"
rm -rf "$tmp/home"
mkdir -p "$tmp/home"
check "hook exits 0" run_hook EMUDECK_IMAGE_DIR="$tmp/no-such-dir"
check "Eden still placed" test -x "$apps/Eden.AppImage"
check "no EmuDeck placed" bash -c "! compgen -G '$apps/*EmuDeck*' >/dev/null"

echo "== the hook uses the image's paths by default"
check "EmuDeck image directory /usr/lib/emudeck" grep -qF 'EMUDECK_IMAGE_DIR:-/usr/lib/emudeck}' "$HOOK"
check "tool /usr/libexec/image-appimage" grep -qF 'IMAGE_APPIMAGE:-/usr/libexec/image-appimage}' "$HOOK"

if ((fails > 0)); then
	echo "$fails check(s) failed"
	exit 1
fi
echo "all checks passed"
