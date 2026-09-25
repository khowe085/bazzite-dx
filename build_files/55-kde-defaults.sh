#!/usr/bin/bash
set -euxo pipefail

# Bazzite names its default global theme (Vapor) in /etc/xdg/kdeglobals, next to settings that
# stay. Plasma applies this at login to every user who has not picked a global theme of their own.
KDEGLOBALS="${KDE_DEFAULTS_KDEGLOBALS:-/etc/xdg/kdeglobals}"

# Checked first: sed changes nothing, without complaint, if the base stops setting the key here.
grep -q '^LookAndFeelPackage=' "$KDEGLOBALS"
sed -i 's/^LookAndFeelPackage=.*/LookAndFeelPackage=org.fedoraproject.fedoradark.desktop/' "$KDEGLOBALS"

# The Deck's file (bazzite-dx is built on bazzite-deck) also has the compositor scale X11 apps
# ([KScreen] XwaylandClientsScale=false), which blurs them on a scaled display. Bazzite's desktop edition
# keeps KDE's default, where they scale themselves; the key goes whatever its value is spelled like.
sed -i '/^XwaylandClientsScale=/d' "$KDEGLOBALS"

# Konsole starts with its built-in profile instead of Bazzite's Vapor one. Bazzite names Vapor here
# rather than in konsolerc, which Konsole reads on top of kdeglobals. Without the line Konsole already
# uses its built-in profile, so there is nothing to check first.
sed -i '/^DefaultProfile=/d' "$KDEGLOBALS"

# Input defaults for touchpads and mice: natural scrolling, no pointer acceleration (libinput's flat
# profile, "Enable pointer acceleration" unchecked in System Settings) and tap-and-drag that lets the
# finger lift briefly ("Allow briefly lifting finger during tap-and-drag"; devices that cannot tap
# ignore it). KWin takes per-device-type defaults from these groups (a touchpad reads Touchpad, any
# other pointing device Pointer); a value chosen in System Settings is stored per device in the
# user's own kcminputrc and wins.
# Keyboard is there for keyboards with a built-in touchpad or trackball that show up as one device:
# KWin checks for a keyboard first and gives such a device that group alone. Plain keyboards have no
# scroll direction for it to apply to.
# Appended, not written: the base may ship a kcminputrc, and KConfig merges a group that repeats.
KCMINPUTRC="${KDE_DEFAULTS_KCMINPUTRC:-/etc/xdg/kcminputrc}"
INPUT_DEFAULTS=(NaturalScroll=true PointerAccelerationProfile=1 TapDragLock=true)

# A device whose type has a group reads nothing from [Libinput][Defaults] itself, where Bazzite
# turns acceleration off for every device. A key the base sets there and these groups do not repeat
# would be lost without a word.
if [[ -e "$KCMINPUTRC" ]]; then
	# An assignment, so that set -e stops the build if sed fails; a for list would not.
	base_keys=$(sed -n '/^\[Libinput\]\[Defaults\]$/,/^\[/{/^[^[#]/s/[=[].*//p}' "$KCMINPUTRC")
	for key in $base_keys; do
		if [[ " ${INPUT_DEFAULTS[*]%%=*} " != *" $key "* ]]; then
			echo "The base sets $key in [Libinput][Defaults]; the device type groups would hide it" >&2
			exit 1
		fi
	done
fi
for type in Touchpad Pointer Keyboard; do
	printf '\n[Libinput][Defaults][%s]\n' "$type"
	printf '%s\n' "${INPUT_DEFAULTS[@]}"
done >>"$KCMINPUTRC"

# The top-left screen corner does nothing. Overview claims it unless told otherwise, and 9 (no edge)
# is what System Settings saves for Overview when the corner is set to "No Action".
printf '\n[Effect-overview]\nBorderActivate=9\n' >>"${KDE_DEFAULTS_KWINRC:-/etc/xdg/kwinrc}"

# The screen never locks by itself, but does lock after waking from sleep. Bazzite already turns
# Autolock off, but System Settings shows the Timeout, so it reads "5 minutes" (the default) although
# nothing locks; choosing "Never" there writes both keys. Bazzite's Deck file also sets
# LockOnResume=false; within one file KConfig takes the last value, so this group overrides it.
printf '\n[Daemon]\nAutolock=false\nTimeout=0\nLockOnResume=true\n' >>"${KDE_DEFAULTS_KSCREENLOCKERRC:-/etc/xdg/kscreenlockerrc}"

