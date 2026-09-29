#!/usr/bin/bash
# Exercises build_files/75-tmog-task-manager.sh, which installs Task Manager TMOG from its tar.gz at
# image build time, with a stub curl serving a fake tarball and a redirected install prefix.
# sha256sum, tar and gtk-update-icon-cache are the real ones.
# Run inside a container with the repo mounted at /src:
#   podman run --rm -v "$PWD:/src:ro,Z" <image> /src/tests/test-tmog-task-manager.sh
set -uo pipefail

SRC="${SRC:-/src}"
STEP="$SRC/build_files/75-tmog-task-manager.sh"
VERSION="$(sed -n 's/^TMOG_VERSION=//p' "$STEP")"
NAME="TaskManagerOG-${VERSION}-linux-x86_64"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
PREFIX="$tmp/prefix"
ICON_SIZES="32x32 48x48 64x64 128x128 256x256 512x512"

# The release's layout (1.0.0): the task manager, an XScreenSaver engine with its registration
# script, their menu entries, icons, AppStream metadata and licence notices, owned by uid 1000.
# make_tarball [path to leave out]
make_tarball() {
	local root="$tmp/tree/$NAME" size
	rm -rf "$tmp/tree"
	mkdir -p "$root"/{bin,libexec/xscreensaver,share/applications/screensavers,share/doc/tmog,share/doc/taskmanagerog,share/metainfo,share/pixmaps,share/xscreensaver/config}
	printf '#!/usr/bin/bash\n# TMOG-BINARY\n' >"$root/bin/tmog-task-manager"
	printf '#!/usr/bin/bash\n' | tee "$root/bin/tmog-screensaver" "$root/bin/tmog-register-screensaver" "$root/libexec/xscreensaver/tmog-screensaver" >/dev/null
	chmod 0755 "$root"/bin/* "$root/libexec/xscreensaver/tmog-screensaver"
	printf '[Desktop Entry]\nExec=tmog-task-manager\n' >"$root/share/applications/com.tmog.taskmanager.desktop"
	printf '[Desktop Entry]\n' | tee "$root/share/applications/tmog-register-screensaver.desktop" "$root/share/applications/screensavers/tmog-screensaver.desktop" >/dev/null
	echo licence | tee "$root/share/doc/tmog/LICENSE.txt" "$root/share/doc/tmog/THIRD_PARTY_NOTICES.md" "$root/share/doc/taskmanagerog/copyright" >/dev/null
	echo '<component/>' >"$root/share/metainfo/com.tmog.taskmanager.metainfo.xml"
	echo png >"$root/share/pixmaps/tmog-task-manager.png"
	echo '<screensaver/>' >"$root/share/xscreensaver/config/tmog-screensaver.xml"
	for size in $ICON_SIZES; do
		mkdir -p "$root/share/icons/hicolor/$size/apps"
		echo "png $size" >"$root/share/icons/hicolor/$size/apps/tmog-task-manager.png"
	done
	[[ -n "${1:-}" ]] && rm -rf "${root:?}/$1"
	tar -czf "$tmp/tarball.tar.gz" --owner=1000 --group=1000 -C "$tmp/tree" "$NAME"
}

# DOWNLOAD_FAIL=1 fails the download.
cat >"$tmp/bin/curl" <<'EOF'
#!/usr/bin/bash
out=""; url=""
while [[ $# -gt 0 ]]; do
	case "$1" in
	-o) out="$2"; shift ;;
	http*) url="$1" ;;
	esac
	shift
done
echo "$url" >>"$CALLS"
[[ -n "${DOWNLOAD_FAIL:-}" ]] && exit 22
cp "$TARBALL" "$out"
EOF
chmod +x "$tmp/bin/curl"

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
tarball_sha() { sha256sum "$tmp/tarball.tar.gz" | cut -d' ' -f1; }
run_step() { # run_step [VAR=value ...]
	env PATH="$tmp/bin:$PATH" CALLS="$tmp/calls.log" TARBALL="$tmp/tarball.tar.gz" TMOG_PREFIX="$PREFIX" \
		TMOG_SHA256="$(tarball_sha)" "$@" bash "$STEP"
}
step_fails() { ! run_step "$@"; }
reset() {
	rm -rf "$PREFIX"
	mkdir -p "$PREFIX"
	: >"$tmp/calls.log"
}
nothing_installed() { test -z "$(ls -A "$PREFIX")"; }

echo "== the pinned release"
check "the step pins a version" test -n "$VERSION"
check "and a SHA-256" grep -Eq '^TMOG_SHA256="\$\{TMOG_SHA256:-[0-9a-f]{64}\}"$' "$STEP"
make_tarball
reset
check "step exits 0" run_step
check "the tar.gz of that version is fetched from tmog.org" grep -qx "https://tmog.org/rtm/downloads/${NAME}.tar.gz" "$tmp/calls.log"
check "and nothing else" test "$(wc -l <"$tmp/calls.log")" = 1
check "the task manager is installed" grep -qx '# TMOG-BINARY' "$PREFIX/bin/tmog-task-manager"
check "and executable" test -x "$PREFIX/bin/tmog-task-manager"
check "owned by the build's user, not the archive's uid 1000" test "$(stat -c %u "$PREFIX/bin/tmog-task-manager")" = "$(id -u)"
for size in $ICON_SIZES; do
	check "its $size icon is installed" grep -qx "png $size" "$PREFIX/share/icons/hicolor/$size/apps/tmog-task-manager.png"
done
check "the icon cache lists the icon" grep -aq tmog-task-manager "$PREFIX/share/icons/hicolor/icon-theme.cache"
check "its AppStream metadata is installed" test -f "$PREFIX/share/metainfo/com.tmog.taskmanager.metainfo.xml"
check "its licence is installed" test -f "$PREFIX/share/doc/tmog/LICENSE.txt"
check "and the third-party notices" test -f "$PREFIX/share/doc/tmog/THIRD_PARTY_NOTICES.md"
check "kglobalacceld gets the image's menu entry, for Ctrl+Shift+Esc" \
	test "$(readlink "$PREFIX/share/kglobalaccel/com.tmog.taskmanager.desktop")" = /usr/share/applications/com.tmog.taskmanager.desktop
check "the tarball's menu entries are not installed (the image ships its own)" test ! -e "$PREFIX/share/applications"
check "nor the XScreenSaver engine" test ! -e "$PREFIX/bin/tmog-screensaver"
check "nor its registration script" test ! -e "$PREFIX/bin/tmog-register-screensaver"
check "nor its XScreenSaver files" bash -c "test ! -e '$PREFIX/libexec' && test ! -e '$PREFIX/share/xscreensaver'"
check "a second run succeeds" run_step

echo "== the download does not match the pinned SHA-256"
make_tarball
reset
check "step fails" step_fails TMOG_SHA256=0000000000000000000000000000000000000000000000000000000000000000
check "nothing installed" nothing_installed

echo "== the download fails"
reset
check "step fails" step_fails DOWNLOAD_FAIL=1
check "nothing installed" nothing_installed

echo "== the tarball no longer has the task manager where it was"
make_tarball bin/tmog-task-manager
reset
check "step fails" step_fails

if ((fails > 0)); then
	echo "$fails check(s) failed"
	exit 1
fi
echo "all checks passed"
