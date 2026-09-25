#!/usr/bin/bash
# Image test: asserts everything build_files/*.sh and system_files/ must produce.
# Runs as the last build step; can also be run standalone against any image
# (it fails against the untouched bazzite-dx base).
set -uo pipefail

fails=0
check() { # check <description> <command...>
	local desc=$1
	shift
	if "$@" >/dev/null 2>&1; then
		echo "ok   - $desc"
	else
		echo "FAIL - $desc"
		fails=$((fails + 1))
	fi
}
mode_of() { stat -c '%a %U:%G' "$1" 2>/dev/null; }

OP=/usr/lib/opt/1Password
POLICY=/usr/share/polkit-1/actions/com.1password.1Password.policy
HOOK=/usr/share/ublue-os/user-setup.hooks.d/30-emudeck.sh
FF_SETUP=/usr/libexec/onepassword-firefox-flatpak-setup
FF_PREF=/usr/share/ublue-os/firefox-config/zz-onepassword-native-messaging.js
JUST_DIR=/usr/share/ublue-os/just

echo "== .NET 10 SDK"
check "dotnet-sdk-10.0 package installed" rpm -q dotnet-sdk-10.0
check "dotnet lists a 10.0 SDK" bash -c 'DOTNET_CLI_HOME=/tmp dotnet --list-sdks | grep -q "^10\.0\."'

echo "== 1Password"
check "1password package installed" rpm -q 1password
check "payload relocated to $OP" test -x "$OP/1password"
check "tmpfiles.d recreates the /var/opt/1Password link" grep -qx 'L+ /var/opt/1Password - - - - /usr/lib/opt/1Password' /usr/lib/tmpfiles.d/onepassword.conf
check "/usr/bin/1password resolves through /opt" test "$(readlink /usr/bin/1password)" = /opt/1Password/1password
check "onepassword group has the fixed GID 20200" test "$(getent group onepassword | cut -d: -f3)" = 20200
check "onepassword-mcp group has the fixed GID 20201" test "$(getent group onepassword-mcp | cut -d: -f3)" = 20201
check "sysusers.d declares onepassword with the same GID" grep -Eqx 'g[[:space:]]+onepassword[[:space:]]+20200' /usr/lib/sysusers.d/onepassword.conf
check "sysusers.d declares onepassword-mcp with the same GID" grep -Eqx 'g[[:space:]]+onepassword-mcp[[:space:]]+20201' /usr/lib/sysusers.d/onepassword.conf
check "1Password-BrowserSupport is root:onepassword 2755" test "$(mode_of "$OP/1Password-BrowserSupport")" = "2755 root:onepassword"
check "1password-mcp is root:onepassword-mcp 2755" test "$(mode_of "$OP/1password-mcp")" = "2755 root:onepassword-mcp"
check "chrome-sandbox is root:root 4755" test "$(mode_of "$OP/chrome-sandbox")" = "4755 root:root"
check "polkit policy installed" test -f "$POLICY"
check "polkit policy owners include the first desktop user (uid 1000)" grep -q 'unix-user:1000' "$POLICY"
check "polkit policy has no unexpanded template variable" bash -c "! grep -q 'POLICY_OWNERS' '$POLICY'"
check "1password repo present" test -f /etc/yum.repos.d/1password.repo
check "1password repo disabled" bash -c 'dnf5 repolist --disabled | grep -q "^1password "'
check "custom_allowed_browsers allows xdg-native-messaging-proxy" grep -qx 'xdg-native-messaging-proxy' /etc/1password/custom_allowed_browsers
check "custom_allowed_browsers is root:root 644" test "$(mode_of /etc/1password/custom_allowed_browsers)" = "644 root:root"

