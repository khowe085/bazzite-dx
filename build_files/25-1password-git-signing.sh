#!/usr/bin/bash
set -euxo pipefail

# The key-independent half of what 1Password's "Configure commit signing" writes to ~/.gitconfig.
# `git config --system` edits /etc/gitconfig in place, so anything the base ships there survives.
# user.signingkey is per user and comes from the app; until it is set, plain `git commit` refuses
# to run, which is the point of signing by default.
git config --system gpg.format ssh
git config --system gpg.ssh.program /opt/1Password/op-ssh-sign
git config --system commit.gpgsign true
