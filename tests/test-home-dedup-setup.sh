#!/usr/bin/bash
# Exercises system_files/usr/libexec/custom-home-dedup-setup, the one-time beesd setup for the
# filesystem behind /var/home, with stub findmnt and systemctl and a scratch root directory.
# Run inside a container with the repo mounted at /src:
#   podman run --rm -v "$PWD:/src:ro,Z" <image> /src/tests/test-home-dedup-setup.sh
set -uo pipefail

SRC="${SRC:-/src}"
SETUP="$SRC/system_files/usr/libexec/custom-home-dedup-setup"
UUID=1b3c2f8e-5a7d-4c11-9e0a-6f2d8b4c7a91

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

# findmnt answers one column per call: FAKE_FSTYPE, FAKE_UUID or FAKE_SIZE (set but empty = an empty
# answer). FINDMNT_FAIL=1 makes it fail.
cat >"$tmp/bin/findmnt" <<'EOF'
#!/usr/bin/bash
echo "findmnt $*" >>"$CALLS"
[[ -n "${FINDMNT_FAIL:-}" ]] && exit 1
case "$*" in
*FSTYPE*) echo "${FAKE_FSTYPE-btrfs}" ;;
*UUID*) echo "${FAKE_UUID-$DEFAULT_UUID}" ;;
*SIZE*) echo "${FAKE_SIZE-1000204886016}" ;;
esac
EOF
# SYSTEMCTL_FAIL names the verb that fails.
cat >"$tmp/bin/systemctl" <<'EOF'
#!/usr/bin/bash
echo "systemctl $*" >>"$CALLS"
[[ "${SYSTEMCTL_FAIL:-}" == "$1" ]] && exit 1
exit 0
EOF
chmod +x "$tmp/bin/"*