echo "== 1Password SSH agent and Git signing"
check "op-ssh-sign ships with 1Password" test -x "$OP/op-ssh-sign"
check "system git config signs with SSH" test "$(git config --system gpg.format)" = ssh
check "system git config uses 1Password's signer" test "$(git config --system gpg.ssh.program)" = /opt/1Password/op-ssh-sign
check "system git config signs commits by default" test "$(git config --system --type=bool commit.gpgsign)" = true
SSH_DROPIN=/etc/ssh/ssh_config.d/60-1password-agent.conf
check "ssh agent drop-in is root:root 644" test "$(mode_of "$SSH_DROPIN")" = "644 root:root"
check "drop-in points at 1Password's agent socket" grep -Eqx '[[:space:]]*IdentityAgent ~/\.1password/agent\.sock' "$SSH_DROPIN"
check "ssh_config pulls in ssh_config.d" grep -Eqi '^[[:space:]]*Include[[:space:]]+/etc/ssh/ssh_config\.d/\*\.conf' /etc/ssh/ssh_config
# The drop-in only applies with 1Password's socket present, which a build never has; what matters
# here is that the whole system ssh configuration still parses with it in place.
check "system ssh configuration parses with the drop-in" ssh -G example.com

echo "== Firefox flatpak <-> 1Password (xdg-native-messaging-proxy)"
check "xdg-native-messaging-proxy installed" rpm -q xdg-native-messaging-proxy
check "proxy package provides the org.freedesktop.NativeMessagingProxy bus service" bash -c 'rpm -ql xdg-native-messaging-proxy | grep -q "dbus-1/services/org.freedesktop.NativeMessagingProxy.service"'
check "setup script grants exactly that bus name" grep -q -- '--talk-name=org.freedesktop.NativeMessagingProxy ' "$FF_SETUP"
check "onepassword-firefox-flatpak.service enabled" systemctl is-enabled onepassword-firefox-flatpak.service
check "setup script is executable" test -x "$FF_SETUP"
check "setup script parses" bash -n "$FF_SETUP"
check "Firefox pref file enables the native-messaging proxy" grep -qx 'pref("widget.use-xdg-desktop-portal.native-messaging-proxy", 1);' "$FF_PREF"

echo "== Eden"
check "Eden AppImage shipped" test -x /usr/lib/eden/Eden.AppImage
check "Eden AppImage has the AppImage type-2 magic" bash -c 'test "$(dd if=/usr/lib/eden/Eden.AppImage bs=1 skip=8 count=3 2>/dev/null | od -An -c | tr -d " ")" = "AI002"'
check "Eden version stamp recorded" test -s /usr/lib/eden/VERSION

echo "== EmuDeck and Crunchyroll AppImages"
APPIMAGE_TOOL=/usr/libexec/image-appimage
for app in emudeck/EmuDeck crunchyroll/Crunchyroll; do
	check "${app#*/} AppImage shipped" test -x "/usr/lib/${app}.AppImage"
	check "${app#*/} AppImage has the AppImage type-2 magic" bash -c "test \"\$(dd if=/usr/lib/${app}.AppImage bs=1 skip=8 count=3 2>/dev/null | od -An -c | tr -d ' ')\" = AI002"
	check "${app#*/} version stamp recorded" test -s "/usr/lib/${app%/*}/VERSION"
done
check "$APPIMAGE_TOOL is executable" test -x "$APPIMAGE_TOOL"
check "$APPIMAGE_TOOL parses" bash -n "$APPIMAGE_TOOL"
# The build step fetches from the projects ujust uses, so the Portal's status and toggles still fit.
check "ujust get-emudeck still downloads from EmuDeck/emudeck-electron" grep -rqF 'https://api.github.com/repos/EmuDeck/emudeck-electron/releases/latest' "$JUST_DIR"
check "the Portal still gets Crunchyroll from aarron-lee/crunchyroll-linux" grep -rqF 'https://api.github.com/repos/aarron-lee/crunchyroll-linux/releases/latest' "$JUST_DIR"
# build_files/ is only there during the build (/ctx), not when this runs against a finished image.
APPIMAGES_STEP="$(dirname "${BASH_SOURCE[0]}")/fetch-appimages.sh"
if [[ -f "$APPIMAGES_STEP" ]]; then
	check "the build step fetches EmuDeck from there" grep -qx 'ship EmuDeck/emudeck-electron emudeck EmuDeck.AppImage' "$APPIMAGES_STEP"
	check "and Crunchyroll" grep -qx 'ship aarron-lee/crunchyroll-linux crunchyroll Crunchyroll.AppImage' "$APPIMAGES_STEP"
fi

