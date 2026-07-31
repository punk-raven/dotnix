#!/bin/bash
#
# Regression test for lib/nvm-bootstrap.sh - the activation step that installs
# nvm and a pinned default LTS Node on all three surfaces (see modules/nvm.nix).
#
# The script's whole job is to mutate $NVM_DIR and shell out to `nvm install`,
# which downloads ~50MB of Node. So the default run is hermetic: every scenario
# gets a throwaway $HOME, a fake "store" standing in for the pinned nvm scripts,
# and a stub `nvm` that logs its invocations and fakes the directories a real
# install would create. Nothing touches the network or the real ~/.nvm.
#
# Scenarios (all assert on observed behaviour, never on the script's source):
#   fresh              empty $NVM_DIR -> nvm installed, Node installed, default set
#   idempotent         second run     -> no `nvm` calls at all, no rewrites
#   node-present       Node already there, no default alias -> alias only
#   pin-bump           nvm pin changed -> scripts re-synced, Node untouched
#   install-failure    `nvm install` fails -> exit 0, warning, no default alias
#   retry-after-failure a failed run leaves nothing that skips the next attempt
#   respects-user      a user-chosen default alias is never overwritten
#   takes-over-manual  a hand-installed (unstamped) nvm gets pinned
#
# One further scenario sources the REAL upstream nvm.sh to prove the three files
# modules/nvm.nix copies are enough for a working `nvm` command. It needs `nix`
# and, the first time, a network fetch of the pinned tarball - so it is opt-in:
#
#   DOTNIX_NVM_TEST_ONLINE=1 bash tests/nvm_test.sh
#
# Run: bash tests/nvm_test.sh

set -uo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &> /dev/null && pwd)
BOOTSTRAP="$REPO_ROOT/lib/nvm-bootstrap.sh"
MODULE="$REPO_ROOT/modules/nvm.nix"

PINNED_NVM="0.40.6-test"
PINNED_NODE="v24.18.1"

FAILURES=0
fail() { echo "FAIL: $1" >&2; FAILURES=$((FAILURES + 1)); }
pass() { echo "PASS: $1"; }

assert_contains() {
  local haystack="$1" needle="$2" msg="$3"
  if grep -qF -- "$needle" <<<"$haystack"; then pass "$msg"; else
    fail "$msg -- expected to find: $needle"; fi
}
assert_not_contains() {
  local haystack="$1" needle="$2" msg="$3"
  if grep -qF -- "$needle" <<<"$haystack"; then
    fail "$msg -- expected NOT to find: $needle"; else pass "$msg"; fi
}
assert_eq() {
  local actual="$1" expected="$2" msg="$3"
  if [ "$actual" = "$expected" ]; then pass "$msg"; else
    fail "$msg -- expected '$expected', got '$actual'"; fi
}
assert_exists() {
  if [ -e "$1" ]; then pass "$2"; else fail "$2 -- missing: $1"; fi
}
assert_not_exists() {
  if [ -e "$1" ]; then fail "$2 -- unexpectedly present: $1"; else pass "$2"; fi
}
assert_executable() {
  if [ -x "$1" ]; then pass "$2"; else fail "$2 -- not executable: $1"; fi
}

mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1"; }

