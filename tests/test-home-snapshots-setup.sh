#!/usr/bin/bash
# Exercises system_files/usr/libexec/custom-home-snapshots-setup, the one-time Snapper setup for
# /var/home, with stub findmnt, snapper and systemctl.
# Run inside a container with the repo mounted at /src:
#   podman run --rm -v "$PWD:/src:ro,Z" <image> /src/tests/test-home-snapshots-setup.sh
set -uo pipefail

SRC="${SRC:-/src}"
SETUP="$SRC/system_files/usr/libexec/custom-home-snapshots-setup"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

# findmnt answers with FAKE_FSTYPE (default btrfs); FINDMNT_FAIL=1 makes it fail.
cat >"$tmp/bin/findmnt" <<'EOF'
#!/usr/bin/bash
echo "findmnt $*" >>"$CALLS"
[[ -n "${FINDMNT_FAIL:-}" ]] && exit 1
echo "${FAKE_FSTYPE:-btrfs}"
EOF
# snapper knows one thing: whether the "root" config exists ($STATE/config). SNAPPER_FAIL names the
# subcommand that fails. Anything not aimed at the "root" config is a usage error.
cat >"$tmp/bin/snapper" <<'EOF'
#!/usr/bin/bash
echo "snapper $*" >>"$CALLS"
[[ "$1 $2" == "-c root" ]] || exit 64
case "$3" in
get-config) [[ -e "$STATE/config" ]] || exit 1 ;;
create-config)
	[[ "${SNAPPER_FAIL:-}" == create-config ]] && exit 1
	touch "$STATE/config"
	;;
set-config) [[ "${SNAPPER_FAIL:-}" == set-config ]] && exit 1 ;;
esac
exit 0
EOF
cat >"$tmp/bin/systemctl" <<'EOF'
#!/usr/bin/bash
echo "systemctl $*" >>"$CALLS"
[[ -n "${SYSTEMCTL_FAIL:-}" ]] && exit 1
exit 0
EOF
chmod +x "$tmp/bin/"*

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
# systemd creates the unit's StateDirectory before the script starts; reset() stands in for that.
run_setup() { # run_setup [VAR=value ...]
	env PATH="$tmp/bin:$PATH" CALLS="$tmp/calls.log" STATE="$tmp" STATE_DIRECTORY="$tmp/state" "$@" bash "$SETUP"
}
setup_fails() { ! run_setup "$@"; }
reset() {
	rm -rf "$tmp/state" "$tmp/config"
	mkdir -p "$tmp/state"
	: >"$tmp/calls.log"
}
called() { grep -q -- "$1" "$tmp/calls.log"; }
never_called() { ! called "$1"; }
line_of() { grep -n -m1 -- "$1" "$tmp/calls.log" | cut -d: -f1; }
in_order() { # in_order <pattern> <pattern>: the first shows up in the call log before the second
	local a b
	a="$(line_of "$1")"
	b="$(line_of "$2")"
	[[ -n "$a" && -n "$b" ]] && ((a < b))
}
set_config_has() { grep '^snapper -c root set-config ' "$tmp/calls.log" | grep -qw -- "$1"; }
# --no-block: this runs inside a boot-time unit, which must not sit waiting on another unit's start job.
enables_now() { grep '^systemctl enable --now --no-block ' "$tmp/calls.log" | grep -qw -- "$1"; }
stamp="$tmp/state/done"
creating="$tmp/state/creating"

echo "== first boot on btrfs, no snapper config yet"
reset
check "setup exits 0" run_setup
check "asks what /var/home is mounted from" called '^findmnt .*--target /var/home'
check "creates the config Bazzite's tooling expects: named root, covering /var/home" called '^snapper -c root create-config /var/home$'
check "settings are applied after the config exists" in_order ' create-config ' ' set-config '
# 5 hourly and 7 daily timeline snapshots, 10 under number cleanup; every other timeline limit off.
for pair in TIMELINE_CREATE=yes TIMELINE_CLEANUP=yes TIMELINE_MIN_AGE=1800 \
	TIMELINE_LIMIT_HOURLY=5 TIMELINE_LIMIT_DAILY=7 TIMELINE_LIMIT_WEEKLY=0 TIMELINE_LIMIT_MONTHLY=0 \
	TIMELINE_LIMIT_QUARTERLY=0 TIMELINE_LIMIT_YEARLY=0 \
	NUMBER_CLEANUP=yes NUMBER_MIN_AGE=1800 NUMBER_LIMIT=10 NUMBER_LIMIT_IMPORTANT=10; do
	check "retention: $pair" set_config_has "$pair"
