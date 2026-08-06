#!/bin/bash
#
# Regression test for the PATH precedence contract in modules/common.nix - the
# one documented under "PATH precedence" in README.md:
#
#   pyenv shims > Homebrew > ~/.local/bin > ~/.cargo/bin > ~/.bun/bin
#     > ~/.maestro/bin > Nix profile > nvm > ~/.yarn/bin > system
#
# That order is now assembled in TWO generated files, not one: .zshenv carries
# the tail of it (profile > nvm > ~/.yarn/bin) so non-interactive shells can
# find the pinned Node, and .zshrc re-asserts the whole thing on top of pyenv
# and Homebrew. Reading either diff proves nothing about the result, so this
# test runs a real zsh and looks at the real PATH.
#
# Scenarios:
#   fresh-noninteractive  `zsh -c`   -> profile > nvm > ~/.yarn/bin, `node` found
#   fresh-interactive     `zsh -ic`  -> pyenv > profile > nvm > ~/.yarn/bin
#   nested-noninteractive `zsh -c` inside `zsh -ic` -> parent's PATH untouched
#   gate-defeated         the same, with __DOTNIX_PATH_ASSEMBLED unset, to prove
#                         the guard in .zshenv is what keeps pyenv on top there
#
# It is hermetic in the sense that matters - a throwaway $HOME holding stub
# binaries, no writes outside it, no activation - but it is NOT offline: it has
# to evaluate the flake to get the generated .zshenv/.zshrc, so it needs `nix`
# and a config.nix. Both surfaces generate the same two files apart from
# `home.profileDirectory`, which the sandbox substitutes anyway, so whichever
# surface the available config.nix selects exercises the shared logic.
#
# Run: bash tests/path_test.sh
#      DOTNIX_CONFIG=/path/to/config.nix bash tests/path_test.sh

set -uo pipefail

FAILURES=0
fail() { echo "FAIL: $1" >&2; FAILURES=$((FAILURES + 1)); }
pass() { echo "PASS: $1"; }
skip() { echo "SKIP: $1" >&2; }

# --- preconditions ------------------------------------------------------------
# A missing nix or config.nix means "cannot run here", not "the contract broke",
# so say which one and exit 0 rather than reporting a failure nobody caused.
command -v nix  >/dev/null || { skip "nix not found; this test evaluates the flake"; exit 0; }
command -v zsh  >/dev/null || { skip "zsh not found; this test runs a real zsh"; exit 0; }

CONFIG="${DOTNIX_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/dotnix/config.nix}"
[ -f "$CONFIG" ] || {
  skip "no config.nix at $CONFIG; copy config.example.nix or set \$DOTNIX_CONFIG"
  exit 0
}

# --- locate the surface this config.nix selects -------------------------------
# flake.nix exposes darwinConfigurations only on a darwin `system` and
# homeConfigurations only on the others, so the attribute path follows the
# config rather than the host.
nix_eval() { DOTNIX_CONFIG="$CONFIG" nix eval --impure --raw "$@" 2>/dev/null; }

cfg_get() { nix_eval --expr "(import $CONFIG).$1"; }
CFG_SYSTEM=$(cfg_get system)   || { skip "could not read \`system\` from $CONFIG"; exit 0; }
CFG_HOST=$(cfg_get hostname)   || { skip "could not read \`hostname\` from $CONFIG"; exit 0; }
CFG_USER=$(cfg_get username)   || { skip "could not read \`username\` from $CONFIG"; exit 0; }
CFG_HOME=$(cfg_get homeDirectory) || { skip "could not read \`homeDirectory\` from $CONFIG"; exit 0; }

case "$CFG_SYSTEM" in
  *darwin) ATTR=".#darwinConfigurations.$CFG_HOST.config.home-manager.users.$CFG_USER" ;;
  *)       ATTR=".#homeConfigurations.$CFG_USER.config" ;;
esac
echo "surface: $CFG_SYSTEM ($ATTR)"