# --- sandbox ------------------------------------------------------------------
# Each scenario gets a $HOME, a fake store dir standing in for `nvmScripts` in
# modules/nvm.nix, and a stub upstream tree.
#
# The stub `nvm` is a shell FUNCTION defined by the stub nvm.sh, exactly as
# upstream defines it - `nvm` is not an executable, so a PATH stub would never
# be reached by the bootstrap's `. nvm.sh && nvm ...`. Its install arm fails
# whenever $SANDBOX/fail-install exists, so a scenario can flip the network
# between runs without rebuilding the sandbox.
SANDBOX=""
make_sandbox() {
  local name="$1"
  SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/nvm-test-${name}.XXXXXX") || exit 1
  export HOME="$SANDBOX/home"
  export NVM_DIR="$HOME/.nvm"
  export STUB_LOG="$SANDBOX/log"
  export STUB_FAIL="$SANDBOX/fail-install"
  mkdir -p "$HOME" "$SANDBOX/store"
  : > "$STUB_LOG"

  # The marker line lets pin-bump prove the files were really re-copied.
  {
    printf 'stub nvm.sh %s\n' "$name"
    cat <<'STUBEOF'
nvm() {
  echo "nvm $*" >> "$STUB_LOG"
  case "$1" in
    install)
      [ -e "$STUB_FAIL" ] && return 1
      mkdir -p "$NVM_DIR/versions/node/$2/bin"
      printf '#!/bin/sh\n' > "$NVM_DIR/versions/node/$2/bin/node"
      chmod +x "$NVM_DIR/versions/node/$2/bin/node"
      # Real nvm sets the default itself when no alias exists yet.
      if [ ! -s "$NVM_DIR/alias/default" ]; then
        mkdir -p "$NVM_DIR/alias"
        printf '%s\n' "$2" > "$NVM_DIR/alias/default"
      fi
      ;;
    alias)
      mkdir -p "$NVM_DIR/alias"
      printf '%s\n' "$3" > "$NVM_DIR/alias/$2"
      ;;
  esac
}
STUBEOF
  } > "$SANDBOX/store/nvm.sh"
  printf 'stub nvm-exec %s\n' "$name" > "$SANDBOX/store/nvm-exec"
  printf 'stub bash_completion %s\n' "$name" > "$SANDBOX/store/bash_completion"
}

cleanup_sandbox() { [ -n "$SANDBOX" ] && rm -rf "$SANDBOX"; SANDBOX=""; }

# Runs the real bootstrap script; echoes combined output and sets RUN_STATUS.
RUN_STATUS=0
run_bootstrap() {
  local pin="${1:-$PINNED_NVM}" out
  out=$(DOTNIX_NVM_SRC="$SANDBOX/store" \
        DOTNIX_NVM_VERSION="$pin" \
        DOTNIX_NODE_VERSION="$PINNED_NODE" \
        NVM_DIR="$NVM_DIR" \
        STUB_LOG="$STUB_LOG" \
        STUB_FAIL="$STUB_FAIL" \
        HOME="$HOME" \
        bash "$BOOTSTRAP" 2>&1)
  RUN_STATUS=$?
  printf '%s' "$out"
}

count_log() { grep -c "^nvm $1" "$STUB_LOG" 2>/dev/null || true; }

# --- scenarios ----------------------------------------------------------------

scenario_fresh() {
  make_sandbox fresh
  local out; out=$(run_bootstrap)
  assert_eq "$RUN_STATUS" "0" "fresh: exits 0"
  assert_executable "$NVM_DIR/nvm.sh" "fresh: nvm.sh installed and executable"
  assert_executable "$NVM_DIR/nvm-exec" "fresh: nvm-exec installed and executable"
  assert_exists "$NVM_DIR/bash_completion" "fresh: bash_completion installed"
  assert_eq "$(cat "$NVM_DIR/.dotnix-nvm-version")" "$PINNED_NVM" "fresh: pin stamped"
  assert_executable "$NVM_DIR/versions/node/$PINNED_NODE/bin/node" "fresh: pinned Node installed"
  assert_eq "$(cat "$NVM_DIR/alias/default")" "$PINNED_NODE" "fresh: default alias set to the pinned Node"
  assert_eq "$(count_log install)" "1" "fresh: exactly one \`nvm install\`"
  assert_not_contains "$out" "nvm-bootstrap:" "fresh: no warnings"
  cleanup_sandbox
}

scenario_idempotent() {
  make_sandbox idempotent
  run_bootstrap >/dev/null
  local stamp_before nvm_before
  stamp_before=$(mtime "$NVM_DIR/.dotnix-nvm-version")
  nvm_before=$(mtime "$NVM_DIR/nvm.sh")
  sleep 1
  local out; out=$(run_bootstrap)
  assert_eq "$RUN_STATUS" "0" "idempotent: second run exits 0"
  assert_eq "$(count_log install)" "1" "idempotent: no second \`nvm install\` (no redundant download)"
  assert_eq "$(grep -c . "$STUB_LOG")" "1" "idempotent: nvm not invoked at all on the second run"
  assert_eq "$(mtime "$NVM_DIR/.dotnix-nvm-version")" "$stamp_before" "idempotent: stamp not rewritten"
  assert_eq "$(mtime "$NVM_DIR/nvm.sh")" "$nvm_before" "idempotent: nvm.sh not re-copied"
  assert_not_contains "$out" "nvm-bootstrap:" "idempotent: no warnings"
  cleanup_sandbox
}