echo "== EmuDeck first-login hook"
check "hook is executable" test -x "$HOOK"
check "hook parses" bash -n "$HOOK"
# The hook only runs if the base still ships the runner that scans this directory.
check "base runner scans $(dirname "$HOOK")" grep -q "$(dirname "$HOOK")" /usr/libexec/ublue-user-setup
check "ublue-user-setup.service is enabled for all users" systemctl --global is-enabled ublue-user-setup.service

echo "== Base units this image orders itself after"
check "bazzite-flatpak-manager.service still exists in the base" test -f /usr/lib/systemd/system/bazzite-flatpak-manager.service

echo "== KDE defaults"
LNF=org.fedoraproject.fedoradark.desktop
UPDATES_DIR=/usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates
POTD_SCRIPT="$UPDATES_DIR/picture-of-the-day-default.js"
check "Fedora Dark is the default global theme" grep -qx "LookAndFeelPackage=$LNF" /etc/xdg/kdeglobals
check "kdeglobals names one global theme only" test "$(grep -c '^LookAndFeelPackage=' /etc/xdg/kdeglobals)" = 1
check "the base ships that theme" test -f "/usr/share/plasma/look-and-feel/$LNF/metadata.json"
check "the rest of Bazzite's kdeglobals is still there" grep -qx 'kcm_updates=false' /etc/xdg/kdeglobals
# With --type bool, kreadconfig6 exits 0 only for true, however false is spelled.
check "X11 apps scale themselves, KDE's default rather than the Deck's" kreadconfig6 --file /etc/xdg/kdeglobals --group KScreen --key XwaylandClientsScale --type bool --default true
check "wallpaper update script shipped" test -f "$POTD_SCRIPT"
check "in the directory the base uses for its own Plasma update script" test -f "$UPDATES_DIR/bazzite-pins.js"
# Bazzite's Vapor theme writes its wallpaper into every profile it sets up; the script has to know
# that exact value to tell it from a picture the user chose.
VAPOR_WALLPAPER=/usr/share/wallpapers/convergence.jxl
check "Bazzite's Vapor theme still gives new profiles that wallpaper" grep -Fq "writeConfig(\"Image\", \"$VAPOR_WALLPAPER\")" /usr/share/plasma/look-and-feel/com.valve.vapor.desktop/contents/plasmoidsetupscripts/org.kde.plasma.folder.js
check "and the script counts it as untouched" grep -Fq "\"$VAPOR_WALLPAPER\"" "$POTD_SCRIPT"
check "the script selects the Picture of the Day wallpaper" grep -q 'wallpaperPlugin = "org.kde.potd"' "$POTD_SCRIPT"
check "with the Astronomy (NASA) provider" grep -q 'writeConfig("Provider", "apod")' "$POTD_SCRIPT"
check "the base ships that wallpaper type" test -f /usr/share/plasma/wallpapers/org.kde.potd/metadata.json
check "and that provider" test -f /usr/lib64/qt6/plugins/potd/plasma_potd_apodprovider.so
# Read back with KDE's own parser: KWin's Touchpad group covers touchpads, Pointer the other pointing devices.
input_default() { kreadconfig6 --file /etc/xdg/kcminputrc --group Libinput --group Defaults --group "$1" --key "$2"; }
for type in Touchpad Pointer Keyboard; do
	check "natural scrolling is the default for $type devices" test "$(input_default "$type" NaturalScroll)" = true
	check "no pointer acceleration is the default for $type devices" test "$(input_default "$type" PointerAccelerationProfile)" = 1
	check "tap-and-drag lets the finger lift briefly by default for $type devices" test "$(input_default "$type" TapDragLock)" = true
done
check "the top-left screen corner does nothing" test "$(kreadconfig6 --file /etc/xdg/kwinrc --group Effect-overview --key BorderActivate)" = 9
check "the screen does not lock by itself" test "$(kreadconfig6 --file /etc/xdg/kscreenlockerrc --group Daemon --key Autolock)" = false
check "and System Settings shows Never for that" test "$(kreadconfig6 --file /etc/xdg/kscreenlockerrc --group Daemon --key Timeout)" = 0
check "but it locks after waking from sleep" test "$(kreadconfig6 --file /etc/xdg/kscreenlockerrc --group Daemon --key LockOnResume)" = true
# bazzite-dx is built on bazzite-deck, so it has steamdeck-kde-presets' Deck-only files; the desktop edition does not.
for f in /etc/skel/Desktop/Return.desktop /etc/xdg/autostart/ibus.desktop /etc/xdg/plasma-workspace/env/ibus.sh /etc/xdg/baloofilerc; do
	check "the Deck-only $f is gone" test ! -e "$f"
