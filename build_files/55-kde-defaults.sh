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
