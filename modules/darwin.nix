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
      # Docker Desktop. Declared because Homebrew now owns the app - with zap,
      # an undeclared brew-managed cask is uninstalled on the next switch.
      #
      # Do NOT let brew adopt an app it did not install. `brew install --cask
      # --adopt` runs `sudo chmod -R a+rX` over the bundle, which left the
      # signature valid on disk but the launch assessment broken: the Electron
      # GUI died with SIGTRAP in V8 startup while the engine and containers kept
      # running. Only `brew reinstall --cask docker-desktop` (a fresh bundle)
      # fixed it. brew bundle adds `--adopt` by itself for an app that is present
      # but unknown to brew (bundle/cask.rb), so the way to stay safe is to keep
      # brew's view and the disk in agreement - never hand-install over a
      # declared cask.
      #
      # Quarantine is NOT the hazard here: the reinstalled bundle still carries
      # com.apple.quarantine and runs fine. Do not reach for
      # `caskArgs.no_quarantine` - Homebrew 6 dropped the flag, and bundle would
      # pass an option brew rejects, failing the switch.
      "docker-desktop"
      "opensuperwhisper"
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
