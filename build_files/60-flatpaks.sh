#!/usr/bin/bash
set -euxo pipefail

# Fedora ships `flatpak preinstall` without a unit to run it; this one installs
# /usr/share/flatpak/preinstall.d/*.preinstall at boot.
systemctl enable custom-flatpak-preinstall.service
