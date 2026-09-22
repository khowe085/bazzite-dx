#!/usr/bin/bash
# The Bazzite Portal entries (and one ujust recipe) this image switches on, each done the way its
# recipe does it. The per-user ones are in user-setup.hooks.d/35-portal-tweaks.sh.
set -euxo pipefail

# Manage Bazzite -> Enable Cockpit (ujust cockpit enable)
systemctl enable cockpit.service
# ujust enable-framework-fan-control. The fan is fw-fanctrl's alone: CoolerControl, which can drive
# it too, was taken out again.
systemctl enable fw-fanctrl.service

# Tweak System -> Install support for DisplayLink. The recipe layers this package from negativo17;
# the evdi kernel module it drives is already in the base.
dnf5 -y install --enable-repo='*fedora-multimedia*' displaylink

# Tweak System -> Enable visible password asterisks in CLI (ujust password-feedback on) is
# system_files/etc/sudoers.d/enable-pwfeedback; sudo wants its drop-ins read-only.
chmod 0440 /etc/sudoers.d/enable-pwfeedback

# Tweak System -> Setup virtualization. bazzite-dx ships the packages and puts users in the libvirt
# group; what is left of `ujust setup-virtualization virt-on` is libvirtd, the one-time relabel of
# libvirt's /var directories, and the kernel arguments and swtpm directory under system_files/.
systemctl enable libvirtd.service bazzite-libvirtd-setup.service

# Tweak System -> Configure btrfs snapshots / Setup btrfs deduplication, both for /var/home.
systemctl enable custom-home-snapshots.service custom-home-dedup.service
