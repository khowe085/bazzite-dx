#!/usr/bin/bash
set -euxo pipefail

# /etc/distrobox/apps.ini is the manifest behind `ujust setup-distrobox-app` and belongs to
# ublue-os-just. Append our entry instead of shipping a copy, so the base's own entries survive.
# The first-login setup reads the /usr copy directly; this only serves the ujust command.
install -d /etc/distrobox
cat /usr/share/claude-distrobox/claude.ini >>/etc/distrobox/apps.ini
