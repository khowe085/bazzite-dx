#!/usr/bin/bash
set -euxo pipefail

dnf5 -y install gh
bash /ctx/install-tea.sh