# Notification popups appear at the top centre, below the top bar, and low-priority notifications
# are kept in the history too. Appended: Plasma ships this file with per-application defaults.
printf '\n[Notifications]\nPopupPosition=TopCenter\nLowPriorityHistory=true\n' >>"${KDE_DEFAULTS_PLASMANOTIFYRC:-/etc/xdg/plasmanotifyrc}"

# Deck-only files of steamdeck-kde-presets: bazzite-dx is built on bazzite-deck, and Bazzite's desktop
# edition (steamdeck-kde-presets-desktop) deletes them. The "Return to Gaming Mode" shortcut on every
# new user's desktop, the IBus input-method daemon with its session variable at every KDE login, and
# Baloo indexing file names only.
rm -f "${KDE_DEFAULTS_RETURN_SHORTCUT:-/etc/skel/Desktop/Return.desktop}" \
	"${KDE_DEFAULTS_IBUS_AUTOSTART:-/etc/xdg/autostart/ibus.desktop}" \
	"${KDE_DEFAULTS_IBUS_ENV:-/etc/xdg/plasma-workspace/env/ibus.sh}" \
	"${KDE_DEFAULTS_BALOOFILERC:-/etc/xdg/baloofilerc}"

# The power profiles are in /etc/xdg/powerdevilrc (system_files). Bazzite also ships the Steam
# Deck's Plasma 5 profiles, which powerdevil copies into a new user's own powerdevilrc at the first
# login, where they would beat those defaults. Nothing else reads the Plasma 5 file.
rm -f "${KDE_DEFAULTS_PLASMA5_POWER_PROFILES:-/etc/xdg/powermanagementprofilesrc}"

# Panels do not float. There is no default for it: a panel's floating state is set where the panel
# is made, and these Add Panel templates are where they are made (a new profile's default layout
# loads one of them too).
TEMPLATES="${KDE_DEFAULTS_LAYOUT_TEMPLATES:-/usr/share/plasma/layout-templates}"
layouts=("$TEMPLATES"/*/contents/layout.js)
# Checked first, as above, and for every template before any is changed: each makes one panel, `panel`.
for layout in "${layouts[@]}"; do
	grep -qx 'var panel = new Panel' "$layout"
	test "$(grep -c 'new Panel' "$layout")" = 1
done
sed -i '/^var panel = new Panel$/a panel.floating = false' "${layouts[@]}"

# The default global theme, Fedora Dark, decides two more things for a new profile, and its choices
# outrank /etc/xdg: the window decoration it copies into ~/.config/kdedefaults, and the desktop layout.
LNF="${KDE_DEFAULTS_LNF:-/usr/share/plasma/look-and-feel/org.fedoraproject.fedoradark.desktop}"

# Window decoration Plastik instead of Breeze. Checked first: both keys in the decoration group.
DECORATION_GROUP='/^\[kwinrc\]\[org\.kde\.kdecoration2\]$/,/^\[/'
test "$(sed -n "${DECORATION_GROUP}{/^library=/p;/^theme=/p}" "$LNF/contents/defaults" | wc -l)" = 2
sed -i "${DECORATION_GROUP}{s/^library=.*/library=org.kde.kwin.aurorae/;s/^theme=.*/theme=kwin4_decoration_qml_plastik/}" \
	"$LNF/contents/defaults"

# Two panels instead of Bazzite's default one: this image's top bar and dock (Add Panel templates in
# system_files). Checked first, as above, unless an earlier run already made the change.
LAYOUT="$LNF/contents/layouts/org.kde.plasma.desktop-layout.js"
if ! grep -qx 'loadTemplate("io.github.khowe085.bazzite-dx.topBar")' "$LAYOUT"; then
	grep -qx 'loadTemplate("org.kde.plasma.desktop.defaultPanel")' "$LAYOUT"
	sed -i 's/^loadTemplate("org\.kde\.plasma\.desktop\.defaultPanel")$/loadTemplate("io.github.khowe085.bazzite-dx.topBar")\nloadTemplate("io.github.khowe085.bazzite-dx.dock")/' "$LAYOUT"
fi

