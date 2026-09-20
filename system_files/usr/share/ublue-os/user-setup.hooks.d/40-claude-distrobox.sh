#!/usr/bin/bash
# First login: start the Claude Desktop distrobox setup as a detached user unit. ublue-user-setup
# runs its hooks one after another and this setup takes minutes (image pull plus apt), so running
# it inline would hold up every hook behind it. Follow it with:
#   journalctl --user -u claude-distrobox-setup
set -euo pipefail

STAMP="${XDG_STATE_HOME:-$HOME/.local/state}/claude-distrobox.created"
if [[ -e "$STAMP" ]]; then
	exit 0
fi
# If a setup from an earlier login is still running, the unit name is taken and systemd-run
# refuses. That is not a failure of this hook: there is nothing to add.
if ! systemd-run --user --collect --quiet --unit=claude-distrobox-setup /usr/libexec/claude-distrobox-setup; then
	echo "claude-distrobox-setup was not started; it is probably still running from an earlier login"
fi
