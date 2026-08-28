#!/usr/bin/env bash
#
# sclaude.sh - run Claude Code inside a bubblewrap sandbox.
#
# Threat model: the agent can execute arbitrary code inside the sandbox (that
# is its job). The sandbox exists to stop that code from reaching anything
# outside the current project directory. In particular:
#
#   - No session D-Bus. A single systemd --user StartTransientUnit call on the
#     session bus spawns a process *outside* the sandbox, which would make
#     every other restriction here decorative.
#   - ~/.claude is an overlay: the sandbox reads your real config but every
#     write lands in a private upper dir. Host settings.json / plugins / hooks
#     stay untouched, because those execute OUTSIDE the sandbox in your normal
#     Claude sessions.
#   - The environment is cleared. Host API keys and tokens do not leak in.
#   - $PWD may not be $HOME, / , an ancestor of $HOME, or a sensitive dotdir.
#
# Opt-in escape hatches (each is documented at its use site below):
#   SAFE_AGENTS_DBUS=proxy       filtered session bus, Secret Service only
#   SAFE_AGENTS_GNUPG_FULL=1     bind all of ~/.gnupg read-only
#   SAFE_AGENTS_PASSTHRU="A B"   extra env vars to forward into the sandbox
#   SAFE_AGENTS_STATE=<dir>      where sandbox-private state is kept

set -euo pipefail

die()  { printf 'sclaude: %s\n' "$*" >&2; exit 1; }
warn() { printf 'sclaude: %s\n' "$*" >&2; }

# --------------------------------------------------------------------------
# Preflight
# --------------------------------------------------------------------------

command -v bwrap >/dev/null 2>&1 || die "bwrap not found (apt install bubblewrap)"
CLAUDE_BIN=$(command -v claude) || die "claude not found in PATH"

WORKDIR=$(realpath -e -- "$PWD")  || die "cannot resolve \$PWD"
HOMEDIR=$(realpath -e -- "$HOME") || die "cannot resolve \$HOME"

# The project dir is bound read-write, so refuse the ones that would hand the
# agent the whole home directory (or a sensitive corner of it).
if [ "$WORKDIR" = "/" ] || [ "$WORKDIR" = "$HOMEDIR" ]; then
  die "refusing to sandbox '$WORKDIR' as the project directory"
