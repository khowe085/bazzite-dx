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
POTD_SCRIPT="$UPDATES_DIR/picture-of-the-day-wallpaper.js"
check "Fedora Dark is the default global theme" grep -qx "LookAndFeelPackage=$LNF" /etc/xdg/kdeglobals
check "kdeglobals names one global theme only" test "$(grep -c '^LookAndFeelPackage=' /etc/xdg/kdeglobals)" = 1
check "the base ships that theme" test -f "/usr/share/plasma/look-and-feel/$LNF/metadata.json"
check "the rest of Bazzite's kdeglobals is still there" grep -qx 'kcm_updates=false' /etc/xdg/kdeglobals
check "wallpaper update script shipped" test -f "$POTD_SCRIPT"
check "in the directory the base uses for its own Plasma update script" test -f "$UPDATES_DIR/bazzite-pins.js"
check "the script selects the Picture of the Day wallpaper" grep -q 'wallpaperPlugin = "org.kde.potd"' "$POTD_SCRIPT"
check "with the Astronomy (NASA) provider" grep -q 'writeConfig("Provider", "apod")' "$POTD_SCRIPT"
check "the base ships that wallpaper type" test -f /usr/share/plasma/wallpapers/org.kde.potd/metadata.json
check "and that provider" test -f /usr/lib64/qt6/plugins/potd/plasma_potd_apodprovider.so
# Read back with KDE's own parser: KWin's Touchpad group covers touchpads, Pointer the other pointing devices.
for type in Touchpad Pointer; do
	check "natural scrolling is the default for $type devices" test "$(kreadconfig6 --file /etc/xdg/kcminputrc --group Libinput --group Defaults --group "$type" --key NaturalScroll)" = true
done

echo "== Tailscale"
check "tailscaled enabled" systemctl is-enabled tailscaled.service

echo "== Flatpaks"
PREINSTALL=/usr/share/flatpak/preinstall.d/custom-apps.preinstall
check "flatpak preinstall accepts --system" bash -c 'flatpak preinstall --help | grep -q -- "--system"'
check "flatpak preinstall accepts -y" bash -c 'flatpak preinstall --help | grep -q -- "-y, --assumeyes"'
check "custom-flatpak-preinstall.service enabled" systemctl is-enabled custom-flatpak-preinstall.service
for app in md.obsidian.Obsidian com.spotify.Client com.obsproject.Studio com.discordapp.Discord org.mozilla.firefox; do
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
check "manifest defines the claude box" in_manifest '[claude]'
check "claude box uses the ublue Ubuntu toolbox image" in_manifest 'image=ghcr.io/ublue-os/ubuntu-toolbox:latest'
check "claude box runs the install script from the host image" in_manifest "init_hooks=\"/run/host$CLAUDE_INIT\""
check "claude box exports the app to the menu" in_manifest 'exported_apps="claude-desktop"'
check "setup reads that manifest" grep -Fqx "MANIFEST=$CLAUDE_INI" "$CLAUDE_SETUP"
check "hook launches the setup script" grep -Fq " $CLAUDE_SETUP" "$CLAUDE_HOOK"
check "apps.ini ends with the same manifest, for ujust setup-distrobox-app claude" bash -c "tail -n \"\$(wc -l <'$CLAUDE_INI')\" '$APPS_INI' | cmp -s - '$CLAUDE_INI'"
check "apps.ini has exactly one [claude] section" test "$(grep -cFx '[claude]' "$APPS_INI")" = 1
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

if ((fails > 0)); then
	echo "$fails check(s) failed"
	exit 1
fi
echo "all checks passed"
