#!/usr/bin/bash
set -euxo pipefail

# Bookkeeping left by this build's dnf runs, which differs between builds even when nothing else does:
# a usage counter under /var/lib/dnf and dnf's install history. rpm-ostree's rechunking puts them in
# large layers, so each rebuild made machines re-download about 800 MB for them (the counter alone
# rode in a 633 MB layer). Nothing on a bootc system reads either, and the base ships no /var/lib/dnf.
# The history file also holds the base's own transactions, so `dnf5 history` on an installed machine
# comes back empty; `rpm-ostree db diff` is what shows package changes between deployments there.
# Runs after every step that installs packages; dnf's package state next to the history stays.
ROOT="${DNF_CLEANUP_ROOT:-}"
rm -rf "$ROOT/var/lib/dnf"
rm -f "$ROOT"/usr/lib/sysimage/libdnf5/transaction_history.sqlite{,-shm,-wal}
