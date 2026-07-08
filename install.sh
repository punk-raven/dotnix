#!/bin/sh
#
# Cross-platform installer: macOS, Linux, and inside-WSL all run this one
# script. It ensures prerequisites, installs Nix (Determinate) if absent, clones
# or updates this repo, prompts for the per-user values, writes config.nix, and
# activates - via nix-darwin on macOS, standalone home-manager on Linux/WSL.
#
# One-liner (macOS / Linux / inside a WSL distro):
#   curl -fsSL https://raw.githubusercontent.com/allanjeo/dotfiles/main/install.sh | sh
#
# Designed to complete in a single pass on a fresh machine: right after
# installing Nix it sources the daemon profile into the current shell, so `nix`
# is usable for the rest of the run without a re-login.
#
# NEVER run this for real in CI or a dev checkout: it mutates the host (installs
# Nix, activates a system). All validation goes through tests/install_test.sh.
#
# Overridable env vars (defaults are the real values; the test harness points
# them at a sandbox):
#   REPO_URL            git URL to clone          (default: the public https repo)
#   DOTFILES_DIR        clone destination         (default: ~/dotfiles)
#   DOTFILES_BRANCH     branch to clone           (default: main)
#   NIX_DAEMON_PROFILE  daemon profile to source  (default: the real one)
#   DARWIN_REBUILD_BIN  darwin-rebuild path       (default: the real one)
#   DOTFILES_NONINTERACTIVE  set to 1 to accept every default with no prompt
#   DOTFILES_HEADLESS   true|false, skip GUI apps on Linux/WSL (default: false)
#   DOTNIX_CONFIG       path to the per-user config.nix, kept OUTSIDE the repo so
#                       it is never committed (default: ~/.config/dotnix/config.nix)
#   GIT_WAIT_TIMEOUT    seconds to wait for git   (default: 1800, macOS CLT)
#   GIT_WAIT_INTERVAL   git poll interval seconds (default: 5)

set -eu

: "${REPO_URL:=https://github.com/allanjeo/dotfiles.git}"
: "${DOTFILES_DIR:=$HOME/dotfiles}"
: "${DOTFILES_BRANCH:=main}"
: "${NIX_DAEMON_PROFILE:=/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh}"
: "${DARWIN_REBUILD_BIN:=/run/current-system/sw/bin/darwin-rebuild}"
: "${DOTFILES_HEADLESS:=false}"
: "${GIT_WAIT_TIMEOUT:=1800}"
: "${GIT_WAIT_INTERVAL:=5}"
# Per-user config lives outside the flake's git tree so it is never committed to
# a shared/template repo. The flake reads it impurely via this path (flake.nix).
: "${DOTNIX_CONFIG:=${XDG_CONFIG_HOME:-$HOME/.config}/dotnix/config.nix}"

OS=$(uname -s)

# 1. Ensure git + curl. On a bare Mac, git ships with the Xcode Command Line
#    Tools, gated behind a one-time GUI installer; trigger it and wait. On Linux
#    they are almost always preinstalled - if not, print the fix and stop.
ensure_prereqs() {
  if command -v curl >/dev/null 2>&1 && command -v git >/dev/null 2>&1; then
    return 0
  fi
  if [ "$OS" = "Darwin" ]; then
    if ! command -v git >/dev/null 2>&1; then
      echo "git not found - requesting Xcode Command Line Tools."
      echo "A GUI installer will open; click through it to continue."
      xcode-select --install || true
      _waited=0
      until command -v git >/dev/null 2>&1; do
        if [ "$_waited" -ge "$GIT_WAIT_TIMEOUT" ]; then
          echo "git is still unavailable after ${GIT_WAIT_TIMEOUT}s. Finish the" >&2
          echo "Command Line Tools install, then re-run this script." >&2
          exit 1
        fi
        sleep "$GIT_WAIT_INTERVAL"
        _waited=$((_waited + GIT_WAIT_INTERVAL))
      done
    fi
  else
    echo "git and/or curl are missing. Install them with your distro package" >&2
    echo "manager first, e.g.:" >&2
    echo "  Debian/Ubuntu: sudo apt-get install -y git curl" >&2
    echo "  Fedora:        sudo dnf install -y git curl" >&2
    echo "  Arch:          sudo pacman -S --noconfirm git curl" >&2
    exit 1
  fi
}

# 2. Install Nix via the Determinate installer if missing, then source the
#    daemon profile so `nix` works for the rest of THIS run (no second shell).
ensure_nix() {
  if command -v nix >/dev/null 2>&1; then
    return 0
  fi
  echo "Installing Nix (Determinate)..."
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
  # The profile script isn't written to be `set -u` safe; relax just around it.
  if [ -f "$NIX_DAEMON_PROFILE" ]; then
    set +u
    # shellcheck disable=SC1090
    . "$NIX_DAEMON_PROFILE"
    set -u
  fi
}

