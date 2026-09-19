#!/usr/bin/bash
set -euxo pipefail

# Host-side broker that lets the sandboxed Firefox start native messaging hosts such as
# 1Password-BrowserSupport. Firefox uses it from 157 on; the service only stages configuration.
dnf5 -y install xdg-native-messaging-proxy
systemctl enable onepassword-firefox-flatpak.service
