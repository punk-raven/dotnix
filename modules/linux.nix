# Linux + Windows/WSL2 only. Imported solely by homeConfigurations, so it can
# assume Linux. Provides the nixpkgs equivalents of the macOS Homebrew brews
# (Homebrew stays macOS-only in modules/darwin.nix) plus the desktop GUI apps,
# which are skipped on a headless/server install.
{ pkgs, lib, cfg, herdrPkg, ... }:

{
  # GUI apps only on a non-headless box (WSLg / a real desktop). Static import
  # guarded on the per-user `headless` flag from config.nix.
  imports = lib.optionals (!cfg.headless) [ ./gui.nix ];

  # nixpkgs equivalents of the portable macOS Homebrew formulae. macOS-only
  # tools (cocoapods, pinentry-mac, herdr) have no entry here; optional Linux
  # substitutes (pinentry-gtk for pinentry-mac, i3/hyprland for amethyst) can be
  # added later.
  home.packages = with pkgs; [
    # C toolchain. NOT a Homebrew equivalent - it closes a gap that only exists
    # on Linux. install.sh triggers the Xcode Command Line Tools on macOS, which
    # hands that platform clang, ld, and the system headers for free. A stock
    # Ubuntu/WSL distro ships none of it, which breaks declared tools that
    # shell out to a compiler: rustup (rustc uses `cc` as its linker), neovim
    # treesitter (`:TSInstall` compiles each parser), and any npm/pre-commit
    # hook with a native module. Same reasoning as `gnumake` in common.nix.
    gcc
    binutils
    pkg-config

    ffmpeg
    direnv
    gh
    watchman
    act
    opentofu
    ktlint
    autoconf
    bear
    cf-terraforming
    git-filter-repo
    mongodb-tools
    pyenv
    zulu17
    pinentry-curses    # pinentry-mac equivalent (terminal; works headless)

    # Docker CLIENT only - the closest parity with the macOS `docker-desktop`
    # cask that this flake can actually reach. Standalone home-manager runs
    # unprivileged, and the daemon needs root plus an init system, so nothing
    # here can install or start `dockerd`. On WSL2 the daemon lives on the
    # Windows side (Docker Desktop -> Settings -> Resources -> WSL integration,
    # enabled for this distro), which exposes /var/run/docker.sock inside the
    # distro; these binaries then behave exactly like the macOS ones. On a
    # native Linux box the daemon is a root-level concern (`services.docker` on
    # NixOS, distro package elsewhere) and stays outside this module.
    docker-client
    docker-compose
    docker-buildx
  ]
  # herdr from its own flake (macOS gets it via Homebrew instead). The
  # SessionStart hook in the agent configs uses it when present.
  ++ [ herdrPkg ];
}