# --- sandbox ------------------------------------------------------------------
# The generated files are used verbatim except for two absolute paths that point
# at the real machine: the Nix profile (outside $HOME on darwin) and everything
# under the configured home directory. Both are redirected into the sandbox, so
# a stub planted here is what the shell actually resolves.
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/dotnix-path-test.XXXXXX") || exit 1
trap 'rm -rf "$SANDBOX"' EXIT
SB="$SANDBOX/home"
PROFILE_BIN="$SB/profile/bin"

PIN_NODE=$(nix_eval "$ATTR.dotnix.nvm.nodeVersion") || true
[ -n "$PIN_NODE" ] || { fail "could not read dotnix.nvm.nodeVersion from $ATTR"; exit 1; }
PROFILE_DIR=$(nix_eval "$ATTR.home.profileDirectory") || true
[ -n "$PROFILE_DIR" ] || { fail "could not read home.profileDirectory from $ATTR"; exit 1; }

# .zshenv sources hm-session-vars.sh out of the store, and that is the fragment
# carrying home.sessionPath - so it has to exist, not just evaluate. Building
# .zshrc's source realises the oh-my-zsh and plugin trees it sources for the
# same reason.
DOTNIX_CONFIG="$CONFIG" nix build --impure --no-link \
  "$ATTR.home.sessionVariablesPackage" "$ATTR.home.file.\"./.zshrc\".source" \
  >/dev/null 2>&1 || { fail "could not build the generated zsh files"; exit 1; }

mkdir -p "$SB" "$PROFILE_BIN"
for f in .zshenv .zshrc; do
  nix_eval "$ATTR.home.file" --apply "f: f.\"./$f\".text" \
    | sed -e "s#$PROFILE_DIR/bin#$PROFILE_BIN#g" -e "s#$CFG_HOME#$SB#g" > "$SB/$f"
  [ -s "$SB/$f" ] || { fail "generated $f is empty"; exit 1; }
done

NVM_PIN_BIN="$SB/.nvm/versions/node/$PIN_NODE/bin"
NVM_USE_BIN="$SB/.nvm/versions/node/v0.0.0-test/bin"
mkdir -p "$SB"/{.local/bin,.cargo/bin,.bun/bin,.maestro/bin,.yarn/bin,.cache/oh-my-zsh,.pyenv/{bin,shims}} \
         "$NVM_PIN_BIN" "$NVM_USE_BIN"

# `lavish-axi` is the real historical case (an npm global outranking the pinned
# build, fixed in dc82938), so plant it in all three competing dirs: the winner
# names which dir won.
for d in "$PROFILE_BIN" "$NVM_PIN_BIN" "$NVM_USE_BIN" "$SB/.yarn/bin"; do
  printf '#!/bin/sh\necho %s\n' "$d" > "$d/lavish-axi"
  chmod +x "$d/lavish-axi"
done
for d in "$NVM_PIN_BIN" "$NVM_USE_BIN" "$SB/.yarn/bin"; do
  printf '#!/bin/sh\necho %s\n' "$d" > "$d/node"
  chmod +x "$d/node"
done

# `maestro` is installed into ~/.maestro/bin by its own installer, whose PATH
# step appends to ~/.zshrc - a read-only store symlink here, so the append
# no-ops and the binary was invisible until ~/.maestro/bin became a
# home.sessionPath entry. Nothing else ever plants a `maestro`, so this stub
# only has to prove the dir is on PATH at all, in both shell shapes.
printf '#!/bin/sh\necho %s\n' "$SB/.maestro/bin" > "$SB/.maestro/bin/maestro"
chmod +x "$SB/.maestro/bin/maestro"