scenario_node_present() {
  make_sandbox node-present
  # Node already installed by hand; no default alias yet.
  mkdir -p "$NVM_DIR/versions/node/$PINNED_NODE/bin"
  printf '#!/bin/sh\n' > "$NVM_DIR/versions/node/$PINNED_NODE/bin/node"
  chmod +x "$NVM_DIR/versions/node/$PINNED_NODE/bin/node"
  run_bootstrap >/dev/null
  assert_eq "$RUN_STATUS" "0" "node-present: exits 0"
  assert_eq "$(count_log install)" "0" "node-present: never re-downloads an installed Node"
  assert_eq "$(cat "$NVM_DIR/alias/default")" "$PINNED_NODE" "node-present: default alias filled in"
  cleanup_sandbox
}

scenario_pin_bump() {
  make_sandbox pin-bump
  run_bootstrap "0.40.5-test" >/dev/null
  assert_contains "$(cat "$NVM_DIR/nvm.sh")" "stub nvm.sh pin-bump" "pin-bump: scripts installed on the first run"
  # New pin, new upstream contents: the bump must move the files, not just the stamp.
  printf 'stub nvm.sh bumped\n' > "$SANDBOX/store/nvm.sh"
  run_bootstrap "0.40.6-test" >/dev/null
  assert_eq "$RUN_STATUS" "0" "pin-bump: exits 0"
  assert_contains "$(cat "$NVM_DIR/nvm.sh")" "stub nvm.sh bumped" "pin-bump: nvm.sh re-synced from the new pin"
  assert_eq "$(cat "$NVM_DIR/.dotnix-nvm-version")" "0.40.6-test" "pin-bump: stamp follows the pin"
  assert_eq "$(count_log install)" "1" "pin-bump: bumping nvm does not reinstall Node"
  cleanup_sandbox
}

scenario_install_failure() {
  make_sandbox install-failure
  : > "$STUB_FAIL"
  local out; out=$(run_bootstrap)
  assert_eq "$RUN_STATUS" "0" "install-failure: exits 0 so activation survives a failed download"
  assert_contains "$out" "could not install Node $PINNED_NODE" "install-failure: explains what failed"
  assert_executable "$NVM_DIR/nvm.sh" "install-failure: nvm itself is still installed"
  assert_not_exists "$NVM_DIR/alias/default" "install-failure: no default alias pointing at a missing Node"
  cleanup_sandbox
}

scenario_retry_after_failure() {
  make_sandbox retry-after-failure
  : > "$STUB_FAIL"
  run_bootstrap >/dev/null
  assert_eq "$(count_log install)" "1" "retry-after-failure: attempted once"
  rm -f "$STUB_FAIL"   # network is back
  run_bootstrap >/dev/null
  assert_eq "$RUN_STATUS" "0" "retry-after-failure: exits 0"
  assert_eq "$(count_log install)" "2" "retry-after-failure: the next activation retries the install"
  assert_executable "$NVM_DIR/versions/node/$PINNED_NODE/bin/node" "retry-after-failure: Node installed on the retry"
  assert_eq "$(cat "$NVM_DIR/alias/default")" "$PINNED_NODE" "retry-after-failure: default alias set on the retry"
  cleanup_sandbox
}

scenario_respects_user() {
  make_sandbox respects-user
  run_bootstrap >/dev/null
  # The user picks their own default afterwards; activation must not undo it.
  printf 'v20.11.1\n' > "$NVM_DIR/alias/default"
  run_bootstrap >/dev/null
  assert_eq "$RUN_STATUS" "0" "respects-user: exits 0"
  assert_eq "$(cat "$NVM_DIR/alias/default")" "v20.11.1" "respects-user: a user-chosen default alias survives activation"
  assert_eq "$(count_log alias)" "0" "respects-user: never re-aliases once a default exists"
  cleanup_sandbox
}