done
for layout in /usr/share/plasma/layout-templates/*/contents/layout.js; do
	template=${layout%/contents/layout.js}
	check "the Add Panel template ${template##*/} makes a panel that does not float" bash -c "sed -n 2p '$layout' | grep -qx 'panel.floating = false'"
done
LNF_DIR="/usr/share/plasma/look-and-feel/$LNF"
check "Fedora Dark gives new profiles the Plastik window decoration" test "$(kreadconfig6 --file "$LNF_DIR/contents/defaults" --group kwinrc --group org.kde.kdecoration2 --key theme)" = kwin4_decoration_qml_plastik
check "through Aurorae" test "$(kreadconfig6 --file "$LNF_DIR/contents/defaults" --group kwinrc --group org.kde.kdecoration2 --key library)" = org.kde.kwin.aurorae
check "the base ships Plastik" test -f /usr/share/kwin/decorations/kwin4_decoration_qml_plastik/metadata.json
for template in io.github.khowe085.bazzite-dx.topBar io.github.khowe085.bazzite-dx.dock; do
	check "Fedora Dark's layout makes the panel of $template" grep -qx "loadTemplate(\"$template\")" "$LNF_DIR/contents/layouts/org.kde.plasma.desktop-layout.js"
	layout="/usr/share/plasma/layout-templates/$template/contents/layout.js"
	# Plasma skips a widget it cannot find without a word; they come as QML packages or compiled plugins.
	for widget in $(sed -n 's/.*addWidget("\([^"]*\)").*/\1/p' "$layout"); do
		check "$template: the base has the widget $widget" bash -c "test -e /usr/share/plasma/plasmoids/$widget/metadata.json || test -e /usr/lib64/qt6/plugins/plasma/applets/$widget.so"
	done
done
check "Bazzite's default panel is no longer in Fedora Dark's layout" bash -c "! grep -q 'org.kde.plasma.desktop.defaultPanel' '$LNF_DIR/contents/layouts/org.kde.plasma.desktop-layout.js'"
check "the dock's launcher icon (framework) is in the base" test -f /usr/share/icons/hicolor/scalable/apps/framework.svg
check "Konsole starts with its built-in profile: no default profile in kdeglobals" bash -c "! grep -q '^DefaultProfile=' /etc/xdg/kdeglobals"
check "nor in konsolerc" bash -c "! grep -q '^DefaultProfile=' /etc/xdg/konsolerc"
KONSOLE_SHORTCUTS=/etc/skel/.local/share/kxmlgui5/konsole/sessionui.rc
check "new users get Ctrl+V to paste in Konsole" grep -Fq '<Action name="edit_paste" shortcut="Ctrl+V; Shift+Ins"/>' "$KONSOLE_SHORTCUTS"
check "from a file older than Konsole's own, so Konsole's menus are used and the shortcut merged in" grep -qx '<gui name="session" version="1">' "$KONSOLE_SHORTCUTS"
check "notification popups appear at the top centre" test "$(kreadconfig6 --file /etc/xdg/plasmanotifyrc --group Notifications --key PopupPosition)" = TopCenter
check "low-priority notifications are kept in the history" test "$(kreadconfig6 --file /etc/xdg/plasmanotifyrc --group Notifications --key LowPriorityHistory)" = true

