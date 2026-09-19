#!/usr/bin/bash
set -euxo pipefail

OP_KEY=https://downloads.1password.com/linux/keys/1password.asc
OP_DIR=/usr/lib/opt/1Password

# The RPM's post-install runs a bare `groupadd`, which hands out a GID from the user range, and
# bootc never merges /etc/group into existing installs. Create the groups first from the shipped
# sysusers.d file so the GIDs are fixed here and recreated at boot on every machine.
systemd-sysusers /usr/lib/sysusers.d/onepassword.conf

rpm --import "$OP_KEY"
dnf5 -y config-manager addrepo --id=1password \
	--set=name="1Password Stable Channel" \
	--set=baseurl='https://downloads.1password.com/linux/rpm/stable/$basearch' \
	--set=gpgcheck=1 --set=gpgkey="$OP_KEY" --set=enabled=0

# /opt -> var/opt, and /var/opt does not exist in the base, so the RPM cannot unpack /opt/1Password.
mkdir -p /var/opt
dnf5 -y --enable-repo=1password install 1password
# The post-install script rewrites the repo file with enabled=1; third-party repos stay off by default.
dnf5 -y config-manager setopt 1password.enabled=0

# /var is not shipped with the image. Keep the payload under /usr; tmpfiles.d (system_files) links
# /var/opt/1Password back to it at boot so the /opt/1Password paths keep working.
install -d "$(dirname "$OP_DIR")"
mv /var/opt/1Password "$OP_DIR"

# The post-install rendered the polkit policy from /etc/passwd, which has no desktop users at build
# time. Owners gate CheckAuthorization for the CLI/SSH-agent actions, so list the UIDs Fedora hands
# to the first ten desktop users instead of the empty set found here.
POLICY_OWNERS="$(seq -f 'unix-user:%g' 1000 1009 | tr '\n' ' ')"
sed "s|\${POLICY_OWNERS}|${POLICY_OWNERS}|" "$OP_DIR/com.1password.1Password.policy.tpl" \
	>/usr/share/polkit-1/actions/com.1password.1Password.policy
