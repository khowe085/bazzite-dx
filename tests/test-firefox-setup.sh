#!/usr/bin/bash
# Exercises system_files/usr/libexec/onepassword-firefox-flatpak-setup with a stub flatpak.
# Run inside a container with the repo mounted at /src:
#   podman run --rm -v "$PWD:/src:ro,Z" <image> /src/tests/test-firefox-setup.sh
set -uo pipefail

SRC="${SRC:-/src}"
SETUP="$SRC/system_files/usr/libexec/onepassword-firefox-flatpak-setup"
PREF="$SRC/system_files/usr/share/ublue-os/firefox-config/zz-onepassword-native-messaging.js"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/config"
cp "$PREF" "$tmp/config/"
echo '// stand-in for the prefs Bazzite ships in the same directory' >"$tmp/config/01-bazzite-global.js"
cat >"$tmp/bin/flatpak" <<EOF
#!/usr/bin/bash
[[ "\$1" == "--default-arch" ]] && { echo aarch64; exit 0; }
echo "\$*" >>"$tmp/flatpak.log"
EOF
chmod +x "$tmp/bin/flatpak"

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
run_setup() {
	PATH="$tmp/bin:$PATH" ONEPASSWORD_FIREFOX_EXT_ROOT="$tmp/ext" ONEPASSWORD_FIREFOX_CONFIG_DIR="$tmp/config" bash "$SETUP"
}

check "setup script exits 0" run_setup
# The stub reports aarch64, so a hardcoded x86_64 path would fail these.
for branch in stable beta; do
	dir="$tmp/ext/org.mozilla.firefox.systemconfig/aarch64/$branch/defaults/pref"
	check "$branch: 1Password pref file placed under the arch flatpak reports" cmp -s "$PREF" "$dir/zz-onepassword-native-messaging.js"
	check "$branch: Bazzite's own pref files are carried along" test -f "$dir/01-bazzite-global.js"
	check "$branch: pref files are 0644" test "$(stat -c %a "$dir/zz-onepassword-native-messaging.js")" = 644
done
check "shipped pref file enables the native-messaging proxy" grep -qx 'pref("widget.use-xdg-desktop-portal.native-messaging-proxy", 1);' "$PREF"
check "Firefox flatpak is granted talk access to the proxy" grep -qx 'override --system --talk-name=org.freedesktop.NativeMessagingProxy org.mozilla.firefox' "$tmp/flatpak.log"

check "second run exits 0 (idempotent)" run_setup
check "second run still leaves one pref file per branch" test "$(find "$tmp/ext" -name 'zz-onepassword-native-messaging.js' | wc -l)" = 2
check "override is re-applied on every run" test "$(grep -c '^override' "$tmp/flatpak.log")" = 2

if ((fails > 0)); then
	echo "$fails check(s) failed"
	exit 1
fi
echo "all checks passed"