# Stub nvm.sh: what real nvm does when sourcing activates a version - strip
# every $NVM_DIR version bin from PATH, then prepend the selected one. It picks
# a version that is NOT the pin, so "the interactive shell follows nvm" and "the
# non-interactive shell gets the pin" are distinguishable.
cat > "$SB/.nvm/nvm.sh" <<EOF
path=( "$NVM_USE_BIN" \${path:#\$NVM_DIR/versions/node/*} )
EOF
: > "$SB/.nvm/bash_completion"

# Stub pyenv, so the "pyenv keeps Python" half of the contract is exercised
# without depending on whether the host has a real one. .zshrc gates on
# $PYENV_ROOT/bin existing and then evals `pyenv init -`, and $PYENV_ROOT is
# $HOME-relative, so the sandbox owns both.
cat > "$SB/.pyenv/bin/pyenv" <<EOF
#!/bin/sh
[ "\$1" = "init" ] && echo 'export PATH="$SB/.pyenv/shims:\$PATH"'
EOF
chmod +x "$SB/.pyenv/bin/pyenv"

# --- helpers ------------------------------------------------------------------
# Every shell starts from `env -i`, so nothing of the caller's environment leaks
# in and /etc/zshenv sets the base PATH exactly as it would on a real login.
zsh_run() {
  local flags="$1" script="$2"
  env -i HOME="$SB" TERM=dumb "$(command -v zsh)" "$flags" "$script" 2>/dev/null
}

# Index of an exact PATH entry, or empty if absent. Printed one per line so the
# comparison is on positions, never on a substring of the joined string.
idx_of() {
  local want="$1" list="$2"
  awk -v want="$want" '$0 == want { print NR; exit }' <<<"$list"
}

assert_order() {
  local list="$1" msg="$2"; shift 2
  local prev_name="" prev_idx=0 name idx
  for name in "$@"; do
    idx=$(idx_of "${!name}" "$list")
    if [ -z "$idx" ]; then fail "$msg -- $name not on PATH (${!name})"; return; fi
    if [ -n "$prev_name" ] && [ "$idx" -le "$prev_idx" ]; then
      fail "$msg -- $prev_name (#$prev_idx) should precede $name (#$idx)"; return
    fi
    prev_name="$name"; prev_idx="$idx"
  done
  pass "$msg"
}

assert_resolves() {
  local actual="$1" expected="$2" msg="$3"
  if [ "$actual" = "$expected" ]; then pass "$msg"; else
    fail "$msg -- expected '$expected', got '${actual:-<not found>}'"; fi
}

# assert_order takes variable NAMES and dereferences them, so it can report
# which entry is out of place rather than just printing two paths.
# shellcheck disable=SC2034  # read indirectly, via ${!name}
LOCAL_BIN="$SB/.local/bin"
# shellcheck disable=SC2034  # read indirectly, via ${!name}
CARGO_BIN="$SB/.cargo/bin"
# shellcheck disable=SC2034  # read indirectly, via ${!name}
BUN_BIN="$SB/.bun/bin"
# shellcheck disable=SC2034  # read indirectly, via ${!name}
MAESTRO_BIN="$SB/.maestro/bin"
# shellcheck disable=SC2034  # read indirectly, via ${!name}
YARN_BIN="$SB/.yarn/bin"
# shellcheck disable=SC2034  # read indirectly, via ${!name}
PYENV_SHIMS="$SB/.pyenv/shims"

# Single-quoted on purpose: these are zsh, evaluated by the shell under test.
# shellcheck disable=SC2016
DUMP='print -l ${(s.:.)PATH}'
# shellcheck disable=SC2016
WHICH='echo "node=$(command -v node)"; echo "lavish=$(command -v lavish-axi)"; echo "maestro=$(command -v maestro)"'

# --- scenario: a fresh non-interactive shell ----------------------------------
# The whole point of the .zshenv half: `zsh -c` never reads .zshrc, so before
# this it saw no `node` at all.
scenario_fresh_noninteractive() {
  local out path_list
  path_list=$(zsh_run -c "$DUMP")
  out=$(zsh_run -c "$WHICH")

  assert_order "$path_list" "non-interactive: documented order holds" \
    LOCAL_BIN CARGO_BIN BUN_BIN MAESTRO_BIN PROFILE_BIN NVM_PIN_BIN YARN_BIN
  assert_resolves "$(sed -n 's/^node=//p' <<<"$out")" "$NVM_PIN_BIN/node" \
    "non-interactive: node resolves to the pinned nvm Node"
  assert_resolves "$(sed -n 's/^lavish=//p' <<<"$out")" "$PROFILE_BIN/lavish-axi" \
    "non-interactive: the Nix profile still beats nvm and ~/.yarn/bin"
  assert_resolves "$(sed -n 's/^maestro=//p' <<<"$out")" "$MAESTRO_BIN/maestro" \
    "non-interactive: maestro resolves out of ~/.maestro/bin"
}

# --- scenario: a fresh interactive shell --------------------------------------
# .zshrc runs, so pyenv goes on top and nvm.sh picks its own version - and the
# profile still has to sit between them.
scenario_fresh_interactive() {
  local out path_list
  path_list=$(zsh_run -ic "$DUMP")
  out=$(zsh_run -ic "$WHICH")

  assert_order "$path_list" "interactive: documented order holds" \
    PYENV_SHIMS LOCAL_BIN CARGO_BIN BUN_BIN MAESTRO_BIN PROFILE_BIN NVM_USE_BIN YARN_BIN
  assert_resolves "$(sed -n 's/^node=//p' <<<"$out")" "$NVM_USE_BIN/node" \
    "interactive: nvm's own selection still owns node"
  assert_resolves "$(sed -n 's/^lavish=//p' <<<"$out")" "$PROFILE_BIN/lavish-axi" \
    "interactive: the Nix profile still beats nvm and ~/.yarn/bin"
  assert_resolves "$(sed -n 's/^maestro=//p' <<<"$out")" "$MAESTRO_BIN/maestro" \
    "interactive: maestro resolves out of ~/.maestro/bin"
}

# --- scenario: a non-interactive child of an interactive shell ----------------
# It inherits a PATH .zshrc already finished assembling, and .zshrc will not run
# again to put pyenv and Homebrew back on top - so .zshenv must leave it alone.
# That is what __DOTNIX_PATH_ASSEMBLED is for.
scenario_nested_noninteractive() {
  local path_list
  path_list=$(zsh_run -ic "zsh -c 'print -l \${(s.:.)PATH}'")

  assert_order "$path_list" "nested: parent's assembled order survives" \
    PYENV_SHIMS LOCAL_BIN CARGO_BIN BUN_BIN MAESTRO_BIN PROFILE_BIN NVM_USE_BIN YARN_BIN
}

# --- scenario: the same child with the guard defeated -------------------------
# Not a contract, a control: it proves the guard above is load-bearing rather
# than decorative. Without it the profile is hoisted over pyenv, which is the
# one collision README.md says must not happen.
scenario_gate_defeated() {
  local path_list profile_idx pyenv_idx
  path_list=$(zsh_run -ic "unset __DOTNIX_PATH_ASSEMBLED; zsh -c 'print -l \${(s.:.)PATH}'")
  profile_idx=$(idx_of "$PROFILE_BIN" "$path_list")
  pyenv_idx=$(idx_of "$PYENV_SHIMS" "$path_list")

  if [ -n "$profile_idx" ] && [ -n "$pyenv_idx" ] && [ "$profile_idx" -lt "$pyenv_idx" ]; then
    pass "control: without the guard the profile would displace pyenv (so it is load-bearing)"
  else
    fail "control: defeating __DOTNIX_PATH_ASSEMBLED changed nothing -- the guard in .zshenv is no longer doing what its comment claims"
  fi
}

scenario_fresh_noninteractive
scenario_fresh_interactive
scenario_nested_noninteractive
scenario_gate_defeated

echo
if [ "$FAILURES" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "$FAILURES check(s) failed."; exit 1; fi
