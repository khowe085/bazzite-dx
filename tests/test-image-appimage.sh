#!/usr/bin/bash
# Exercises system_files/usr/libexec/image-appimage with a temp HOME and a fake image directory.
# Run inside a container with the repo mounted at /src:
#   podman run --rm -v "$PWD:/src:ro,Z" <image> /src/tests/test-image-appimage.sh
set -uo pipefail

SRC="${SRC:-/src}"
TOOL="$SRC/system_files/usr/libexec/image-appimage"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
image="$tmp/image"

# ship_version <version>: the image's AppImage, a script that only knows --appimage-extract, enough
# to exercise the icon path; its bytes carry the version.
ship_version() {
	mkdir -p "$image"
	cat >"$image/Foo.AppImage" <<-APP
		#!/usr/bin/bash
		# fake AppImage: FOO-$1
		if [[ "\${1:-}" == "--appimage-extract" ]]; then
			mkdir -p squashfs-root
			case "\${2:-}" in
			.DirIcon) ln -sf foo.png squashfs-root/.DirIcon ;;
			foo.png) echo PNG >squashfs-root/foo.png ;;
			esac
		fi
	APP
	chmod +x "$image/Foo.AppImage"
	echo "$1" >"$image/VERSION"
}

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
run() { # run [image dir]
	HOME="$tmp/home" bash "$TOOL" foo "${1:-$image}" Foo.AppImage '*[Ff]oo*.AppImage' Foo "A foo" "Utility;"
}
fresh_home() {
	rm -rf "$tmp/home"
	mkdir -p "$tmp/home"
}
apps="$tmp/home/Applications"
app="$apps/Foo.AppImage"
desktop="$tmp/home/.local/share/applications/Foo.desktop"
icon="$tmp/home/.local/share/icons/hicolor/256x256/apps/foo.png"
stamp="$apps/.foo.image-version"
line() { sed -n "${1}p" "$stamp"; }

echo "== first login"
fresh_home
ship_version v1
check "exits 0" run
check "AppImage copied from the image" cmp -s "$image/Foo.AppImage" "$app"
check "and executable" test -x "$app"
check "no partial file left" test ! -e "$app.part"
check "desktop entry launches it" grep -qx "Exec=\"$app\" %U" "$desktop"
check "desktop entry has name, comment and categories" bash -c "grep -qx 'Name=Foo' '$desktop' && grep -qx 'Comment=A foo' '$desktop' && grep -qx 'Categories=Utility;' '$desktop'"
check "desktop entry names the icon" grep -qx 'Icon=foo' "$desktop"
check "icon extracted (through the .DirIcon symlink)" test "$(cat "$icon")" = PNG
check "stamp records the path" test "$(line 1)" = "$app"
check "stamp records the image version" test "$(line 2)" = v1
check "stamp records the file's sha256" test "$(line 3)" = "$(sha256sum "$app" | cut -d' ' -f1)"

echo "== next login, same image"
touch -d '2000-01-01' "$app"
check "exits 0" run
check "file not rewritten" test "$(stat -c %Y "$app")" = "$(date -d 2000-01-01 +%s)"

echo "== newer image, file untouched since placed"
ship_version v2
check "exits 0" run
check "updated to the image's copy" cmp -s "$image/Foo.AppImage" "$app"
check "stamp follows the version" test "$(line 2)" = v2
check "stamp follows the new sha256" test "$(line 3)" = "$(sha256sum "$app" | cut -d' ' -f1)"

echo "== the app updated itself (file changed), then a newer image"
echo "SELF-UPDATED" >>"$app"
ship_version v3
check "exits 0" run
check "the changed file is left alone" grep -q SELF-UPDATED "$app"
check "stamp marks it unmanaged" test "$(line 3)" = unmanaged
ship_version v4
check "exits 0 on a later image too" run
check "still left alone" grep -q SELF-UPDATED "$app"

echo "== moved out of ~/Applications (Gear Lever) or deleted"
fresh_home
ship_version v1
run >/dev/null
rm "$app" "$desktop"
ship_version v2
check "exits 0" run
check "not put back" test ! -e "$app"
check "desktop entry not recreated" test ! -e "$desktop"

echo "== the user already has one there"
fresh_home
mkdir -p "$apps"
echo MINE >"$apps/foo-linux.AppImage"
check "exits 0" run
check "theirs is left alone" test "$(cat "$apps/foo-linux.AppImage")" = MINE
check "nothing placed next to it" test ! -e "$app"
check "no stamp" test ! -e "$stamp"

