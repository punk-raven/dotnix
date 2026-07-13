{
  description = "Cross-platform Nix dotfiles (macOS + Linux + Windows/WSL2)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    # herdr - terminal workspace manager for AI coding agents. Cross-platform
    # flake; wired into the Linux/WSL package set (macOS gets it via Homebrew in
    # modules/darwin.nix). Pinned to a release tag; `nix flake update herdr` bumps.
    herdr = {
      url = "github:ogulcancelik/herdr/v0.7.3";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # nixGL - injects a working GL/EGL/Vulkan driver into Nix-built GUI apps on
    # non-NixOS hosts. Needed on Linux/WSL, where a Nix binary (e.g. wezterm)
    # cannot load the host's libEGL and only sees its own closure. macOS never
    # uses it (GUI apps come from Homebrew casks). See modules/gui.nix.
    nixgl = {
      url = "github:nix-community/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, nix-darwin, home-manager, nix-homebrew, herdr, nixgl, ... }:
    let
      # The prompted values + detected system. This is the single source of
      # per-user configuration; every module reads from `cfg` (threaded via
      # specialArgs / extraSpecialArgs) instead of hardcoding anything.
      #
      # config.nix lives OUTSIDE this repo (default
      # ~/.config/dotnix/config.nix, override with $DOTNIX_CONFIG) so a real
      # user's values are never committed to a shared/template checkout. Reading
      # a path outside the flake requires impure evaluation, so every activation
      # command passes `--impure` (see install.sh and the `rebuild` alias in
      # modules/common.nix).
      cfg = import (
        let
          explicit = builtins.getEnv "DOTNIX_CONFIG";
          xdg = builtins.getEnv "XDG_CONFIG_HOME";
          home = builtins.getEnv "HOME";
          base = if xdg != "" then xdg else "${home}/.config";
        in
        if explicit != "" then explicit else "${base}/dotnix/config.nix"
      );
      lib = nixpkgs.lib;
      isDarwin = lib.hasSuffix "darwin" cfg.system;

      pkgsFor = system: import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      # macOS: nix-darwin owns the system; home-manager runs as a darwin module.
      # Only exposed on a darwin `system` so a Linux checkout never tries to
      # evaluate darwinSystem with a Linux system string.
      darwinConfigurations = lib.optionalAttrs isDarwin {
        ${cfg.hostname} = nix-darwin.lib.darwinSystem {
          inherit (cfg) system;
          specialArgs = { inherit cfg; };
          modules = [
            ./modules/darwin.nix
            nix-homebrew.darwinModules.nix-homebrew
            home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "backup";
              home-manager.extraSpecialArgs = { inherit cfg; };
              home-manager.users.${cfg.username} = import ./modules/common.nix;
            }
          ];
        };
      };

      # Linux + Windows/WSL2: standalone home-manager (Nix does not run natively
      # on Windows, so WSL runs this identical Linux path).
      homeConfigurations = lib.optionalAttrs (!isDarwin) {
        ${cfg.username} = home-manager.lib.homeManagerConfiguration {
          pkgs = pkgsFor cfg.system;
          extraSpecialArgs = {
            inherit cfg;
            herdrPkg = herdr.packages.${cfg.system}.default;
            # Mesa GL/EGL wrapper for Nix GUI apps on non-NixOS/WSL. Only
            # referenced on the Linux path, so it is never evaluated on macOS.
            nixglPkg = nixgl.packages.${cfg.system}.nixGLIntel;
          };
          modules = [
            ./modules/common.nix
            ./modules/linux.nix
          ];
        };
      };
    };
}
