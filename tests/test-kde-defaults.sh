#!/usr/bin/bash
# Exercises build_files/55-kde-defaults.sh, which sets the image's KDE defaults, against scratch
# copies of the Bazzite files it changes: kdeglobals (Fedora Dark as the default global theme, X11 apps
# scaling themselves), kcminputrc (input defaults), kwinrc (top-left screen corner), kscreenlockerrc
# (no automatic lock, lock after waking from sleep), plasmanotifyrc (where popups appear), the Plasma 5
# power profiles and the Deck-only files it removes, the Add Panel templates (panels that do not float,
# the image's own two among them) and Fedora Dark (window decoration, the image's panels in its layout).
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
TEMPLATES="$tmp/layout-templates"
LNF="$tmp/fedoradark"
OWN_TEMPLATES=(io.github.khowe085.bazzite-dx.topBar io.github.khowe085.bazzite-dx.dock)
run_step() {
	env KDE_DEFAULTS_KDEGLOBALS="$tmp/kdeglobals" KDE_DEFAULTS_KCMINPUTRC="$tmp/kcminputrc" \
		KDE_DEFAULTS_KWINRC="$tmp/kwinrc" KDE_DEFAULTS_KSCREENLOCKERRC="$tmp/kscreenlockerrc" \
		KDE_DEFAULTS_PLASMA5_POWER_PROFILES="$tmp/powermanagementprofilesrc" \
		KDE_DEFAULTS_LAYOUT_TEMPLATES="$TEMPLATES" KDE_DEFAULTS_RETURN_SHORTCUT="$tmp/Return.desktop" \
		KDE_DEFAULTS_IBUS_AUTOSTART="$tmp/ibus.desktop" KDE_DEFAULTS_IBUS_ENV="$tmp/ibus.sh" \
		KDE_DEFAULTS_BALOOFILERC="$tmp/baloofilerc" KDE_DEFAULTS_PLASMANOTIFYRC="$tmp/plasmanotifyrc" \
		KDE_DEFAULTS_LNF="$LNF" bash "$STEP"
}
step_fails() { ! run_step; }
# kread <file> <group>... <key>: the value KDE's own parser reads from that scratch file.
kread() {
	local file="$tmp/$1" groups=()
	shift
	while (($# > 1)); do
		groups+=(--group "$1")
		shift
	done
	kreadconfig6 --file "$file" "${groups[@]}" --key "$1"
}
# Bazzite's /etc/xdg/kdeglobals (steamdeck-kde-presets, the Deck variant bazzite-dx gets from
# bazzite-deck), shortened to one font line.
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
# The other Bazzite files the step changes (steamdeck-kde-presets, plasma-desktop), the power
# profiles and the templates shortened.
write_bazzite_files() {
	write_bazzite_kdeglobals
	printf '[Libinput][Defaults]\nPointerAccelerationProfile=1\n' >"$tmp/kcminputrc"
	cat >"$tmp/kwinrc" <<'EOF'
[Wayland]
InputMethod[$e]=/usr/share/applications/com.github.maliit.keyboard.desktop
VirtualKeyboardEnabled=true
EOF
	printf '[Daemon]\nAutolock=false\nLockOnResume=false\n' >"$tmp/kscreenlockerrc"
	printf '[AC][DPMSControl]\nidleTime=600\nlockBeforeTurnOff=1\n' >"$tmp/powermanagementprofilesrc"
	# Deck-only files of steamdeck-kde-presets, which bazzite-dx gets from bazzite-deck.
	printf '[Desktop Entry]\nName=Return to Gaming Mode\nExec=/usr/bin/return-to-gamemode\n' >"$tmp/Return.desktop"
	printf '[Desktop Entry]\nName=IBus\nExec=ibus-daemon --panel=/usr/libexec/kimpanel-ibus-panel\n' >"$tmp/ibus.desktop"
	printf 'export XMODIFIERS= @ im = ibus\n' >"$tmp/ibus.sh"
	printf '[General]\nonly basic indexing=true\n' >"$tmp/baloofilerc"
	rm -rf "$TEMPLATES"
	mkdir -p "$TEMPLATES"/org.kde.plasma.desktop.{defaultPanel,emptyPanel,appmenubar}/contents
	# Bazzite's own version of the default panel, which names another panel `panel` further down.
	cat >"$TEMPLATES/org.kde.plasma.desktop.defaultPanel/contents/layout.js" <<'EOF'
var panel = new Panel
var panelScreen = panel.screen
panel.height = 2 * Math.ceil(gridUnit * 2.5 / 2)
panel.addWidget("org.kde.plasma.kickoff")

const allPanels = panels();

for (let i = 0; i < allPanels.length; ++i) {
    const panel = allPanels[i];
}
EOF
	printf 'var panel = new Panel\nvar panelScreen = panel.screen\npanel.height = gridUnit * 2\n' \
		>"$TEMPLATES/org.kde.plasma.desktop.emptyPanel/contents/layout.js"
	printf 'var panel = new Panel\npanel.location = "top";\npanel.addWidget("org.kde.plasma.appmenu");\n' \
		>"$TEMPLATES/org.kde.plasma.desktop.appmenubar/contents/layout.js"
	# The image's own templates, as system_files puts them next to the base's before the step runs.
	for template in "${OWN_TEMPLATES[@]}"; do
		cp -r "$SRC/system_files/usr/share/plasma/layout-templates/$template" "$TEMPLATES/"
	done
	# Plasma's plasmanotifyrc, shortened.
	printf '[Applications][org.kde.spectacle]\nShowPopupsInDndMode=true\n' >"$tmp/plasmanotifyrc"
	# Fedora Dark (plasma-lookandfeel-fedora), shortened.
	rm -rf "$LNF"
	mkdir -p "$LNF/contents/layouts"
	cat >"$LNF/contents/defaults" <<'EOF2'
[kdeglobals][General]
ColorScheme=BreezeDark

[kwinrc][org.kde.kdecoration2]
library=org.kde.breeze
theme=Breeze

[ksplashrc][KSplash]
Theme=org.kde.breeze.desktop
EOF2
	cat >"$LNF/contents/layouts/org.kde.plasma.desktop-layout.js" <<'EOF2'
loadTemplate("org.kde.plasma.desktop.defaultPanel")

var desktopsArray = desktopsForActivity(currentActivity());
EOF2
}

echo "== Bazzite's kdeglobals"
write_bazzite_files
cp "$tmp/kdeglobals" "$tmp/before"
check "build step exits 0" run_step
check "Fedora Dark is the default global theme" grep -qx 'LookAndFeelPackage=org.fedoraproject.fedoradark.desktop' "$tmp/kdeglobals"
check "Vapor no longer is" bash -c "! grep -q 'com.valve.vapor.desktop' '$tmp/kdeglobals'"
check "the setting is still in the [KDE] group, right below its header" bash -c "grep -A1 -Fx '[KDE]' '$tmp/kdeglobals' | grep -q '^LookAndFeelPackage='"
check "Konsole no longer starts with Bazzite's Vapor profile, but with its built-in one" bash -c "! grep -q '^DefaultProfile=' '$tmp/kdeglobals'"
check "nothing else in the file changed" test "$(diff "$tmp/before" "$tmp/kdeglobals" | grep -c '^[<>]')" = 3

echo "== Bazzite's Deck kdeglobals has the compositor scale X11 apps"
write_bazzite_files
printf '\n[KScreen]\nXwaylandClientsScale=false\n' >>"$tmp/kdeglobals"
cp "$tmp/kdeglobals" "$tmp/before"
check "build step exits 0" run_step
check "X11 apps scale themselves again, KDE's default (sharp on a scaled display)" test -z "$(kread kdeglobals KScreen XwaylandClientsScale)"
check "only that line, the theme line and Konsole's profile changed" test "$(diff "$tmp/before" "$tmp/kdeglobals" | grep -c '^[<>]')" = 4

echo "== second run"
cp "$tmp/kdeglobals" "$tmp/once"
check "build step exits 0" run_step
check "the file is unchanged" cmp -s "$tmp/once" "$tmp/kdeglobals"

echo "== the base no longer names a Konsole profile in kdeglobals"
write_bazzite_files
sed -i '/^DefaultProfile=/d' "$tmp/kdeglobals"
check "build step exits 0 (Konsole already starts with its built-in profile)" run_step

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
# shows up as one device gets the Keyboard group, and only that one. A device that has a type group
# reads nothing from [Libinput][Defaults] itself.
check_input_defaults() {
	check "touchpads scroll naturally by default" test "$(kread kcminputrc Libinput Defaults Touchpad NaturalScroll)" = true
	check "mice scroll naturally by default" test "$(kread kcminputrc Libinput Defaults Pointer NaturalScroll)" = true
	check "so do pointing devices built into a keyboard" test "$(kread kcminputrc Libinput Defaults Keyboard NaturalScroll)" = true
	for type in Touchpad Pointer Keyboard; do
		check "no pointer acceleration by default for $type devices (libinput's flat profile)" test "$(kread kcminputrc Libinput Defaults "$type" PointerAccelerationProfile)" = 1
		check "tap-and-drag lets the finger lift briefly by default for $type devices" test "$(kread kcminputrc Libinput Defaults "$type" TapDragLock)" = true
	done
}
echo "== input defaults, no system kcminputrc in the base"
write_bazzite_files
rm -f "$tmp/kcminputrc"
check "build step exits 0" run_step
check_input_defaults

echo "== input defaults, the base ships a kcminputrc of its own (here without a final newline)"
write_bazzite_files
printf '[Mouse]\ncursorTheme=breeze_cursors' >"$tmp/kcminputrc"
check "build step exits 0" run_step
check "its settings are kept" bash -c "sed -n '/^\[Mouse\]\$/,/^\[/p' '$tmp/kcminputrc' | grep -qx 'cursorTheme=breeze_cursors'"
check "the new groups start on a line of their own" grep -qx '\[Libinput\]\[Defaults\]\[Touchpad\]' "$tmp/kcminputrc"
check_input_defaults

echo "== input defaults, Bazzite's kcminputrc: no pointer acceleration for every device"
write_bazzite_files
check "build step exits 0" run_step
check "the base's own default is kept" test "$(kread kcminputrc Libinput Defaults PointerAccelerationProfile)" = 1
check_input_defaults

echo "== the base sets another input default for every device"
write_bazzite_files
printf '[Libinput][Defaults]\nPointerAccelerationProfile=1\nScrollFactor=2\n' >"$tmp/kcminputrc"
cp "$tmp/kcminputrc" "$tmp/before"
check "build step fails instead of hiding it from touchpads, mice and keyboards" step_fails
check "the file is left as it was" cmp -s "$tmp/before" "$tmp/kcminputrc"

echo "== top-left screen corner, Bazzite's kwinrc"
write_bazzite_files
check "build step exits 0" run_step
check "Overview no longer claims the corner (9 is no edge, what System Settings saves for No Action)" test "$(kread kwinrc Effect-overview BorderActivate)" = 9
check "Bazzite's settings are kept" test "$(kread kwinrc Wayland VirtualKeyboardEnabled)" = true

echo "== automatic screen lock, Bazzite's kscreenlockerrc"
check "the screen does not lock by itself" test "$(kread kscreenlockerrc Daemon Autolock)" = false
check "and System Settings shows Never, which it reads from the timeout" test "$(kread kscreenlockerrc Daemon Timeout)" = 0
check "but it locks after waking from sleep, which Bazzite's Deck file turns off" test "$(kread kscreenlockerrc Daemon LockOnResume)" = true

echo "== automatic screen lock, the base no longer turns it off"
write_bazzite_files
printf '[Daemon]\nLockOnResume=false\n' >"$tmp/kscreenlockerrc"
check "build step exits 0" run_step
check "the screen still does not lock by itself" test "$(kread kscreenlockerrc Daemon Autolock)" = false

echo "== notifications, Plasma's plasmanotifyrc"
write_bazzite_files
check "build step exits 0" run_step
check "popups appear at the top centre" test "$(kread plasmanotifyrc Notifications PopupPosition)" = TopCenter
check "low-priority notifications are kept in the history" test "$(kread plasmanotifyrc Notifications LowPriorityHistory)" = true
check "Plasma's per-application defaults are kept" test "$(kread plasmanotifyrc Applications org.kde.spectacle ShowPopupsInDndMode)" = true

echo "== Deck-only files, which Bazzite's desktop edition does not ship"
write_bazzite_files
check "build step exits 0" run_step
check "new users get no Return to Gaming Mode shortcut on the desktop" test ! -e "$tmp/Return.desktop"
check "the IBus daemon no longer starts at login" test ! -e "$tmp/ibus.desktop"
check "nor is the session told to use it" test ! -e "$tmp/ibus.sh"
check "Baloo indexes file contents again, not only names" test ! -e "$tmp/baloofilerc"

echo "== the base no longer ships those Deck-only files"
write_bazzite_files
rm -f "$tmp/Return.desktop" "$tmp/ibus.desktop" "$tmp/ibus.sh" "$tmp/baloofilerc"
check "build step exits 0" run_step

echo "== Bazzite's Plasma 5 power profiles"
check "are removed, so powerdevil copies nothing from them into a new profile" test ! -e "$tmp/powermanagementprofilesrc"

echo "== the base no longer ships them"
write_bazzite_files
rm -f "$tmp/powermanagementprofilesrc"
check "build step exits 0" run_step

echo "== Add Panel templates"
write_bazzite_files
cp -r "$TEMPLATES" "$tmp/templates-before"
check "build step exits 0" run_step
for template in org.kde.plasma.desktop.defaultPanel org.kde.plasma.desktop.emptyPanel org.kde.plasma.desktop.appmenubar "${OWN_TEMPLATES[@]}"; do
	layout="$TEMPLATES/$template/contents/layout.js"
	check "$template turns floating off right after making its panel" test "$(sed -n 2p "$layout")" = 'panel.floating = false'
	check "$template has no other change" test "$(diff "$tmp/templates-before/$template/contents/layout.js" "$layout" | grep -c '^[<>]')" = 1
done

echo "== the image's own templates"
for template in "${OWN_TEMPLATES[@]}"; do
	check "$template names itself by its directory, which is how layouts load it" grep -q "\"Id\": \"$template\"" "$TEMPLATES/$template/metadata.json"
	check "$template is offered in Add Panel" grep -q '"panel"' "$TEMPLATES/$template/metadata.json"
done
TOP="$TEMPLATES/io.github.khowe085.bazzite-dx.topBar/contents/layout.js"
DOCK="$TEMPLATES/io.github.khowe085.bazzite-dx.dock/contents/layout.js"
check "the top bar is at the top" grep -qx 'panel.location = "top"' "$TOP"
check "the dock is at the bottom" grep -qx 'panel.location = "bottom"' "$DOCK"
check "and hides itself" grep -qx 'panel.hiding = "autohide"' "$DOCK"
# Widget order, left to right, as `addWidget` calls.
widgets() { sed -n 's/.*addWidget("\([^"]*\)").*/\1/p' "$1" | paste -sd' '; }
check "the top bar's widgets in order" test "$(widgets "$TOP")" = "org.kde.plasma.systemmonitor.cpu org.kde.plasma.systemmonitor.memory org.kde.plasma.systemmonitor.cpucore org.kde.plasma.systemmonitor.net org.kde.plasma.systemmonitor.diskactivity org.kde.plasma.pager org.kde.plasma.panelspacer org.kde.plasma.systemtray org.kde.plasma.volume org.kde.plasma.cameraindicator org.kde.plasma.networkmanagement org.kde.plasma.bluetooth org.kde.plasma.brightness org.kde.plasma.battery org.kde.plasma.digitalclock org.kde.plasma.userswitcher"
check "the dock's widgets in order" test "$(widgets "$DOCK")" = "org.kde.plasma.kickoff org.kde.plasma.icontasks org.kde.plasma.marginsseparator org.kde.plasma.notifications"
check "no widget in the top bar is also shown inside its tray" bash -c "! sed -n '/\"extraItems\"/,/])/p' '$TOP' | grep -Eq 'plasma\.(volume|cameraindicator|networkmanagement|bluetooth|brightness|battery|notifications)\"'"

echo "== Fedora Dark, the default global theme"
write_bazzite_files
cp "$LNF/contents/defaults" "$tmp/before"
check "build step exits 0" run_step
check "new profiles get the Plastik window decoration" test "$(kread fedoradark/contents/defaults kwinrc org.kde.kdecoration2 library)" = org.kde.kwin.aurorae
check "Plastik's theme name" test "$(kread fedoradark/contents/defaults kwinrc org.kde.kdecoration2 theme)" = kwin4_decoration_qml_plastik
check "nothing else in the theme's defaults changed" test "$(diff "$tmp/before" "$LNF/contents/defaults" | grep -c '^[<>]')" = 4
check "its layout makes the image's top bar and dock, in that order" test "$(grep '^loadTemplate' "$LNF/contents/layouts/org.kde.plasma.desktop-layout.js" | paste -sd' ')" = 'loadTemplate("io.github.khowe085.bazzite-dx.topBar") loadTemplate("io.github.khowe085.bazzite-dx.dock")'
check "and the rest of the layout is kept" grep -q 'desktopsForActivity' "$LNF/contents/layouts/org.kde.plasma.desktop-layout.js"
cp -r "$LNF" "$tmp/lnf-once"
check "a second run exits 0" run_step
check "and changes nothing more there" diff -r "$tmp/lnf-once" "$LNF"
rm -rf "$tmp/lnf-once"

echo "== Fedora Dark no longer sets a window decoration"
write_bazzite_files
sed -i '/^library=/d' "$LNF/contents/defaults"
check "build step fails instead of leaving Breeze" step_fails

echo "== Fedora Dark's layout no longer loads the default panel"
write_bazzite_files
printf 'loadTemplate("org.kde.plasma.desktop.otherPanel")\n' >"$LNF/contents/layouts/org.kde.plasma.desktop-layout.js"
check "build step fails instead of leaving that layout" step_fails

echo "== a template makes its panel some other way"
write_bazzite_files
printf 'var bar = new Panel\nbar.location = "top";\n' >"$TEMPLATES/org.kde.plasma.desktop.appmenubar/contents/layout.js"
rm -rf "$tmp/templates-before"
cp -r "$TEMPLATES" "$tmp/templates-before"
check "build step fails instead of leaving that panel floating" step_fails
check "no template is changed" diff -r "$tmp/templates-before" "$TEMPLATES"

echo "== a template makes a second panel"
write_bazzite_files
printf 'var dock = new Panel\ndock.location = "left";\n' >>"$TEMPLATES/org.kde.plasma.desktop.emptyPanel/contents/layout.js"
rm -rf "$tmp/templates-before"
cp -r "$TEMPLATES" "$tmp/templates-before"
check "build step fails instead of leaving the second one floating" step_fails
check "no template is changed" diff -r "$tmp/templates-before" "$TEMPLATES"

echo "== the base no longer ships the templates there"
write_bazzite_files
rm -rf "$TEMPLATES"
check "build step fails" step_fails

if ((fails > 0)); then
	echo "$fails check(s) failed"
	exit 1
fi
echo "all checks passed"