# System Monitor's Overview page, which a profile shows until it saves a page of its own: the hottest
# CPU temperature under CPU usage, and the battery's charge rate where the disks were. Edited in place
# rather than replaced, so Plasma's translations stay. The battery is matched by pattern, like the
# page's own network and disk sensors, because its sensor is named after the battery's serial number
# (so a Bluetooth mouse or headset that reports a battery gets a line too, and a machine without a
# battery shows an empty chart);
# the two labels are keyed to one battery's sensors (the laptop's this was set up on), so others show
# the sensors' own names.
OVERVIEW="${KDE_DEFAULTS_SYSMON_OVERVIEW:-/usr/share/plasma-systemmonitor/overview.page}"
TEMP_FACE=Face-94212943519072
BATTERY_FACE=Face-94304568396688
CPU_FACE=Face-106123380916688
GPU_FACE=Face-106123406501568
DISKS_FACE=Face-106123488899456
page_read() { # page_read <group>... <key>
	local groups=()
	while (($# > 1)); do
		groups+=(--group "$1")
		shift
	done
	kreadconfig6 --file "$OVERVIEW" "${groups[@]}" --key "$1"
}
page_write() { # page_write <group>... <key> <value>
	local groups=()
	while (($# > 2)); do
		groups+=(--group "$1")
		shift
	done
	# After --, so a value such as -50 is not taken for an option.
	kwriteconfig6 --file "$OVERVIEW" "${groups[@]}" --key "$1" -- "$2"
}
if [[ "$(page_read page row-0 column-0 section-1 face)" != "$TEMP_FACE" ]]; then
	# Checked first, unless an earlier run already made the change: CPU, a separator and the GPU in
	# the first column, and the disks where the battery goes.
	test "$(page_read page row-0 column-0 section-0 face)" = "$CPU_FACE"
	test "$(page_read page row-0 column-0 section-1 isSeparator)" = true
	test "$(page_read page row-0 column-0 section-2 face)" = "$GPU_FACE"
	test -z "$(page_read page row-0 column-0 section-3 face)"
	test "$(page_read page row-1 column-0 section-0 face)" = "$DISKS_FACE"
	# kwriteconfig6 drops comments, among them the file's SPDX licence header; put it back after.
	header="$(sed -n '/^#/p;/^#/!q' "$OVERVIEW")"

	page_write "$TEMP_FACE" Appearance chartFace org.kde.ksysguard.piechart
	page_write "$TEMP_FACE" Appearance title Temp
	page_write "$TEMP_FACE" Sensors highPrioritySensorIds '["cpu/all/maximumTemperature"]'
	page_write "$TEMP_FACE" Sensors totalSensors '["cpu/all/maximumTemperature"]'
	page_write "$TEMP_FACE" SensorColors cpu/all/maximumTemperature 233,61,225
	page_write "$TEMP_FACE" SensorLabels cpu/all/maximumTemperature Max
	page_write "$TEMP_FACE" org.kde.ksysguard.piechart General rangeAuto false
	page_write "$TEMP_FACE" org.kde.ksysguard.piechart General rangeFrom 30

	page_write "$BATTERY_FACE" Appearance chartFace org.kde.ksysguard.linechart
	page_write "$BATTERY_FACE" Appearance title Battery
	page_write "$BATTERY_FACE" Sensors highPrioritySensorIds '["power/.*/chargeRate"]'
	page_write "$BATTERY_FACE" Sensors lowPrioritySensorIds '["power/.*/chargePercentage"]'
	page_write "$BATTERY_FACE" SensorLabels power/1AEE/chargeRate "Charging Rate"
	page_write "$BATTERY_FACE" SensorLabels power/1AEE/chargePercentage "Charge %"
	page_write "$BATTERY_FACE" SensorColors power/1AEE/chargeRate 61,233,134
	page_write "$BATTERY_FACE" SensorColors power/1AEE/chargePercentage 110,61,233
	page_write "$BATTERY_FACE" org.kde.ksysguard.linechart General rangeAutoY false
	page_write "$BATTERY_FACE" org.kde.ksysguard.linechart General rangeFromY -50

	# Sections are named after their position: the separator and the GPU move down one.
	page_write page row-0 column-0 section-3 face "$GPU_FACE"
	page_write page row-0 column-0 section-3 isSeparator false
	page_write page row-0 column-0 section-3 name section-3
	page_write page row-0 column-0 section-2 face ""
	page_write page row-0 column-0 section-2 isSeparator true
	page_write page row-0 column-0 section-1 face "$TEMP_FACE"
	page_write page row-0 column-0 section-1 isSeparator false
	page_write page row-1 column-0 section-0 face "$BATTERY_FACE"
	if [[ -n "$header" ]]; then
		printf '%s\n\n%s\n' "$header" "$(<"$OVERVIEW")" >"${OVERVIEW}.new"
		chmod --reference="$OVERVIEW" "${OVERVIEW}.new"
		mv "${OVERVIEW}.new" "$OVERVIEW"
	fi
fi