# 3. Clone the repo to DOTFILES_DIR, or fast-forward it if already present.
clone_or_update() {
  if [ -d "$DOTFILES_DIR/.git" ]; then
    echo "Repo already present at $DOTFILES_DIR - updating..."
    git -C "$DOTFILES_DIR" pull --ff-only ||
      echo "warning: could not fast-forward $DOTFILES_DIR (local changes?); continuing."
  else
    echo "Cloning $REPO_URL -> $DOTFILES_DIR ..."
    mkdir -p "$(dirname "$DOTFILES_DIR")"
    git clone --branch "$DOTFILES_BRANCH" "$REPO_URL" "$DOTFILES_DIR"
  fi
}

# 4. Prompt for the per-user values (pre-filled from an existing config.nix on a
#    re-run) and write config.nix OUTSIDE the repo (see DOTNIX_CONFIG), so the
#    flake reads it impurely and it is never committed to a shared checkout.
generate_config() {
  . "$DOTFILES_DIR/lib/prompt.sh"

  _system=$(detect_system)
  _cfg="$DOTNIX_CONFIG"
  mkdir -p "$(dirname "$_cfg")"

  # Resolve defaults, preferring an existing config.nix value, else auto-detect.
  _def_user=$(config_value "$_cfg" username); [ -n "$_def_user" ] || _def_user=$(id -un)
  _def_home=$(config_value "$_cfg" homeDirectory); [ -n "$_def_home" ] || _def_home="$HOME"
  _def_name=$(config_value "$_cfg" gitName); [ -n "$_def_name" ] || _def_name=$(git config --global user.name 2>/dev/null || echo "")
  _def_email=$(config_value "$_cfg" gitEmail); [ -n "$_def_email" ] || _def_email=$(git config --global user.email 2>/dev/null || echo "")
  _def_host=$(config_value "$_cfg" hostname); [ -n "$_def_host" ] || _def_host=$(hostname 2>/dev/null | cut -d. -f1); [ -n "$_def_host" ] || _def_host="mac"

  _username=$(prompt_default "Username" "$_def_user")
  _homedir=$(prompt_default "Home directory" "$_def_home")
  _gitname=$(prompt_default "Git user.name" "$_def_name")
  _gitemail=$(prompt_default "Git email" "$_def_email")

  write_config "$_cfg" \
    "$_username" "$_homedir" "$DOTFILES_DIR" \
    "$_gitname" "$_gitemail" "$_system" "$_def_host" "$DOTFILES_HEADLESS"

  echo "Wrote $_cfg (outside the repo; the flake reads it via \$DOTNIX_CONFIG)"
  SYSTEM="$_system"
  HOSTNAME="$_def_host"
  USERNAME="$_username"
}

# 5. Activate. macOS -> nix-darwin; Linux/WSL -> standalone home-manager.
activate() {
  # config.nix lives outside the flake, so every activation evaluates `--impure`
  # and must see $DOTNIX_CONFIG. On macOS the rebuild runs under sudo, which
  # scrubs the environment, so pass the var explicitly through `sudo env`.
  if [ "$OS" = "Darwin" ]; then
    if [ -x "$DARWIN_REBUILD_BIN" ]; then
      sudo env DOTNIX_CONFIG="$DOTNIX_CONFIG" \
        "$DARWIN_REBUILD_BIN" switch --impure --flake "$DOTFILES_DIR#$HOSTNAME"
    else
      # First activation: darwin-rebuild doesn't exist yet, fetch it via nix run.
      # Resolve nix by absolute path (sudo won't inherit the sourced PATH) and
      # enable the experimental features it needs.
      _nix=$(command -v nix || echo /nix/var/nix/profiles/default/bin/nix)
      sudo env DOTNIX_CONFIG="$DOTNIX_CONFIG" \
        "$_nix" --extra-experimental-features "nix-command flakes" \
        run nix-darwin/master#darwin-rebuild -- switch --impure --flake "$DOTFILES_DIR#$HOSTNAME"
    fi
  else
    # Standalone home-manager. `-b backup` renames any pre-existing plain file it
    # would replace, matching the darwin module's backupFileExtension.
    _nix=$(command -v nix || echo /nix/var/nix/profiles/default/bin/nix)
    DOTNIX_CONFIG="$DOTNIX_CONFIG" "$_nix" --extra-experimental-features "nix-command flakes" \
      run github:nix-community/home-manager -- switch -b backup --impure --flake "$DOTFILES_DIR#$USERNAME"
  fi
}

ensure_prereqs
ensure_nix
clone_or_update
generate_config
activate

cat <<EOF

Done.

To activate Nix in THIS shell (a fresh install isn't on the PATH of the shell
that started before Nix existed), run:

  . $NIX_DAEMON_PROFILE

Or just open a new terminal. After that, 'nix', your packages, and the 'rebuild'
alias are available; use 'rebuild' to apply later config edits.
EOF