echo "== placed by the earlier download hook (.foo.image-placed), still the release the image has"
fresh_home
ship_version v5
mkdir -p "$apps" "$(dirname "$desktop")"
cp "$image/Foo.AppImage" "$apps/Foo-1.0.AppImage"
echo "Foo-1.0.AppImage" >"$apps/.foo.image-placed"
echo "Exec=old" >"$desktop"
check "exits 0" run
check "replaced by the image's copy under the image's name" cmp -s "$image/Foo.AppImage" "$app"
check "the old download is removed" test ! -e "$apps/Foo-1.0.AppImage"
check "desktop entry points at the new file" grep -qx "Exec=\"$app\" %U" "$desktop"
check "old stamp removed" test ! -e "$apps/.foo.image-placed"
check "new stamp at the image version" test "$(line 2)" = v5
ship_version v6
check "exits 0 on a newer image" run
check "and it is updated from then on" cmp -s "$image/Foo.AppImage" "$app"

echo "== placed by the earlier download hook, not the image's release (EmuDeck updated itself)"
fresh_home
ship_version v5
mkdir -p "$apps"
echo "SELF-UPDATED" >"$apps/Foo-1.0.AppImage"
echo "Foo-1.0.AppImage" >"$apps/.foo.image-placed"
check "exits 0" run
check "left alone" test "$(cat "$apps/Foo-1.0.AppImage")" = SELF-UPDATED
check "nothing placed next to it" test ! -e "$app"
check "stamp marks it unmanaged" test "$(line 3)" = unmanaged
ship_version v6
check "exits 0 on a newer image" run
check "still left alone" test "$(cat "$apps/Foo-1.0.AppImage")" = SELF-UPDATED

echo "== placed by the earlier download hook under the image's name, stamp naming the asset (Crunchyroll)"
fresh_home
ship_version v5
mkdir -p "$apps"
cp "$image/Foo.AppImage" "$app"
echo "Foo_v1.0_linux.AppImage" >"$apps/.foo.image-placed"
echo MINE >"$apps/Foo_v1.0_linux.AppImage"
check "exits 0" run
check "the file under the image's name is the one taken over" test "$(line 1)" = "$app"
check "a file under the asset's name is the user's and stays" test "$(cat "$apps/Foo_v1.0_linux.AppImage")" = MINE
ship_version v6
check "exits 0 on a newer image" run
check "and the taken-over file is updated" cmp -s "$image/Foo.AppImage" "$app"

echo "== the earlier download hook's stamp is empty"
fresh_home
ship_version v5
mkdir -p "$apps"
: >"$apps/.foo.image-placed"
check "exits 0" run
check "a second run exits 0 too" run
check "nothing placed" test ! -e "$app"

echo "== first placement interrupted before its stamp"
fresh_home
ship_version v1
mkdir -p "$apps"
cp "$image/Foo.AppImage" "$app"
check "exits 0" run
check "the image's own copy is taken as placed" test "$(line 2)" = v1
check "and gets its menu entry" test -e "$desktop"
ship_version v2
check "exits 0 on a newer image" run
check "and it is updated" cmp -s "$image/Foo.AppImage" "$app"

echo "== placed by the earlier download hook, taken over, then changed by the app"
fresh_home
ship_version v5
mkdir -p "$apps"
cp "$image/Foo.AppImage" "$apps/Foo-1.0.AppImage"
echo "Foo-1.0.AppImage" >"$apps/.foo.image-placed"
check "first run exits 0" run
check "adopted and replaced" test -e "$app"
echo "SELF-UPDATED" >>"$app"
ship_version v6
check "exits 0" run
check "the app's own update is kept" grep -q SELF-UPDATED "$app"

echo "== placed by the earlier download hook, since moved or deleted"
fresh_home
mkdir -p "$apps"
echo "Foo-1.0.AppImage" >"$apps/.foo.image-placed"
check "exits 0" run
check "not put back" test ! -e "$app"
check "stamp records it as gone" test "$(line 2)" = downloaded
check "a later run still does not put it back" bash -c "HOME='$tmp/home' bash '$TOOL' foo '$image' Foo.AppImage '*[Ff]oo*.AppImage' Foo 'A foo' 'Utility;' && test ! -e '$app'"

echo "== image without the AppImage"
fresh_home
check "exits 0" run "$tmp/no-such-dir"
check "nothing placed" test ! -e "$app"
check "no stamp, so a later image with it still places it" test ! -e "$stamp"

echo "== copy fails (disk full)"
fresh_home
ship_version v1
mkdir -p "$apps"
chmod 0555 "$apps"
if [[ $(id -u) -ne 0 ]]; then
	check "fails" bash -c "! HOME='$tmp/home' bash '$TOOL' foo '$image' Foo.AppImage '*[Ff]oo*.AppImage' Foo 'A foo' 'Utility;'"
	check "no stamp, so the next login retries" test ! -e "$stamp"
else
	echo "skip - root ignores directory permissions"
fi
chmod 0755 "$apps"

echo "== wrong usage"
check "fails without all arguments" bash -c "! HOME='$tmp/home' bash '$TOOL' foo"

if ((fails > 0)); then
	echo "$fails check(s) failed"
	exit 1
fi
echo "all checks passed"