fi
case "$HOMEDIR/" in
  "$WORKDIR"/*) die "refusing: \$PWD ($WORKDIR) is an ancestor of \$HOME" ;;
esac
for forbidden in .ssh .gnupg .claude .local .config; do
  if [ "$WORKDIR" = "$HOMEDIR/$forbidden" ]; then
    die "refusing to sandbox '$WORKDIR' as the project directory"
  fi
done

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
STATE_DIR="${SAFE_AGENTS_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/safe-agents}"
mkdir -p "$STATE_DIR/claude-upper" "$STATE_DIR/claude-work"

# --------------------------------------------------------------------------
# Filesystem
# --------------------------------------------------------------------------

# Everything is built as arrays: no word splitting, no globbing, and paths
# containing spaces survive intact. The *-try variants skip a bind whose
# source is missing instead of aborting the whole sandbox.
BW=(
  --ro-bind     /usr /usr
  --ro-bind-try /lib /lib
  --ro-bind-try /lib64 /lib64
  --ro-bind-try /bin /bin
  --ro-bind-try /etc/resolv.conf /etc/resolv.conf
  --ro-bind-try /etc/hosts /etc/hosts
  --ro-bind-try /etc/ssl /etc/ssl
  --ro-bind-try /etc/passwd /etc/passwd
  --ro-bind-try /etc/group /etc/group
  --tmpfs /tmp
  --perms 0700 --tmpfs "$RUNTIME_DIR"
)

# Read-only host config the agent needs but must never rewrite.
BW+=(
  --ro-bind-try "$HOME/.gitconfig" "$HOME/.gitconfig"
  --ro-bind-try "$HOME/.nvm" "$HOME/.nvm"
  --ro-bind-try "$HOME/.config/git" "$HOME/.config/git"
  --ro-bind-try "$HOME/.config/gh" "$HOME/.config/gh"
  --ro-bind-try "$HOME/.local" "$HOME/.local"
  --ro-bind-try "$HOME/.ssh/known_hosts" "$HOME/.ssh/known_hosts"
  --bind-try    "$HOME/.npm" "$HOME/.npm"
)
for keytype in id_ed25519 id_rsa id_ecdsa; do
  BW+=( --ro-bind-try "$HOME/.ssh/$keytype.pub" "$HOME/.ssh/$keytype.pub" )
done

# The project itself.
BW+=( --bind "$WORKDIR" "$WORKDIR" )

# --------------------------------------------------------------------------
# ~/.claude - overlay, so host hooks/plugins/settings cannot be rewritten
# --------------------------------------------------------------------------

# Config and credentials are read through from the host; anything Claude Code
# writes (transcripts, todos, refreshed tokens, caches) goes to the upper dir
# and is invisible to the host. Sandbox sessions therefore keep their own
# history and their own memory files, which is the point.
overlay_supported() {
  bwrap --ro-bind /usr /usr --ro-bind-try /lib /lib --ro-bind-try /lib64 /lib64 \
        --overlay-src "$HOME/.claude" --tmp-overlay /mnt \
        /usr/bin/true >/dev/null 2>&1
}

if [ -d "$HOME/.claude" ]; then
  if overlay_supported; then
    BW+=(
      --overlay-src "$HOME/.claude"
      --overlay "$STATE_DIR/claude-upper" "$STATE_DIR/claude-work" "$HOME/.claude"
    )
  else
    warn "overlayfs unavailable; using read-only ~/.claude with ephemeral state"
    BW+=( --ro-bind "$HOME/.claude" "$HOME/.claude" )
    for d in projects todos sessions session-env shell-snapshots file-history \
             tasks plans jobs cache backups downloads paste-cache telemetry ide; do
      if [ -d "$HOME/.claude/$d" ]; then BW+=( --tmpfs "$HOME/.claude/$d" ); fi
    done
  fi
fi

# ~/.claude.json is a single file, so it gets a private copy rather than an
# overlay. The host copy wins whenever it is newer (auth, project config).
if [ -f "$HOME/.claude.json" ] &&
   { [ ! -f "$STATE_DIR/claude.json" ] || [ "$HOME/.claude.json" -nt "$STATE_DIR/claude.json" ]; }; then
  cp -p -- "$HOME/.claude.json" "$STATE_DIR/claude.json"
fi
[ -f "$STATE_DIR/claude.json" ] || printf '{}\n' > "$STATE_DIR/claude.json"
BW+=( --bind "$STATE_DIR/claude.json" "$HOME/.claude.json" )

# --------------------------------------------------------------------------
# Environment - cleared, then rebuilt explicitly
# --------------------------------------------------------------------------

ENVIRON=(
  --clearenv
  --setenv HOME "$HOME"
  --setenv USER "${USER:-$(id -un)}"
  --setenv LOGNAME "${LOGNAME:-${USER:-$(id -un)}}"
  --setenv PATH "$PATH"
  --setenv XDG_RUNTIME_DIR "$RUNTIME_DIR"
  --setenv SAFE_AGENT 1
)
# Forwarded only if set on the host. Add your own via SAFE_AGENTS_PASSTHRU;
# note that anything forwarded here is readable by the agent and the sandbox
# has full network access.
for var in SHELL TERM COLORTERM LANG LC_ALL TZ GPG_TTY GPG_SIGNING_KEY_ID \
           ${SAFE_AGENTS_PASSTHRU:-}; do
  if [ -n "${!var:-}" ]; then ENVIRON+=( --setenv "$var" "${!var}" ); fi
done

# --------------------------------------------------------------------------
# SSH agent - the socket only, never its directory
# --------------------------------------------------------------------------

# Binding dirname("$SSH_AUTH_SOCK") would, for an agent socket living directly
# in $XDG_RUNTIME_DIR, hand over the whole runtime dir: the session bus and
# systemd's private socket included. Bind the socket to a fixed path instead.
# It is bound read-write on purpose: a read-only bind does not block connect()
# on a socket inode, so it only ever looked like a restriction.
if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "$SSH_AUTH_SOCK" ]; then
  BW+=( --bind "$SSH_AUTH_SOCK" /run/ssh-agent.sock )
  ENVIRON+=( --setenv SSH_AUTH_SOCK /run/ssh-agent.sock )
fi

# --------------------------------------------------------------------------
# GnuPG - public material only; private keys stay with the host agent
# --------------------------------------------------------------------------

if [ -d "$HOME/.gnupg" ]; then
  if [ "${SAFE_AGENTS_GNUPG_FULL:-0}" = 1 ]; then
    BW+=( --ro-bind "$HOME/.gnupg" "$HOME/.gnupg" )
    BW+=( --bind-try "$HOME/.gnupg/trustdb.gpg" "$HOME/.gnupg/trustdb.gpg" )
    BW+=( --bind-try "$HOME/.gnupg/random_seed" "$HOME/.gnupg/random_seed" )
  else
    # Writable tmpfs so gpg can drop lock files and random_seed, with only the
    # public keyring and config read through. Signing still works: the private
    # keys never enter the sandbox, the host gpg-agent does the signing over
    # its socket below.
    BW+=( --perms 0700 --tmpfs "$HOME/.gnupg" )
    for f in pubring.kbx pubring.gpg trustdb.gpg gpg.conf gpg-agent.conf; do
      BW+=( --ro-bind-try "$HOME/.gnupg/$f" "$HOME/.gnupg/$f" )
    done
  fi
fi

GPG_SOCKDIR=$(gpgconf --list-dirs socketdir 2>/dev/null || true)
if [ -n "$GPG_SOCKDIR" ] && [ -d "$GPG_SOCKDIR" ]; then
  BW+=( --bind "$GPG_SOCKDIR" "$GPG_SOCKDIR" )
fi

# --------------------------------------------------------------------------
# D-Bus - off by default; filtered proxy on request
# --------------------------------------------------------------------------

proxy_pid=""
proxy_dir=""
cleanup() {
  if [ -n "$proxy_pid" ]; then kill "$proxy_pid" 2>/dev/null || true; fi
  if [ -n "$proxy_dir" ]; then
    # No rm(1) here: unlink/rmdir only.
    if [ -S "$proxy_dir/bus" ]; then unlink "$proxy_dir/bus" 2>/dev/null || true; fi
    rmdir "$proxy_dir" 2>/dev/null || true
  fi
}

case "${SAFE_AGENTS_DBUS:-off}" in
  off) ;;
  proxy)
    # Claude Code only needs the bus to reach the keyring (Secret Service).
    # xdg-dbus-proxy exposes exactly that name and nothing else - crucially
    # not org.freedesktop.systemd1, which is an escape.
    command -v xdg-dbus-proxy >/dev/null 2>&1 ||
      die "SAFE_AGENTS_DBUS=proxy requires xdg-dbus-proxy"
    host_bus="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$RUNTIME_DIR/bus}"
    proxy_dir=$(mktemp -d "${TMPDIR:-/tmp}/safe-agents-dbus.XXXXXX")
    trap cleanup EXIT INT TERM
    xdg-dbus-proxy "$host_bus" "$proxy_dir/bus" \
      --filter --talk=org.freedesktop.secrets &
    proxy_pid=$!
    # Wait for the socket rather than xdg-dbus-proxy's --fd handshake: the
    # fifo form deadlocks if the redirection is set up before the fork.
    for _ in $(seq 1 50); do
      if [ -S "$proxy_dir/bus" ]; then break; fi
      if ! kill -0 "$proxy_pid" 2>/dev/null; then break; fi
      sleep 0.1
    done
    [ -S "$proxy_dir/bus" ] || die "xdg-dbus-proxy failed to start"
    BW+=( --bind "$proxy_dir/bus" /run/dbus-session.sock )
    ENVIRON+=( --setenv DBUS_SESSION_BUS_ADDRESS unix:path=/run/dbus-session.sock )
    ;;
  *) die "SAFE_AGENTS_DBUS must be 'off' or 'proxy'" ;;
esac

# --------------------------------------------------------------------------
# Go
# --------------------------------------------------------------------------

CMD=(
  bwrap
  "${BW[@]}"
  --proc /proc
  --dev /dev
  "${ENVIRON[@]}"
  --share-net
  --unshare-pid
  --die-with-parent
  --chdir "$WORKDIR"
  -- "$CLAUDE_BIN" "$@"
)

if [ -n "$proxy_pid" ]; then
  # Keep the shell alive so the trap can reap the proxy.
  status=0
  "${CMD[@]}" || status=$?
  exit "$status"
fi
exec "${CMD[@]}"