# The lines of bees' beesd.conf.sample that matter here, in its layout.
write_sample() { # write_sample <directory>
	mkdir -p "$1"
	cat >"$1/beesd.conf.sample" <<'EOF'
## Config for Bees: /etc/bees/beesd.conf.sample
# Which FS will be used
UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

## System Vars
# WORK_DIR=/run/bees/

## Options to apply, see `beesd --help` for details
# OPTIONS="--strip-paths --no-timestamps"

# Size MUST be multiple of 128KB
# DB_SIZE=$((1024*1024*1024)) # 1G in bytes
EOF
}

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
# $tmp/root stands in for /. systemd creates the unit's StateDirectory before the script starts;
# reset() stands in for that, and lays the sample out as on a deployed system: under /usr/etc,
# ostree's pristine copy of the image's /etc.
run_setup() { # run_setup [VAR=value ...]
	env PATH="$tmp/bin:$PATH" CALLS="$tmp/calls.log" STATE_DIRECTORY="$tmp/state" \
		DEFAULT_UUID="$UUID" HOME_DEDUP_ROOT="$tmp/root" "$@" bash "$SETUP"
}
setup_fails() { ! run_setup "$@"; }
reset() {
	rm -rf "$tmp/state" "$tmp/root"
	mkdir -p "$tmp/state"
	write_sample "$tmp/root/usr/etc/bees"
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
conf="$tmp/root/etc/bees/$UUID.conf"
dropin="$tmp/root/etc/systemd/system/beesd@$UUID.service.d/override.conf"
stamp="$tmp/state/done"
creating="$tmp/state/creating"
OPTIONS_LINE='OPTIONS="--strip-paths --no-timestamps --thread-factor 0.125 --thread-min 1 --throttle-factor 100"'
ENABLE="^systemctl enable --now --no-block beesd@$UUID.timer\$"
# What Bazzite's recipe writes: bees only starts while more memory is available than its hash table takes.
exec_condition() { printf 'ExecCondition=/bin/sh -c "test $(free -m | awk \x27/^Mem:/ {print $7}\x27) -gt %s"' "$1"; }

echo "== first boot, /var/home on a 1 TB btrfs filesystem"
reset
check "setup exits 0" run_setup
check "asks which filesystem holds /var/home" called '^findmnt -no UUID --target /var/home$'
check "asks for its size in bytes, not rounded for people" called '^findmnt -bno SIZE --target /var/home$'
check "bees config is named after the filesystem UUID" test -f "$conf"
check "config names the filesystem" grep -qx "UUID=$UUID" "$conf"
check "the sample's placeholder UUID is gone" bash -c "! grep -q 'UUID=xxxxxxxx' '$conf'"
check "hash table is 512 MiB per TB" grep -qx 'DB_SIZE=536870912' "$conf"
check "bees runs with Bazzite's load options" grep -Fqx "$OPTIONS_LINE" "$conf"
check "the rest of the sample is kept" grep -qx '# WORK_DIR=/run/bees/' "$conf"
check "drop-in is a [Service] section" test "$(head -n1 "$dropin")" = "[Service]"
check "drop-in holds bees back unless 512 MB are available" grep -Fqx "$(exec_condition 512)" "$dropin"
check "drop-in has nothing else" test "$(wc -l <"$dropin")" = 2
check "systemd rereads its units before the timer is enabled" in_order '^systemctl daemon-reload$' '^systemctl enable '
# --no-block: this runs inside a boot-time unit, which must not sit waiting on another unit's start job.
check "the daily timer for this filesystem is enabled and started, without waiting for it" called "$ENABLE"
check "stamped" test -e "$stamp"
check "the in-progress marker is gone" test ! -e "$creating"

echo "== later boots"
: >"$tmp/calls.log"
check "setup exits 0" run_setup
check "nothing is queried or changed once stamped" test ! -s "$tmp/calls.log"

echo "== deduplication removed later (ujust configure-beesd deletes the config)"
rm -rf "$conf" "$(dirname "$dropin")"
check "setup exits 0" run_setup
check "the config is not brought back" test ! -e "$conf"

echo "== no /usr/etc (the image run as a plain container): the sample is read from /etc"
reset
rm -rf "$tmp/root/usr"
write_sample "$tmp/root/etc/bees"
check "setup exits 0" run_setup
check "the config is complete" grep -qx 'DB_SIZE=536870912' "$conf"
check "stamped" test -e "$stamp"

echo "== the bees sample is nowhere to be found"
reset
rm -rf "$tmp/root/usr"
check "setup fails" setup_fails
check "no half-written config is enabled" never_called '^systemctl enable '
check "no empty config is left for ujust configure-beesd to find" test ! -e "$conf"
check "a setup that wrote nothing leaves no in-progress marker" test ! -e "$creating"
check "not stamped" test ! -e "$stamp"
echo "== ... and the user sets deduplication up with ujust before the next boot"
write_sample "$tmp/root/usr/etc/bees"
mkdir -p "$(dirname "$conf")"
echo "UUID=$UUID # mine" >"$conf"
: >"$tmp/calls.log"
check "next boot: setup exits 0" run_setup
check "their config is not taken for ours" test "$(cat "$conf")" = "UUID=$UUID # mine"
check "systemd is left alone" never_called '^systemctl '
check "stamped" test -e "$stamp"

echo "== hash table sizing follows Bazzite's recipe: round to the nearest TB, keep within 1 to 4 TB"
while read -r label bytes db_size thresh; do
	reset
	check "$label: setup exits 0" run_setup FAKE_SIZE="$bytes"
	check "$label: DB_SIZE=$db_size" grep -qx "DB_SIZE=$db_size" "$conf"
	check "$label: bees waits for $thresh MB of available memory" grep -Fqx "$(exec_condition "$thresh")" "$dropin"
done <<'EOF'
100GB 107374182400 536870912 512
1.4TB 1400000000000 536870912 512
1.5TB 1500301910016 1073741824 1024
2TB 2000398934016 1073741824 1024
4TB 4000787030016 2147483648 2048
8TB 8001563222016 2147483648 2048
EOF

echo "== /var/home is not on btrfs"
reset
check "setup exits 0" run_setup FAKE_FSTYPE=ext4
check "no bees config is written" test ! -e "$conf"
check "no drop-in is written" test ! -e "$dropin"
check "systemd is left alone" never_called '^systemctl '
check "not stamped" test ! -e "$stamp"

echo "== the mount cannot be inspected"
reset
check "setup fails" setup_fails FINDMNT_FAIL=1
check "no bees config is written" test ! -e "$conf"
check "not stamped" test ! -e "$stamp"

# With an empty UUID the instance drop-in path collapses into beesd@.service.d, the base's own
# drop-in directory for every bees instance.
base_dropin="$tmp/root/etc/systemd/system/beesd@.service.d/override.conf"
for case in "no UUID|FAKE_UUID=" "a UUID that is not one|FAKE_UUID=1000204886016" "a size that is not a byte count|FAKE_SIZE=931.5G"; do
	echo "== findmnt reports ${case%%|*}"
	reset
	mkdir -p "$(dirname "$base_dropin")"
	echo "base" >"$base_dropin"
	check "setup fails" setup_fails "${case#*|}"
	check "Bazzite's drop-in for all bees instances is not overwritten" test "$(cat "$base_dropin")" = base
	check "no bees config is written" bash -c "! ls '$tmp/root/etc/bees/'*.conf"
	check "systemd is left alone" never_called '^systemctl '
	check "not stamped" test ! -e "$stamp"
done

echo "== a bees config for this filesystem already exists (made with ujust configure-beesd)"
reset
mkdir -p "$(dirname "$conf")"
echo "UUID=$UUID # mine" >"$conf"
check "setup exits 0" run_setup
check "the config is left as it is" test "$(cat "$conf")" = "UUID=$UUID # mine"
check "no drop-in is added" test ! -e "$dropin"
check "systemd is left alone" never_called '^systemctl '
check "stamped so later boots skip the check" test -e "$stamp"

echo "== enabling the timer fails"
reset
check "setup fails" setup_fails SYSTEMCTL_FAIL=enable
check "not stamped, so the next boot tries again" test ! -e "$stamp"
check "the in-progress marker stays, so the next boot knows the config is ours" test -e "$creating"
: >"$tmp/calls.log"
echo "== next boot: our half-made setup is finished, not mistaken for the user's"
check "setup exits 0" run_setup
check "the config is complete" grep -qx 'DB_SIZE=536870912' "$conf"
check "the timer is enabled" called "$ENABLE"
check "stamped" test -e "$stamp"
check "the in-progress marker is gone" test ! -e "$creating"

if ((fails > 0)); then
	echo "$fails check(s) failed"
	exit 1
fi
echo "all checks passed"
