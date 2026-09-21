#!/usr/bin/bash
set -euxo pipefail

# Bazzite names its default global theme (Vapor) in /etc/xdg/kdeglobals, next to settings that
# stay. Plasma applies this at login to every user who has not picked a global theme of their own.
KDEGLOBALS="${KDE_DEFAULTS_KDEGLOBALS:-/etc/xdg/kdeglobals}"

# Checked first: sed changes nothing, without complaint, if the base stops setting the key here.
grep -q '^LookAndFeelPackage=' "$KDEGLOBALS"
sed -i 's/^LookAndFeelPackage=.*/LookAndFeelPackage=org.fedoraproject.fedoradark.desktop/' "$KDEGLOBALS"

# Natural scrolling as the default for touchpads and mice. KWin takes per-device-type defaults from
# these groups (a touchpad reads Touchpad, any other pointing device Pointer); a direction chosen in
# System Settings is stored per device in the user's own kcminputrc and wins.
# Keyboard is there for keyboards with a built-in touchpad or trackball that show up as one device:
# KWin checks for a keyboard first and gives such a device that group alone. Plain keyboards have no
# scroll direction for it to apply to.
# Appended, not written: the base may ship a kcminputrc, and KConfig merges a group that repeats.
KCMINPUTRC="${KDE_DEFAULTS_KCMINPUTRC:-/etc/xdg/kcminputrc}"
printf '\n[Libinput][Defaults][%s]\nNaturalScroll=true\n' Touchpad Pointer Keyboard >>"$KCMINPUTRC"
