#!/bin/bash
#
# Regression test for install.sh (and a smoke check of install.ps1's hand-off
# contract).
#
# install.sh installs Nix and activates a real system, so it can never run for
# real in CI or a dev checkout. This test runs the actual script with PATH
# masked down to a directory of stub executables (curl, sh, nix, darwin-rebuild,
# sudo, git, xcode-select, uname) that simulate each OS: they record every
# invocation to a log and fake just enough state (a daemon profile, a `nix`
# binary, a cloned repo) for the script's own logic to progress - without ever
# touching the real network, Nix store, Homebrew, sudo, or system state. Every
# intentional write is guarded against escaping the per-scenario temp sandbox.
#
# Scenarios:
#   macos-fresh      fresh Mac  -> Determinate install + nix-darwin first activation
#   macos-installed  set-up Mac -> darwin-rebuild fast path, repo update (no clone)
#   linux-fresh      fresh Linux-> Determinate install + home-manager activation
#   no-git           bare Mac, git unprovisionable -> exits before activation
#
# Run: bash tests/install_test.sh

set -euo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &> /dev/null && pwd)
# Resolved before PATH gets masked, so the runner always invokes the real shell
# on the script under test, never the stub `sh` that simulates the Determinate pipe.
REAL_SH=$(command -v bash)

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
assert_line_count() {
  local haystack="$1" pattern="$2" expected="$3" msg="$4" actual
  actual=$(grep -cE -- "^$pattern" <<<"$haystack" || true)
  if [ "$actual" -eq "$expected" ]; then pass "$msg"; else
    fail "$msg -- expected $expected line(s) matching '^$pattern', got $actual"; fi
}
assert_file_contains() {
  local file="$1" needle="$2" msg="$3"
  if [ -f "$file" ] && grep -qF -- "$needle" "$file"; then pass "$msg"; else
    fail "$msg -- expected $file to contain: $needle"; fi
}

