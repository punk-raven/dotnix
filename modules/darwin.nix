# macOS-only. Imported solely by darwinConfigurations, so everything here can
# assume darwin. Homebrew (with the `zap` cleanup policy), system.defaults, the
# nix-homebrew integration, and the primary user live here.
{ pkgs, cfg, ... }:

{
  # If you use Determinate Nix Installer (recommended), let it manage Nix itself.
  nix.enable = false;

  nixpkgs.config.allowUnfree = true;

  # nix-homebrew manages the Homebrew installation itself so it stays
  # declarative. autoMigrate adopts the existing /opt/homebrew install on the
  # first switch instead of erroring on it.
  nix-homebrew = {
    enable = true;
    user = cfg.username;
    autoMigrate = true;
  };

  homebrew = {
    enable = true;
    # "zap" removes any brew/cask NOT declared below on every switch. This
    # forces every Homebrew package to be declared here (reproducible machine).
    onActivation.cleanup = "zap";
    # Custom taps must be declared here too. With zap, an undeclared tap is
    # untapped on switch, which fails ("Refusing to untap ...") while any
    # installed formula/cask from that tap remains - so declare the tap AND the
    # package you want to keep.
    taps = [
      "mongodb/brew"
      # Home of the poke-token-bar cask below.
      "chattymin/tap"
    ];
    # With cleanup = "zap", every Homebrew package must be declared here or it
    # gets uninstalled on the next switch. macOS-only tools (cocoapods,
    # pinentry-mac) and GUI casks (amethyst, opensuperwhisper) that have no
    # Linux equivalent stay here rather than in the shared set.
    brews = [
      "autoconf"
      "herdr"
      # dev tooling
      "act"
      # AWS CLI v2. Homebrew ships the vendored single-binary distribution AWS
      # itself supports, and `brew upgrade` tracks upstream releases directly.
      "awscli"
      "bear"
      "cf-terraforming"
      "cocoapods"
      "direnv"
      "ffmpeg"
      "gh"
      "git-filter-repo"
      "ktlint"
      "libb2"
      "mongodb-database-tools"
      "opentofu"
      "pinentry-mac"
      "pyenv"
      "watchman"
    ];
    casks = [
      "wezterm"
      "amethyst"
      # OrbStack (Docker/Linux VM runtime) is in modules/orbstack.nix, not
      # here: the upstream cask is broken on Homebrew 6.
      "opensuperwhisper"
      # Menu-bar token tracker (macOS 14+). Ships only as a cask from its own
      # tap - no nixpkgs derivation and no Linux build - so it stays here rather
      # than in the shared package set. Fully qualified because the cask name
      # alone would resolve against homebrew/cask first.
      "chattymin/tap/poke-token-bar"
      "zulu@17"
    ];
  };

  environment.systemPackages = with pkgs; [
    starship
  ];

  system.primaryUser = cfg.username;
  users.users.${cfg.username} = {
    home = cfg.homeDirectory;
    shell = pkgs.zsh;
  };

  system.defaults = {
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      KeyRepeat = 2;
      InitialKeyRepeat = 15;
      "com.apple.swipescrolldirection" = false;
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSNavPanelExpandedStateForSaveMode = true;
      NSNavPanelExpandedStateForSaveMode2 = true;
      AppleShowAllExtensions = true;
    };

    finder = {
      AppleShowAllExtensions = true;
      ShowPathbar = true;
    };

    trackpad = {
      Clicking = true;
    };
  };

  environment.systemPath = [
    "/run/current-system/sw/bin"
    "/etc/profiles/per-user/${cfg.username}/bin"
  ];

  system.stateVersion = 6;
}
