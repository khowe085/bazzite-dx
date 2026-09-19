#!/usr/bin/bash
# Entry point run by the Containerfile: lays down system_files/ on / and runs the numbered
# build steps in order. 90-verify.sh runs last and fails the build if anything is missing.
set -euo pipefail

# A Windows working copy hands Docker 0755 on every file, so don't take modes from the checkout:
# with --no-preserve=mode, cp creates files as 0666 and directories as 0777 masked by the umask
# (0644 / 0755 here), whatever the source mode was. Executables are set explicitly below.
cp -avf --no-preserve=mode /ctx/system_files/. /
for dir in usr/libexec usr/share/ublue-os/user-setup.hooks.d; do
	for f in /ctx/system_files/"$dir"/*; do
		[[ -f "$f" ]] && chmod 0755 "/$dir/$(basename "$f")"
	done
done

for script in /ctx/[0-9][0-9]-*.sh; do
	echo "::group::$(basename "$script")"
	bash "$script"
	echo "::endgroup::"
done