# --- sandbox write guard (refuses any write escaping the temp sandbox) ---------
sandbox_guard_violation() {
  echo "HERMETIC VIOLATION: refusing to write outside sandbox: $1 (sandbox: ${2:-unknown})" >&2
  exit 1
}
guard_write_path() {
  local target="$1" abs_sandbox current raw_path component resolved
  local -a components
  [ -n "${SANDBOX_ROOT:-}" ] || { echo "HERMETIC VIOLATION: SANDBOX_ROOT unset ($target)" >&2; exit 1; }
  [ -n "$target" ] || sandbox_guard_violation "$target"
  abs_sandbox=$(cd "$SANDBOX_ROOT" && pwd -P) || sandbox_guard_violation "$target" "${SANDBOX_ROOT:-unknown}"
  case "$target" in
    /*) current="/"; raw_path="${target#/}" ;;
    *)  current=$(pwd -P); raw_path="$target" ;;
  esac
  IFS="/" read -r -a components <<< "$raw_path"
  for component in "${components[@]}"; do
    case "$component" in
      "" | ".") continue ;;
      "..") if [ "$current" != "/" ]; then current="${current%/*}"; [ -n "$current" ] || current="/"; fi ;;
      *) if [ "$current" = "/" ]; then current="/$component"; else current="$current/$component"; fi ;;
    esac
    if [ -d "$current" ]; then resolved=$(cd "$current" && pwd -P); current="$resolved"; fi
  done
  [ -L "$current" ] && sandbox_guard_violation "$target" "$abs_sandbox"
  case "$current" in "$abs_sandbox" | "$abs_sandbox"/*) return 0 ;; esac
  sandbox_guard_violation "$target" "$abs_sandbox"
}
assert_path_under_sandbox() { guard_write_path "$1"; }
write_sandbox_guard() {
  local guard_path="$1"
  guard_write_path "$guard_path"
  { declare -f sandbox_guard_violation; declare -f guard_write_path; } > "$guard_path"
}
write_stub() {
  local path="$1"
  assert_path_under_sandbox "$path"
  mkdir -p "$(dirname "$path")"
  cat > "$path"; chmod +x "$path"
}

# Copy the repo into a scratch dir to act as the "remote" the git stub clones.
make_fixture_repo() {
  local dest="$1"
  cp -R "$REPO_ROOT/." "$dest"
  rm -rf "$dest/.git"
}

# Stubs shared by every scenario. Each only records its invocation and fakes the
# minimum side effect install.sh depends on.
write_shared_stubs() {
  local stub_bin="$1"

  write_stub "$stub_bin/uname" <<'EOF'
#!/bin/bash
set -euo pipefail
case "${1:-}" in
  -s) echo "$STUB_UNAME_S" ;;
  -m) echo "$STUB_UNAME_M" ;;
  -sm|-ms) echo "$STUB_UNAME_S $STUB_UNAME_M" ;;
  *) echo "$STUB_UNAME_S" ;;
esac
EOF

  write_stub "$stub_bin/curl" <<'EOF'
#!/bin/bash
set -euo pipefail
. "${SANDBOX_GUARD:?}" || exit 1
guard_write_path "$STUB_LOG"
echo "curl $*" >> "$STUB_LOG"
url=""
for a in "$@"; do case "$a" in http*) url="$a" ;; esac; done
case "$url" in
  https://install.determinate.systems/nix) echo ": stub determinate installer payload" ;;
  https://install.determinate.sh/nix) echo "wrong determinate domain: $url" >&2; exit 1 ;;
  *) echo ": stub curl payload for $url" ;;
esac
EOF

  # Determinate installer: drops a daemon profile + a discoverable `nix`.
  write_stub "$stub_bin/sh" <<'EOF'
#!/bin/bash
set -euo pipefail
. "${SANDBOX_GUARD:?}" || exit 1
guard_write_path "$STUB_LOG"
echo "sh $*" >> "$STUB_LOG"
cat >/dev/null
guard_write_path "$NIX_DAEMON_PROFILE"
guard_write_path "$STUB_NIX_BIN_DIR"
mkdir -p "$(dirname "$NIX_DAEMON_PROFILE")" "$STUB_NIX_BIN_DIR"
guard_write_path "$STUB_NIX_BIN_DIR/nix"
cat > "$STUB_NIX_BIN_DIR/nix" <<'NIXBIN'
#!/bin/bash
set -euo pipefail
. "${SANDBOX_GUARD:?}" || exit 1
guard_write_path "$STUB_LOG"
echo "nix $*" >> "$STUB_LOG"
exit 0
NIXBIN
chmod +x "$STUB_NIX_BIN_DIR/nix"
cat > "$NIX_DAEMON_PROFILE" <<PROFILE
export PATH="$STUB_NIX_BIN_DIR:\$PATH"
PROFILE
EOF

  write_stub "$stub_bin/sudo" <<'EOF'
#!/bin/bash
set -euo pipefail
. "${SANDBOX_GUARD:?}" || exit 1
guard_write_path "$STUB_LOG"
echo "sudo $*" >> "$STUB_LOG"
exec "$@"
EOF

  write_stub "$stub_bin/xcode-select" <<'EOF'
#!/bin/bash
set -euo pipefail
. "${SANDBOX_GUARD:?}" || exit 1
guard_write_path "$STUB_LOG"
echo "xcode-select $*" >> "$STUB_LOG"
exit 0
EOF

  # git stub: logs every call; `clone` fakes the checkout by copying the fixture
  # repo (so lib/prompt.sh is present for install.sh to source) into the dest.
  write_stub "$stub_bin/git" <<'EOF'
#!/bin/bash
set -euo pipefail
. "${SANDBOX_GUARD:?}" || exit 1
guard_write_path "$STUB_LOG"
echo "git $*" >> "$STUB_LOG"
if [ "${1:-}" = "clone" ]; then
  dest="${@: -1}"
  guard_write_path "$dest"
  mkdir -p "$dest"
  cp -R "$FIXTURE_REPO/." "$dest/"
  mkdir -p "$dest/.git"
fi
exit 0
EOF
}

run_scenario() {
  local name="$1"
  local sandbox stub_bin fixture home_dir log dotfiles
  sandbox=$(mktemp -d "${TMPDIR:-/tmp}/install-test-${name}.XXXXXX")
  if [ -z "${DEBUG_KEEP_SANDBOX:-}" ]; then trap 'rm -rf "$sandbox"' RETURN
  else echo "DEBUG: keeping sandbox $sandbox" >&2; fi

  stub_bin="$sandbox/stub-bin"
  fixture="$sandbox/fixture-repo"
  home_dir="$sandbox/home"
  log="$sandbox/log"
  dotfiles="$home_dir/dotfiles"

  mkdir -p "$stub_bin" "$home_dir"
  export SANDBOX_ROOT="$sandbox"
  write_sandbox_guard "$sandbox/sandbox-guard.sh"
  export SANDBOX_GUARD="$sandbox/sandbox-guard.sh"
  assert_path_under_sandbox "$log"; : > "$log"
  make_fixture_repo "$fixture"
  write_shared_stubs "$stub_bin"

  export STUB_LOG="$log"
  export FIXTURE_REPO="$fixture"
  export STUB_NIX_BIN_DIR="$sandbox/fake-nix/var/nix/profiles/default/bin"
  export NIX_DAEMON_PROFILE="$sandbox/fake-nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
  export HOME="$home_dir"
  export DOTFILES_DIR="$dotfiles"
  export REPO_URL="https://example.invalid/dotfiles.git"
  export DOTFILES_BRANCH="main"
  export DOTFILES_NONINTERACTIVE=1
  export DARWIN_REBUILD_BIN="$sandbox/current-system/sw/bin/darwin-rebuild"

  case "$name" in
    macos-*) export STUB_UNAME_S="Darwin"; export STUB_UNAME_M="arm64" ;;
    linux-*|no-git) export STUB_UNAME_S="Linux"; export STUB_UNAME_M="x86_64" ;;
  esac
  # no-git runs on a Mac (CLT path); override OS back to Darwin.
  [ "$name" = "no-git" ] && { export STUB_UNAME_S="Darwin"; export STUB_UNAME_M="arm64"; }

  if [ "$name" = "macos-installed" ]; then
    # Already bootstrapped: nix + darwin-rebuild resolvable, repo already cloned.
    write_stub "$stub_bin/nix" <<'EOF'
#!/bin/bash
set -euo pipefail
. "${SANDBOX_GUARD:?}" || exit 1
guard_write_path "$STUB_LOG"
echo "nix $*" >> "$STUB_LOG"
exit 0
EOF
    write_stub "$DARWIN_REBUILD_BIN" <<'EOF'
#!/bin/bash
set -euo pipefail
. "${SANDBOX_GUARD:?}" || exit 1
guard_write_path "$STUB_LOG"
echo "darwin-rebuild $*" >> "$STUB_LOG"
exit 0
EOF
    guard_write_path "$dotfiles"; mkdir -p "$dotfiles"
    cp -R "$fixture/." "$dotfiles/"; mkdir -p "$dotfiles/.git"
  fi

  local path_for_run="$stub_bin:/usr/bin:/bin:/usr/sbin:/sbin"
  if [ "$name" = "no-git" ]; then
    rm -f "$stub_bin/git"; export GIT_WAIT_TIMEOUT=0; path_for_run="$stub_bin"
  fi

  local out status invocations
  set +e
  out=$(env -u BASH_ENV -u ENV PATH="$path_for_run" "$REAL_SH" "$fixture/install.sh" 2>&1)
  status=$?
  set -e
  invocations=$(cat "$log")

  case "$name" in
    macos-fresh)
      [ "$status" -eq 0 ] && pass "$name: completed in a single pass" || { fail "$name: exited $status: $out"; return; }
      assert_contains "$invocations" "curl --proto =https --tlsv1.2 -sSf -L https://install.determinate.systems/nix" "$name: canonical Determinate URL requested"
      assert_not_contains "$invocations" "install.determinate.sh" "$name: wrong .sh domain never requested"
      assert_contains "$invocations" "sh -s -- install" "$name: installer invoked"
      assert_contains "$invocations" "git clone --branch main https://example.invalid/dotfiles.git $dotfiles" "$name: clones repo to DOTFILES_DIR"
      assert_line_count "$invocations" "nix .*run nix-darwin/master#darwin-rebuild -- switch" 1 "$name: first-activation ran exactly once"
      assert_contains "$invocations" "extra-experimental-features nix-command flakes" "$name: experimental features enabled"
      assert_not_contains "$invocations" "darwin-rebuild switch --flake" "$name: fast path not used"
      assert_contains "$invocations" "git -C $dotfiles add -f config.nix" "$name: force-adds config.nix"
      assert_file_contains "$dotfiles/config.nix" 'system        = "aarch64-darwin";' "$name: config.nix has detected darwin system"
      ;;
    macos-installed)
      [ "$status" -eq 0 ] && pass "$name: completed in a single pass" || { fail "$name: exited $status: $out"; return; }
      assert_not_contains "$invocations" "install.determinate" "$name: installer never runs when nix present"
      assert_contains "$invocations" "git -C $dotfiles pull --ff-only" "$name: updates existing checkout"
      assert_not_contains "$invocations" "git clone" "$name: does not re-clone"
      assert_line_count "$invocations" "sudo .*darwin-rebuild switch --flake" 1 "$name: fast path ran exactly once"
      assert_not_contains "$invocations" "run nix-darwin/master#darwin-rebuild" "$name: first-activation path not used"
      ;;
    linux-fresh)
      [ "$status" -eq 0 ] && pass "$name: completed in a single pass" || { fail "$name: exited $status: $out"; return; }
      assert_contains "$invocations" "sh -s -- install" "$name: installer invoked"
      assert_contains "$invocations" "run github:nix-community/home-manager -- switch -b backup --flake $dotfiles#" "$name: home-manager activation invoked"
      assert_not_contains "$invocations" "darwin-rebuild" "$name: never touches darwin-rebuild"
      assert_file_contains "$dotfiles/config.nix" 'system        = "x86_64-linux";' "$name: config.nix has detected linux system"
      ;;
    no-git)
      [ "$status" -ne 0 ] && pass "$name: exits non-zero when git cannot be provisioned" || fail "$name: expected non-zero, got 0: $out"
      assert_contains "$invocations" "xcode-select --install" "$name: requests Command Line Tools"
      assert_not_contains "$invocations" "darwin-rebuild" "$name: never reaches activation without git"
      ;;
  esac
}

# install.ps1 contract: it must delegate ALL package logic to install.sh and
# never run Nix itself. A static check keeps Windows and Linux from diverging.
test_ps1_handoff() {
  local ps1="$REPO_ROOT/install.ps1"
  local body; body=$(cat "$ps1")
  assert_contains "$body" "install.sh" "install.ps1: hands off to install.sh"
  assert_contains "$body" "wsl.exe --install" "install.ps1: installs WSL2"
  assert_not_contains "$body" "determinate.systems" "install.ps1: does not install Nix itself"
}

run_scenario "macos-fresh"
run_scenario "macos-installed"
run_scenario "linux-fresh"
run_scenario "no-git"
test_ps1_handoff

echo
if [ "$FAILURES" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "$FAILURES check(s) failed."; exit 1; fi