scenario_takes_over_manual() {
  make_sandbox takes-over-manual
  # A hand-installed nvm: files present, no stamp (curl|bash, or a git clone).
  mkdir -p "$NVM_DIR"
  printf 'hand-installed nvm.sh\n' > "$NVM_DIR/nvm.sh"
  run_bootstrap >/dev/null
  assert_eq "$RUN_STATUS" "0" "takes-over-manual: exits 0"
  assert_contains "$(cat "$NVM_DIR/nvm.sh")" "stub nvm.sh takes-over-manual" "takes-over-manual: an unstamped nvm is replaced by the pinned one"
  assert_eq "$(cat "$NVM_DIR/.dotnix-nvm-version")" "$PINNED_NVM" "takes-over-manual: pin stamped"
  cleanup_sandbox
}

# --- opt-in: the real nvm ------------------------------------------------------
# Establishes the one thing a stub cannot: that the three files modules/nvm.nix
# copies are sufficient for a working `nvm`. Node is pre-seeded so the scenario
# makes no Node download - the only network is the pinned tarball fetch, and
# only on a cold Nix store.
scenario_real_nvm() {
  if [ "${DOTNIX_NVM_TEST_ONLINE:-}" != "1" ]; then
    echo "SKIP: real-nvm (set DOTNIX_NVM_TEST_ONLINE=1 to run; needs nix + network)"
    return
  fi
  command -v nix >/dev/null || { echo "SKIP: real-nvm (no nix on PATH)"; return; }

  local ver url store
  ver=$(sed -nE 's/^[[:space:]]*nvmVersion = "([^"]+)".*/\1/p' "$MODULE")
  [ -n "$ver" ] || { fail "real-nvm: no nvmVersion pin found in $MODULE"; return; }
  url="https://github.com/nvm-sh/nvm/archive/refs/tags/v${ver}.tar.gz"
  store=$(nix store prefetch-file --json --unpack "$url" 2>/dev/null \
    | sed -E 's/.*"storePath":"([^"]+)".*/\1/')
  if [ -z "$store" ] || [ ! -d "$store" ]; then
    fail "real-nvm: could not fetch $url"; return
  fi

  make_sandbox real-nvm
  cp "$store/nvm.sh" "$store/nvm-exec" "$store/bash_completion" "$SANDBOX/store/"
  mkdir -p "$NVM_DIR/versions/node/$PINNED_NODE/bin"
  printf '#!/bin/sh\n' > "$NVM_DIR/versions/node/$PINNED_NODE/bin/node"
  chmod +x "$NVM_DIR/versions/node/$PINNED_NODE/bin/node"
  run_bootstrap >/dev/null
  assert_eq "$RUN_STATUS" "0" "real-nvm: exits 0"

  # The behavioural checks: source what was installed, then drive nvm offline.
  assert_eq \
    "$(NVM_DIR="$NVM_DIR" bash -c '\. "$NVM_DIR/nvm.sh" --no-use >/dev/null && nvm --version' 2>&1)" \
    "$ver" \
    "real-nvm: the installed files yield a working \`nvm\` reporting the pinned version"
  assert_contains \
    "$(NVM_DIR="$NVM_DIR" bash -c '\. "$NVM_DIR/nvm.sh" --no-use >/dev/null && nvm ls' 2>&1)" \
    "$PINNED_NODE" \
    "real-nvm: real nvm sees the pinned Node and the default alias this script set"
  cleanup_sandbox
}

# --- module contract ----------------------------------------------------------
# README.md's PATH contract depends on the flake never declaring Node itself.
# This is the one check that has to read declarations rather than behaviour:
# nothing observable at test time distinguishes "nvm's node" from "a node this
# flake put on PATH" without activating a real system.
test_no_node_declared() {
  local decls
  decls=$(grep -rn -E '^[[:space:]]*(node|npm|npx|corepack|nodejs(_[0-9]+)?)[[:space:]]*$' \
    "$REPO_ROOT/modules" 2>/dev/null)
  if [ -z "$decls" ]; then
    pass "modules: no node/npm/npx/corepack in any package list (nvm keeps ownership)"
  else
    fail "modules: a Node package is declared, which would outrank nvm on PATH: $decls"
  fi
}

scenario_fresh
scenario_idempotent
scenario_node_present
scenario_pin_bump
scenario_install_failure
scenario_retry_after_failure
scenario_respects_user
scenario_takes_over_manual
scenario_real_nvm
test_no_node_declared

echo
if [ "$FAILURES" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "$FAILURES check(s) failed."; exit 1; fi