done
check "timeline timer enabled and started" enables_now snapper-timeline.timer
check "cleanup timer enabled and started" enables_now snapper-cleanup.timer
check "timers come after the settings, so the first snapshot already obeys them" in_order ' set-config ' '^systemctl enable --now '
check "boot snapshots stay off" never_called 'snapper-boot.timer'
check "stamped" test -e "$stamp"
check "the in-progress marker is gone" test ! -e "$creating"

echo "== later boots"
: >"$tmp/calls.log"
check "setup exits 0" run_setup
check "nothing is queried or changed once stamped" test ! -s "$tmp/calls.log"

echo "== snapshots switched off later (ujust configure-snapshots wipe deletes the config)"
rm -f "$tmp/config"
: >"$tmp/calls.log"
check "setup exits 0" run_setup
check "the config is not brought back" never_called ' create-config '

echo "== /var/home is not on btrfs"
reset
check "setup exits 0" run_setup FAKE_FSTYPE=ext4
check "snapper is left out of it" never_called '^snapper '
check "no timers are enabled" never_called '^systemctl '
check "not stamped" test ! -e "$stamp"

echo "== the mount cannot be inspected"
reset
check "setup fails" setup_fails FINDMNT_FAIL=1
check "not stamped" test ! -e "$stamp"

echo "== a snapper config already exists (set up through the Portal or by hand)"
reset
touch "$tmp/config"
check "setup exits 0" run_setup
check "it is not recreated" never_called ' create-config '
check "its settings are not touched" never_called ' set-config '
check "its timers are not touched" never_called '^systemctl '
check "stamped so later boots skip the check" test -e "$stamp"

echo "== creating the config fails (/var/home is not a subvolume, snapperd not reachable)"
reset
check "setup fails" setup_fails SNAPPER_FAIL=create-config
check "not stamped, so the next boot tries again" test ! -e "$stamp"
check "no timers enabled for a config that is not there" never_called '^systemctl '
: >"$tmp/calls.log"
check "next boot: setup exits 0" run_setup
check "the config is created then" called '^snapper -c root create-config /var/home$'
check "stamped" test -e "$stamp"

echo "== creating the config fails, and the user sets snapshots up in the Portal before the next boot"
reset
check "setup fails" setup_fails SNAPPER_FAIL=create-config
check "a create that failed leaves no in-progress marker" test ! -e "$creating"
touch "$tmp/config"
: >"$tmp/calls.log"
check "next boot: setup exits 0" run_setup
check "their config is not taken for ours: its settings are not touched" never_called ' set-config '
check "nor are its timers" never_called '^systemctl '
check "stamped" test -e "$stamp"

echo "== the config is created but applying the settings fails"
reset
check "setup fails" setup_fails SNAPPER_FAIL=set-config
check "not stamped" test ! -e "$stamp"
check "timers are not started on snapper's default retention" never_called '^systemctl '
check "the in-progress marker stays, so the next boot knows the config is ours" test -e "$creating"
: >"$tmp/calls.log"
echo "== next boot: our half-made config is finished, not mistaken for the user's"
check "setup exits 0" run_setup
check "no second create-config" never_called ' create-config '
check "the retention is applied" set_config_has TIMELINE_LIMIT_DAILY=7
check "the timers are enabled" enables_now snapper-timeline.timer
check "stamped" test -e "$stamp"
check "the in-progress marker is gone" test ! -e "$creating"

echo "== enabling the timers fails"
reset
check "setup fails" setup_fails SYSTEMCTL_FAIL=1
check "not stamped" test ! -e "$stamp"
: >"$tmp/calls.log"
check "next boot: setup exits 0" run_setup
check "the timers are enabled then" enables_now snapper-cleanup.timer
check "stamped" test -e "$stamp"

if ((fails > 0)); then
	echo "$fails check(s) failed"
	exit 1
fi
echo "all checks passed"
