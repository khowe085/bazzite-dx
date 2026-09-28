#!/usr/bin/bash
set -euxo pipefail

# What `gh auth setup-git` writes to ~/.gitconfig, in /etc/gitconfig instead so HTTPS to GitHub
# authenticates through gh out of the box. The empty helper clears any helper set before this one
# (git's list semantics), so gh answers for these hosts alone. The helpers are replaced as a whole,
# so a second run adds nothing. gh itself is installed by 80-forge-clis.sh.
for host in https://github.com https://gist.github.com; do
	key="credential.$host.helper"
	# Exit status 5: the key was not set.
	git config --system --unset-all "$key" || (($? == 5))
	git config --system --add "$key" ''
	git config --system --add "$key" '!/usr/bin/gh auth git-credential'
done
