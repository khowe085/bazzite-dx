#!/usr/bin/bash
# Exercises the system-side preconfiguration for 1Password's SSH agent and Git commit signing:
# build_files/25-1password-git-signing.sh against a scratch system gitconfig (GIT_CONFIG_SYSTEM), and
# the ssh_config.d drop-in through the real ssh client.
# Run inside a container with the repo mounted at /src:
#   podman run --rm -v "$PWD:/src:ro,Z" <image> /src/tests/test-1password-ssh-git.sh
set -uo pipefail

SRC="${SRC:-/src}"
GIT_STEP="$SRC/build_files/25-1password-git-signing.sh"
SSH_DROPIN="$SRC/system_files/etc/ssh/ssh_config.d/60-1password-agent.conf"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# Git Bash on Windows rewrites arguments that look like POSIX paths before git.exe sees them, which
# would turn /opt/1Password/op-ssh-sign into a Windows path. Switch that off, and hand git.exe a temp
# path it understands without the rewriting. None of this exists or matters on Linux.
if command -v cygpath >/dev/null 2>&1; then
	tmp="$(cygpath -m "$tmp")"
	export MSYS_NO_PATHCONV=1
fi

fails=0
check() {
	local desc=$1
	shift
	if "$@" >/dev/null 2>&1; then
		echo "ok   - $desc"
	else
		echo "FAIL - $desc"
		fails=$((fails + 1))
	fi
}
sysgit() { GIT_CONFIG_SYSTEM="$tmp/gitconfig" git config --system "$@"; }

echo "== system git config"
# A base image may already ship settings in /etc/gitconfig; they have to survive.
printf '[core]\n\tpager = less -F\n' >"$tmp/gitconfig"
check "build step exits 0" env GIT_CONFIG_SYSTEM="$tmp/gitconfig" bash "$GIT_STEP"
check "signatures use SSH" test "$(sysgit gpg.format)" = ssh
check "the signer is 1Password's op-ssh-sign" test "$(sysgit gpg.ssh.program)" = /opt/1Password/op-ssh-sign
check "commits are signed by default" test "$(sysgit --type=bool commit.gpgsign)" = true
check "settings already in the file survive" test "$(sysgit core.pager)" = "less -F"
check "no signing key is preset (that is per user, set in the app)" test -z "$(sysgit --get-all user.signingkey)"
check "second run exits 0" env GIT_CONFIG_SYSTEM="$tmp/gitconfig" bash "$GIT_STEP"
check "second run adds no duplicate values" test "$(sysgit --get-all gpg.ssh.program | wc -l)" = 1
# Fedora ships no /etc/gitconfig, so the real build most likely starts without the file.
check "build step creates the system config when there is none" env GIT_CONFIG_SYSTEM="$tmp/fresh-gitconfig" bash "$GIT_STEP"
check "and the fresh file signs with SSH too" test "$(GIT_CONFIG_SYSTEM="$tmp/fresh-gitconfig" git config --system gpg.format)" = ssh

echo "== what a user sees before choosing a signing key in 1Password"
git init -q "$tmp/repo"
commit() {
	env GIT_CONFIG_SYSTEM="$tmp/gitconfig" GIT_CONFIG_GLOBAL=/dev/null HOME="$tmp" \
		GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com \
		git -C "$tmp/repo" commit --allow-empty -m test "$@"
}
commit_fails() { ! commit "$@"; }
check "an unsigned commit is still possible on request" commit --no-gpg-sign
check "a plain commit is refused until a signing key exists" commit_fails
commit >"$tmp/commit.out" 2>&1
check "and git names the missing piece" grep -q 'user.signingkey' "$tmp/commit.out"

echo "== ssh client drop-in"
REMOTE='SSH_CONNECTION=10.0.0.2 50000 10.0.0.1 22'
skip() { echo "skip - $1"; }
# What ssh resolves for a host: prints the identityagent line, if any. IdentityAgent outranks
# SSH_AUTH_SOCK, so "no line" is what leaves a forwarded or session agent in charge.
agent_line() { # agent_line [env args ...]
	env "$@" ssh -F "$SSH_DROPIN" -G example.com 2>/dev/null | grep -i '^identityagent'
}
uses_1password() { agent_line "$@" | grep -Eiq '^identityagent .*/\.1password/agent\.sock$'; }
leaves_agent_alone() { ! agent_line "$@" | grep -q .; }

check "ssh accepts the drop-in" ssh -F "$SSH_DROPIN" -G example.com
check "the agent socket is the one 1Password documents" grep -Eqx '[[:space:]]*IdentityAgent ~/\.1password/agent\.sock' "$SSH_DROPIN"

# ssh takes the home directory from the passwd entry, not from $HOME, so the socket has to sit in
# the real home. An existing one (1Password running here) is used as is and never touched.
home="$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6)"
home="$(readlink -m "${home:-$HOME}")"
sock="$home/.1password/agent.sock"
# Whatever this test puts into the real home it takes out again, and nothing else: a socket or a
# directory that was already there is never removed.
made_sock=""
made_dir=""
cleanup_sock() {
	[[ -n "$made_sock" ]] && rm -f "$sock"
	[[ -n "$made_dir" ]] && rmdir "$home/.1password" 2>/dev/null
	return 0
}
trap 'cleanup_sock; rm -rf "$tmp"' EXIT

if [[ -S "$sock" ]]; then
	skip "socket-absent case: a 1Password agent socket already exists at $sock"
else
	check "no 1Password socket: the session's own agent is left alone" leaves_agent_alone -u SSH_CONNECTION
	# Only touch the home directory where a socket can actually be made (not under Git Bash).
	if command -v python3 >/dev/null 2>&1; then
		if [[ ! -d "$home/.1password" ]] && mkdir -p "$home/.1password" 2>/dev/null; then
			made_dir=1
		fi
		if python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$sock" 2>/dev/null; then
			made_sock=1
		fi
	fi
fi
if [[ -S "$sock" ]]; then
	check "local session with the socket present: 1Password's agent is used" uses_1password -u SSH_CONNECTION
	check "connected over SSH with a TTY: a forwarded agent is left alone" leaves_agent_alone "$REMOTE" SSH_TTY=/dev/pts/3
	check "connected over SSH without a TTY (remote command, editor): same" leaves_agent_alone -u SSH_TTY "$REMOTE"
else
	skip "socket-present cases: cannot create a unix socket on this platform"
	# Still worth pinning here: over SSH the drop-in must stay out of the way regardless.
	check "connected over SSH: a forwarded agent is left alone" leaves_agent_alone "$REMOTE"
fi

if ((fails > 0)); then
	echo "$fails check(s) failed"
	exit 1
fi
echo "all checks passed"