echo "== System Monitor's Overview page"
OVERVIEW=/usr/share/plasma-systemmonitor/overview.page
page_key() { kreadconfig6 --file "$OVERVIEW" "${@:1:$#-1}" --key "${!#}"; }
check "CPU temperature under CPU usage" test "$(page_key --group page --group row-0 --group column-0 --group section-1 face)" = Face-94212943519072
check "the GPU still in the first column" test "$(page_key --group page --group row-0 --group column-0 --group section-3 face)" = Face-106123406501568
check "the battery's charge rate where the disks were" test "$(page_key --group page --group row-1 --group column-0 --group section-0 face)" = Face-94304568396688
check "for any battery" test "$(page_key --group Face-94304568396688 --group Sensors highPrioritySensorIds)" = '["power/.*/chargeRate"]'
check "Plasma's translations kept" grep -q '^Title\[de\]=' "$OVERVIEW"

echo "== Power management"
POWER=/etc/xdg/powerdevilrc
power() { kreadconfig6 --file "$POWER" --group "$1" --group "$2" --key "$3"; }
check "no package ships $POWER, which the image's replaces whole" bash -c "! rpm -qf $POWER"
check "Bazzite's Plasma 5 power profiles, which powerdevil would copy into new profiles, are gone" test ! -e /etc/xdg/powermanagementprofilesrc
# profile, then sleep, dim and screen-off timeouts in seconds, lid action, power profile
while read -r profile sleep dim off lid ppd; do
	check "$profile: sleep when inactive" test "$(power "$profile" SuspendAndShutdown AutoSuspendAction)" = 1
	check "$profile: after $sleep s" test "$(power "$profile" SuspendAndShutdown AutoSuspendIdleTimeoutSec)" = "$sleep"
	check "$profile: the power button puts the machine to sleep" test "$(power "$profile" SuspendAndShutdown PowerButtonAction)" = 1
	check "$profile: closing the lid does action $lid" test "$(power "$profile" SuspendAndShutdown LidAction)" = "$lid"
	check "$profile: the screen dims" test "$(power "$profile" Display DimDisplayWhenIdle)" = true
	check "$profile: after $dim s" test "$(power "$profile" Display DimDisplayIdleTimeoutSec)" = "$dim"
	check "$profile: the screen turns off" test "$(power "$profile" Display TurnOffDisplayWhenIdle)" = true
	check "$profile: after $off s" test "$(power "$profile" Display TurnOffDisplayIdleTimeoutSec)" = "$off"
	check "$profile: whether locked or not" test "$(power "$profile" Display TurnOffDisplayIdleTimeoutWhenLockedSec)" = -2
	check "$profile: power profile $ppd" test "$(power "$profile" Performance PowerProfile)" = "$ppd"
done <<'EOF'
AC 1800 900 1800 0 performance
Battery 600 300 600 1 balanced
LowBattery 300 120 300 1 power-saver
EOF

echo "== Tailscale"
check "tailscaled enabled" systemctl is-enabled tailscaled.service

echo "== Flatpaks"
PREINSTALL=/usr/share/flatpak/preinstall.d/custom-apps.preinstall
check "flatpak preinstall accepts --system" bash -c 'flatpak preinstall --help | grep -q -- "--system"'
check "flatpak preinstall accepts -y" bash -c 'flatpak preinstall --help | grep -q -- "-y, --assumeyes"'
check "custom-flatpak-preinstall.service enabled" systemctl is-enabled custom-flatpak-preinstall.service
for app in md.obsidian.Obsidian com.spotify.Client com.obsproject.Studio com.discordapp.Discord rocks.shy.VacuumTube \
	org.jellyfin.JellyfinDesktop org.mozilla.firefox; do
	check "preinstall list has $app" grep -qx "\[Flatpak Preinstall $app\]" "$PREINSTALL"
done
check "Firefox comes from the beta branch" bash -c "grep -A1 -Fx '[Flatpak Preinstall org.mozilla.firefox]' '$PREINSTALL' | grep -qx 'Branch=beta'"

