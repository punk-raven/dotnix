#!/usr/bin/env bash
#
# Idempotent nvm + default-Node bootstrap, run from the home-manager activation
# in modules/nvm.nix on all three surfaces (macOS, Linux, WSL2).
#
# It lives here as a standalone script, not inline in the module, so
# tests/nvm_test.sh can run the REAL code path against a sandboxed $HOME and a
# stub nvm instead of asserting on the module's source text.
#
# Inputs - all required, all supplied by modules/nvm.nix:
#   DOTNIX_NVM_SRC       store path holding nvm.sh / nvm-exec / bash_completion
#   DOTNIX_NVM_VERSION   the pinned nvm release, e.g. 0.40.6
#   DOTNIX_NODE_VERSION  the pinned default Node, e.g. v24.18.1
#   NVM_DIR              where nvm lives and keeps its state
#
# The DOTNIX_ prefix is not decoration: nvm-exec reads $NODE_VERSION and nvm.sh
# reads a family of $NVM_* variables, so plainly-named inputs would be read back
# by the very tool this script drives.
#
# THIS SCRIPT NEVER EXITS NON-ZERO. Installing Node needs the network, and one
# flaky download must not fail the whole activation with no explanation - it
# warns on stderr and leaves the next activation to retry.
#
# shellcheck shell=bash

# Deliberately no `-e`: see above. `-u` and `pipefail` still catch real bugs.
set -uo pipefail

: "${DOTNIX_NVM_SRC:?nvm-bootstrap: DOTNIX_NVM_SRC is required}"
: "${DOTNIX_NVM_VERSION:?nvm-bootstrap: DOTNIX_NVM_VERSION is required}"
: "${DOTNIX_NODE_VERSION:?nvm-bootstrap: DOTNIX_NODE_VERSION is required}"
NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

warn() { echo "nvm-bootstrap: $*" >&2; }

# The stamp records which pinned nvm the files in $NVM_DIR came from, so the
# common case (already current) costs one `cat` and no writes, and bumping the
# pin in modules/nvm.nix is what moves them. A hand-installed nvm - a git clone
# or a curl|bash run - has no stamp, so the first activation takes the directory
# over and pins it; that is the point.
stamp="$NVM_DIR/.dotnix-nvm-version"

if [ "$(cat "$stamp" 2>/dev/null)" != "$DOTNIX_NVM_VERSION" ]; then
  # Only nvm's runtime files are copied, not the whole upstream tree: nvm.sh is
  # the library the shell sources, nvm-exec is the only sibling nvm.sh execs
  # (`nvm exec`), and bash_completion is what the rc file sources for
  # completions. Everything else in the release is docs, CI and the test suite.
  # Copies, not symlinks: $NVM_DIR must stay a plain writable directory because
  # nvm writes versions/, alias/ and .cache/ into it.
  if ! mkdir -p "$NVM_DIR" \
    || ! cp -f "$DOTNIX_NVM_SRC/nvm.sh" "$NVM_DIR/nvm.sh" \
    || ! cp -f "$DOTNIX_NVM_SRC/nvm-exec" "$NVM_DIR/nvm-exec" \
    || ! cp -f "$DOTNIX_NVM_SRC/bash_completion" "$NVM_DIR/bash_completion"; then
    warn "could not install nvm $DOTNIX_NVM_VERSION into $NVM_DIR; skipping"
    exit 0
  fi
  chmod 0755 "$NVM_DIR/nvm.sh" "$NVM_DIR/nvm-exec"
  chmod 0644 "$NVM_DIR/bash_completion"
  # Stamp last, so an interrupted copy is retried rather than considered done.
  printf '%s\n' "$DOTNIX_NVM_VERSION" > "$stamp"
fi

node_bin="$NVM_DIR/versions/node/$DOTNIX_NODE_VERSION/bin/node"

# `--no-use` keeps sourcing nvm.sh from resolving and activating a version,
# which is both wasted work here and the one path that would touch the network
# on an otherwise-satisfied activation.
# shellcheck disable=SC1091 # nvm.sh only exists at runtime, in $NVM_DIR
run_nvm() { ( \. "$NVM_DIR/nvm.sh" --no-use && nvm "$@" ); }

# The only network call in this script, and it is guarded by an -x test on the
# exact pinned version's binary - so a re-activation with Node already present
# downloads nothing.
if [ ! -x "$node_bin" ]; then
  if ! run_nvm install "$DOTNIX_NODE_VERSION"; then
    warn "could not install Node $DOTNIX_NODE_VERSION (network?); \`nvm\` still works, retry with a rebuild or \`nvm install $DOTNIX_NODE_VERSION\`"
    exit 0
  fi
fi

# First activation only. `nvm install` sets the default itself when no alias
# exists, so this is mostly belt-and-braces - but it also covers a $NVM_DIR that
# already had the pinned Node and no default. Once the alias exists it is left
# alone forever, so a later `nvm alias default <other>` sticks and this never
# fights the user's own version choice.
if [ ! -s "$NVM_DIR/alias/default" ] && [ -x "$node_bin" ]; then
  if ! run_nvm alias default "$DOTNIX_NODE_VERSION" >/dev/null; then
    warn "could not set nvm's default alias to $DOTNIX_NODE_VERSION"
  fi
fi

exit 0
