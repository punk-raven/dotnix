# Linux + Windows/WSL2 only. Imported solely by homeConfigurations, so it can
# assume Linux. Provides the nixpkgs equivalents of the macOS Homebrew brews
# (Homebrew stays macOS-only in modules/darwin.nix) plus the desktop GUI apps,
# which are skipped on a headless/server install.
{ pkgs, lib, cfg, ... }:

{
  # GUI apps only on a non-headless box (WSLg / a real desktop). Static import
  # guarded on the per-user `headless` flag from config.nix.
  imports = lib.optionals (!cfg.headless) [ ./gui.nix ];

  # nixpkgs equivalents of the portable macOS Homebrew formulae. macOS-only
  # tools (cocoapods, pinentry-mac, herdr) have no entry here; optional Linux
  # substitutes (pinentry-gtk for pinentry-mac, i3/hyprland for amethyst) can be
  # added later.
  home.packages = with pkgs; [
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
    # PostgreSQL 18 with the PostGIS extension (brew `postgresql@18` + `postgis`).
    (postgresql_18.withPackages (ps: [ ps.postgis ]))
  ];
}