BETA_REMOTE=/etc/flatpak/remotes.d/flathub-beta.flatpakrepo
check "flathub-beta remote definition shipped" grep -qx 'Url=https://dl.flathub.org/beta-repo/' "$BETA_REMOTE"
# Same trust anchor as the Flathub remote the base already ships, not a key of this repo's choosing.
check "flathub-beta uses the Flathub signing key the base trusts" bash -c "k=\$(grep '^GPGKey=' '$BETA_REMOTE'); test -n \"\$k\" && test \"\$k\" = \"\$(grep '^GPGKey=' /etc/flatpak/remotes.d/flathub.flatpakrepo)\""
check "preinstall unit adds the flathub-beta remote before installing" grep -qx "ExecStartPre=/usr/bin/flatpak remote-add --system --if-not-exists flathub-beta $BETA_REMOTE" /usr/lib/systemd/system/custom-flatpak-preinstall.service
# flatpak silently skips a malformed drop-in ("Nothing to do."), so check the shape here: the group
# prefix is the one libflatpak parses, every section header is well-formed, and the line right
# after each header is the Branch line.
check "libflatpak parses the 'Flatpak Preinstall' group prefix" bash -c 'cat /usr/lib64/libflatpak.so.* | grep -a -q "Flatpak Preinstall"'
check "every preinstall section is well-formed" bash -c "test \"\$(grep -c '^\[' '$PREINSTALL')\" = \"\$(grep -c '^\[Flatpak Preinstall [A-Za-z0-9._-]*\]\$' '$PREINSTALL')\""
check "every preinstall section is followed by its Branch line" bash -c "test \"\$(grep -c '^\[' '$PREINSTALL')\" = \"\$(grep -A1 '^\[' '$PREINSTALL' | grep -cEx 'Branch=(stable|beta)')\""

echo "== Bazzite Portal selections: system"
check "cockpit.service enabled" systemctl is-enabled cockpit.service
check "base still ships the container cockpit.service starts" test -f /usr/share/containers/systemd/cockpit-container.container
# Cockpit is for the local machine only. firewalld accepts loopback traffic before it looks at any
# policy or zone, so rejecting the port for every zone leaves exactly that.
cockpit_policy() { firewall-offline-cmd --policy=cockpit-local-only "$@"; }
check "firewalld.service is enabled in the base" systemctl is-enabled firewalld.service
check "firewalld loads the cockpit-local-only policy" firewall-offline-cmd --info-policy=cockpit-local-only
check "it applies to traffic from every zone" cockpit_policy --query-ingress-zone=ANY
check "and only to traffic meant for this machine" cockpit_policy --query-egress-zone=HOST
check "it rejects Cockpit's port" cockpit_policy --query-rich-rule='rule port port="9090" protocol="tcp" reject'
check "it is consulted before the zones, which may allow the port" bash -c 'firewall-offline-cmd --info-policy=cockpit-local-only | grep -Eq "^ *priority: -[0-9]+$"'
check "base still runs Cockpit with no port of its own choosing, so on 9090" bash -c 'f=/usr/share/containers/systemd/cockpit-container.container; grep -qx "Exec=/container/label-run" "$f" && ! grep -q "^PublishPort=" "$f"'
check "fw-fanctrl.service enabled" systemctl is-enabled fw-fanctrl.service
check "CoolerControl is not in the image, so nothing competes with fw-fanctrl for the fan" bash -c '! rpm -q coolercontrol'
check "displaylink installed" rpm -q displaylink
check "the base has an evdi kernel module for displaylink to drive" bash -c 'find /usr/lib/modules -name "evdi.ko*" | grep -q .'
check "negativo17 is still disabled after installing from it" bash -c 'dnf5 repolist --disabled | grep -q "fedora-multimedia"'
check "adb comes with the base (the Portal's Android Platform Tools)" command -v adb
check "sudo shows asterisks while a password is typed" grep -qx 'Defaults pwfeedback' /etc/sudoers.d/enable-pwfeedback
check "the sudoers drop-in is root:root 440" test "$(mode_of /etc/sudoers.d/enable-pwfeedback)" = "440 root:root"
check "sudo accepts the drop-in" visudo -cf /etc/sudoers.d/enable-pwfeedback
check "libvirtd.service enabled" systemctl is-enabled libvirtd.service
check "bazzite-libvirtd-setup.service enabled" systemctl is-enabled bazzite-libvirtd-setup.service
check "kargs.d carries the recipe's KVM arguments" grep -qx 'kargs = \["kvm.ignore_msrs=1", "kvm.report_ignored_msrs=0"\]' /usr/lib/bootc/kargs.d/10-kvm-msrs.toml
check "the recipe still sets exactly those two" bash -c "test \"\$(grep -rhoE -- '--append-if-missing=\"?kvm\.[a-z_]+=[0-9]+' $JUST_DIR | sort -u | wc -l)\" = 2"
check "kargs.d carries the recipe's AMD HDMI 2.1 argument" grep -qx 'kargs = \["amdgpu.dcfeaturemask=0x402"\]' /usr/lib/bootc/kargs.d/20-amdgpu-hdmi21.toml
check "ujust configure-amd-hdmi21 still sets that argument" grep -rq -- '--append-if-missing=amdgpu.dcfeaturemask=0x402' "$JUST_DIR"
check "tmpfiles.d creates the swtpm CA directory" grep -qx 'd /var/lib/swtpm-localca 0750 tss root -' /usr/lib/tmpfiles.d/swtpm-localca.conf
check "its owner exists" getent passwd tss

