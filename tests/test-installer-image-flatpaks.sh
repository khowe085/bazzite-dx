#!/usr/bin/bash
# Exercises installer/install-image-flatpaks.sh with stub flatpak and mount.
# Run inside a container with the repo mounted at /src:
#   podman run --rm -v "$PWD:/src:ro,Z" <image> /src/tests/test-installer-image-flatpaks.sh
set -uo pipefail

SRC="${SRC:-/src}"
SCRIPT="$SRC/installer/install-image-flatpaks.sh"

fail=0
pass() { echo "PASS: $1"; }
failc() { echo "FAIL: $1"; fail=1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
log="$tmp/calls"

# flatpak records its arguments and, for preinstall, which lists it could see then.
cat >"$tmp/bin/flatpak" <<EOF
#!/usr/bin/bash
echo "flatpak \$*" >>"$log"
if [[ \$* == *preinstall* ]]; then
    for f in "$tmp/preinstall.d"/*.preinstall; do
        [[ -e \$f ]] && echo "visible \$(basename "\$f")" >>"$log"
    done
fi
exit "\${FLATPAK_EXIT:-0}"
EOF
cat >"$tmp/bin/mount" <<EOF
#!/usr/bin/bash
echo "mount \$*" >>"$log"
EOF
chmod +x "$tmp/bin/"*

run() { rm -rf "$tmp/preinstall.d"; PATH="$tmp/bin:$PATH" IMAGE_FILES="$1" PREINSTALL_DIR="$tmp/preinstall.d" bash "$SCRIPT" >"$tmp/out" 2>&1; }

# --- The repository's own system_files ---
: >"$log"
if run "$SRC/system_files"; then pass "succeeds with the repository's system_files"; else failc "fails with the repository's system_files: $(cat "$tmp/out")"; fi
grep -qx "mount -o remount,rw /proc/sys" "$log" && pass "makes /proc/sys writable for bwrap" || failc "does not remount /proc/sys"
grep -qx "flatpak remote-add --system --if-not-exists flathub-beta $SRC/system_files/etc/flatpak/remotes.d/flathub-beta.flatpakrepo" "$log" \
    && pass "adds flathub-beta from the image's remote file" || failc "flathub-beta not added as expected: $(cat "$log")"
grep -qx "flatpak preinstall --system -y --noninteractive" "$log" && pass "runs flatpak preinstall non-interactively" || failc "no non-interactive preinstall"
[[ $(grep -n 'remote-add' "$log" | cut -d: -f1) -lt $(grep -n ' preinstall ' "$log" | cut -d: -f1) ]] \
    && pass "adds the beta remote before preinstalling" || failc "preinstall runs before the beta remote exists"
for f in "$SRC"/system_files/usr/share/flatpak/preinstall.d/*.preinstall; do
    grep -qx "visible $(basename "$f")" "$log" && pass "preinstall sees $(basename "$f")" || failc "preinstall did not see $(basename "$f")"
done

# --- A failing install fails the build ---
: >"$log"
if FLATPAK_EXIT=1 run "$SRC/system_files"; then failc "succeeds although flatpak failed"; else pass "fails when flatpak fails"; fi

# --- No lists at all is a mistake, not an empty install ---
mkdir -p "$tmp/empty/etc/flatpak/remotes.d"
cp "$SRC/system_files/etc/flatpak/remotes.d/flathub-beta.flatpakrepo" "$tmp/empty/etc/flatpak/remotes.d/"
: >"$log"
if run "$tmp/empty"; then failc "succeeds with no preinstall files"; else pass "fails with no preinstall files"; fi
grep -q ' preinstall ' "$log" && failc "ran preinstall with no lists" || pass "does not run preinstall with no lists"

# --- IMAGE_FILES is required ---
check_default() { grep -qF 'PREINSTALL_DIR="${PREINSTALL_DIR:-/usr/share/flatpak/preinstall.d}"' "$SCRIPT"; }
check_default && pass "installs into flatpak's own preinstall.d by default" || failc "default preinstall.d is not flatpak's"
if PATH="$tmp/bin:$PATH" PREINSTALL_DIR="$tmp/preinstall.d" bash "$SCRIPT" >/dev/null 2>&1; then failc "runs without IMAGE_FILES"; else pass "requires IMAGE_FILES"; fi

exit "$fail"
