#!/usr/bin/bash
# Exercises build_files/55-kde-defaults.sh, which makes Fedora Dark the default global theme,
# against a scratch copy of the kdeglobals file Bazzite ships.
# Run inside a container with the repo mounted at /src:
#   podman run --rm -v "$PWD:/src:ro,Z" <image> /src/tests/test-kde-defaults.sh
set -uo pipefail

SRC="${SRC:-/src}"
STEP="$SRC/build_files/55-kde-defaults.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

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
run_step() { env KDE_DEFAULTS_KDEGLOBALS="$tmp/kdeglobals" KDE_DEFAULTS_KCMINPUTRC="$tmp/kcminputrc" bash "$STEP"; }
step_fails() { ! run_step; }
# Bazzite's /etc/xdg/kdeglobals (steamdeck-kde-presets-desktop), shortened to one font line.
write_bazzite_kdeglobals() {
	cat >"$tmp/kdeglobals" <<'EOF'
[KDE]
LookAndFeelPackage=com.valve.vapor.desktop

[KDE Control Module Restrictions][$i]
kcm_updates=false

[General]
font=Noto Sans,10,-1,5,50,0,0,0,0,0

# This is a konsole specific setting belonging to /etc/xdg/konsolerc
[Desktop Entry]
DefaultProfile=Vapor.profile
EOF
}

echo "== Bazzite's kdeglobals"
write_bazzite_kdeglobals
cp "$tmp/kdeglobals" "$tmp/before"
check "build step exits 0" run_step
check "Fedora Dark is the default global theme" grep -qx 'LookAndFeelPackage=org.fedoraproject.fedoradark.desktop' "$tmp/kdeglobals"
check "Vapor no longer is" bash -c "! grep -q 'com.valve.vapor.desktop' '$tmp/kdeglobals'"
check "the setting is still in the [KDE] group, right below its header" bash -c "grep -A1 -Fx '[KDE]' '$tmp/kdeglobals' | grep -q '^LookAndFeelPackage='"
check "nothing else in the file changed" test "$(diff "$tmp/before" "$tmp/kdeglobals" | grep -c '^[<>]')" = 2

echo "== second run"
cp "$tmp/kdeglobals" "$tmp/once"
check "build step exits 0" run_step
check "the file is unchanged" cmp -s "$tmp/once" "$tmp/kdeglobals"

echo "== the base no longer sets a global theme in this file"
printf '[General]\nfont=Noto Sans,10,-1,5,50,0,0,0,0,0\n' >"$tmp/kdeglobals"
cp "$tmp/kdeglobals" "$tmp/before"
check "build step fails instead of silently changing nothing" step_fails
check "the file is left as it was" cmp -s "$tmp/before" "$tmp/kdeglobals"

echo "== the base no longer ships the file"
rm -f "$tmp/kdeglobals"
check "build step fails" step_fails
check "no file is made up" test ! -e "$tmp/kdeglobals"

# KWin reads per-device-type input defaults from [Libinput][Defaults][<type>] in kcminputrc. A
# touchpad gets the Touchpad group, every other pointing device (mice included) the Pointer group.
# KWin asks "is it a keyboard?" first, so a keyboard with a built-in touchpad or trackball that
# shows up as one device gets the Keyboard group, and only that one.
input_default() { # input_default <type>: prints the lines of that type's defaults group
	sed -n "/^\[Libinput\]\[Defaults\]\[$1\]\$/,/^\[/p" "$tmp/kcminputrc" | grep -v '^\[' | grep .
}
echo "== natural scrolling, no system kcminputrc in the base"
write_bazzite_kdeglobals
rm -f "$tmp/kcminputrc"
check "build step exits 0" run_step
check "touchpads scroll naturally by default" test "$(input_default Touchpad)" = "NaturalScroll=true"
check "mice scroll naturally by default" test "$(input_default Pointer)" = "NaturalScroll=true"
check "so do pointing devices built into a keyboard" test "$(input_default Keyboard)" = "NaturalScroll=true"

echo "== natural scrolling, the base ships a kcminputrc of its own (here without a final newline)"
write_bazzite_kdeglobals
printf '[Mouse]\ncursorTheme=breeze_cursors' >"$tmp/kcminputrc"
check "build step exits 0" run_step
check "its settings are kept" bash -c "sed -n '/^\[Mouse\]\$/,/^\[/p' '$tmp/kcminputrc' | grep -qx 'cursorTheme=breeze_cursors'"
check "the new groups start on a line of their own" grep -qx '\[Libinput\]\[Defaults\]\[Touchpad\]' "$tmp/kcminputrc"
check "touchpads scroll naturally by default" test "$(input_default Touchpad)" = "NaturalScroll=true"
check "mice scroll naturally by default" test "$(input_default Pointer)" = "NaturalScroll=true"

if ((fails > 0)); then
	echo "$fails check(s) failed"
	exit 1
fi
echo "all checks passed"