echo "== Bazzite Portal selections: /var/home snapshots and deduplication"
SNAP_SETUP=/usr/libexec/custom-home-snapshots-setup
DEDUP_SETUP=/usr/libexec/custom-home-dedup-setup
for unit in custom-home-snapshots custom-home-dedup; do
	check "$unit.service enabled" systemctl is-enabled "$unit.service"
	check "$unit.service runs its setup script" grep -qx "ExecStart=/usr/libexec/$unit-setup" "/usr/lib/systemd/system/$unit.service"
	check "$unit.service gets the state directory the script needs" grep -qx "StateDirectory=$unit" "/usr/lib/systemd/system/$unit.service"
done
for tool in findmnt snapper beesd; do
	check "$tool is available in the base" command -v "$tool"
done
for timer in snapper-timeline.timer snapper-cleanup.timer beesd@.timer; do
	check "base still ships $timer" test -f "/usr/lib/systemd/system/$timer"
done
# The setups repeat what the base's own tooling does; notice when that changes under them.
check "Bazzite still keeps the /var/home config under snapper's default name" grep -q 'snapper create-config /var/home' /usr/libexec/bazzite-snapper-config
check "bees sample config has the three lines the setup rewrites" bash -c 'f=/etc/bees/beesd.conf.sample; grep -q "^UUID=" "$f" && grep -q "^# DB_SIZE=" "$f" && grep -q "^# OPTIONS=" "$f"'
check "Bazzite's beesd recipe still sizes the hash table the same way" bash -c "grep -rq 'readonly MIN_FS_TB=1\$' $JUST_DIR && grep -rq 'readonly MAX_FS_TB=4\$' $JUST_DIR && grep -rq 'readonly HASH_SIZE_MB_PER_TB=512\$' $JUST_DIR"
check "and still passes bees the same options" grep -rqF -- '--strip-paths --no-timestamps --thread-factor 0.125 --thread-min 1 --throttle-factor 100' "$JUST_DIR"
BEES_MEMORY_TEST="free -m | awk '/^Mem:/ {print \\\$7}') -gt \${mem_thresh_mb}"
check "and still holds bees back with the same memory test" grep -rqF -- "$BEES_MEMORY_TEST" "$JUST_DIR"
# Not override.conf: the per-filesystem override.conf the dedup setup writes masks the base's file of that name.
check "base still ends a bees run after 30 minutes, as the README says" grep -q 'timeout 30m /usr/bin/beesd' /etc/systemd/system/beesd@.service.d/bees-timeout.conf

echo "== Bazzite Portal selections: per user"
TWEAKS_HOOK=/usr/share/ublue-os/user-setup.hooks.d/35-portal-tweaks.sh
CASKS_SETUP=/usr/libexec/portal-brew-casks-setup
check "hook knows where the brew casks setup is" grep -Fq ":-$CASKS_SETUP}" "$TWEAKS_HOOK"
check "and starts it as a detached unit" grep -Fq -- '--unit=portal-brew-casks-setup "$CASKS_SETUP"' "$TWEAKS_HOOK"
check "base still ships the Steam icon cleanup user unit" test -f /usr/lib/systemd/user/steam-icons-cleanup.service
check "ujust global-fsr4-rdna3 still uses the same file and variable" bash -c "grep -rq '99-proton-fsr4-rdna3.conf' $JUST_DIR && grep -rq 'PROTON_FSR4_RDNA3_UPGRADE=1' $JUST_DIR"
for cask in jetbrains-toolbox-linux lm-studio-linux; do
	check "the Portal still installs $cask with the same brew steps" grep -Fq "brew trust ublue-os/tap && brew tap ublue-os/tap && brew install --cask $cask'" /usr/share/yafti/yafti.yml
	check "and the setup script installs it" grep -q "^CASKS=.*[( ]$cask:" "$CASKS_SETUP"
