#!/usr/bin/bash
set -euxo pipefail

# Same effect as `ujust tailscale enable`; `tailscale up` still has to be run once to log in.
systemctl enable tailscaled.service