done
check "brew-setup.service, which unpacks Homebrew, is enabled in the base" systemctl is-enabled brew-setup.service
CRUNCHYROLL_HOOK=/usr/share/ublue-os/user-setup.hooks.d/45-crunchyroll.sh
for script in "$SNAP_SETUP" "$DEDUP_SETUP" "$TWEAKS_HOOK" "$CASKS_SETUP" "$CRUNCHYROLL_HOOK"; do
	check "$script is executable" test -x "$script"
	check "$script parses" bash -n "$script"
done

echo "== Claude Desktop distrobox"
APPS_INI=/etc/distrobox/apps.ini
CLAUDE_INI=/usr/share/claude-distrobox/claude.ini
CLAUDE_INIT=/usr/libexec/claude-distrobox-init
CLAUDE_SETUP=/usr/libexec/claude-distrobox-setup
CLAUDE_HOOK=/usr/share/ublue-os/user-setup.hooks.d/40-claude-distrobox.sh
check "distrobox is available in the base" command -v distrobox
check "systemd-run is available for the detached setup" command -v systemd-run
check "base still offers ujust setup-distrobox-app" grep -rq "setup-distrobox-app" /usr/share/ublue-os/just/
in_manifest() { grep -Fx -- "$1" "$CLAUDE_INI"; }
check "manifest defines the ubuntu box" in_manifest '[ubuntu]'
check "the box uses the ublue Ubuntu toolbox image" in_manifest 'image=ghcr.io/ublue-os/ubuntu-toolbox:latest'
check "the box runs the Claude install script from the host image" in_manifest "init_hooks=\"/run/host$CLAUDE_INIT\""
check "the box exports Claude Desktop to the menu" in_manifest 'exported_apps="claude-desktop"'
check "setup reads that manifest" grep -Fqx "MANIFEST=$CLAUDE_INI" "$CLAUDE_SETUP"
# assemble exits 0 without creating anything when the manifest has no section of that name.
check "setup asks for the box the manifest defines" grep -Fqx 'BOX=ubuntu' "$CLAUDE_SETUP"
check "hook launches the setup script" grep -Fq " $CLAUDE_SETUP" "$CLAUDE_HOOK"
check "apps.ini ends with the same manifest, for ujust setup-distrobox-app ubuntu" bash -c "tail -n \"\$(wc -l <'$CLAUDE_INI')\" '$APPS_INI' | cmp -s - '$CLAUDE_INI'"
check "apps.ini has exactly one [ubuntu] section" test "$(grep -cFx '[ubuntu]' "$APPS_INI")" = 1
check "the appended section did not replace the base's entries" bash -c "test \"\$(grep -c '^\[' '$APPS_INI')\" -gt 1"
for script in "$CLAUDE_INIT" "$CLAUDE_SETUP" "$CLAUDE_HOOK"; do
	check "$script is executable" test -x "$script"
	check "$script parses" bash -n "$script"
done

echo "== Forge CLIs"
check "gh package installed" rpm -q gh
check "gh runs" gh --version
check "tea installed" test -x /usr/bin/tea
check "tea runs and reports a version" bash -c 'tea --version | grep -Eq "[0-9]+\.[0-9]+\.[0-9]+"'

echo "== dnf bookkeeping"
check "no dnf usage counter or repo state under /var/lib/dnf" test ! -e /var/lib/dnf
check "no dnf install history" bash -c '! ls /usr/lib/sysimage/libdnf5/transaction_history.sqlite* 2>/dev/null'
check "dnf's package state is still there" test -f /usr/lib/sysimage/libdnf5/packages.toml

if ((fails > 0)); then
	echo "$fails check(s) failed"
	exit 1
fi
echo "all checks passed"
