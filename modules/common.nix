# SHARED across macOS, Linux, and Windows/WSL2. Everything cross-platform -
# the CLI package set, fonts, git/zsh/starship, session vars, agent tooling,
# and the dotfile symlinks - lives here and is imported on every platform.
# Anything platform-bound lives in modules/darwin.nix or modules/linux.nix.
#
# Reads per-user values from `cfg` (config.nix, threaded via specialArgs); it
# hardcodes no username or path.
{ config, pkgs, lib, cfg, ... }:

let
  dotfilesDir = cfg.dotfilesDir;

  # Per-user config.nix lives outside the flake (see flake.nix), so `rebuild`
  # evaluates `--impure` and points $DOTNIX_CONFIG at the real file. On macOS the
  # rebuild runs under sudo, which scrubs the environment, so the var is passed
  # through `sudo env`.
  configPath = "${cfg.homeDirectory}/.config/dotnix/config.nix";

  # `rebuild` re-applies the config. The command differs per platform: macOS
  # goes through nix-darwin, Linux/WSL through standalone home-manager.
  rebuildAlias =
    if pkgs.stdenv.isDarwin then
      "sudo env DOTNIX_CONFIG=${configPath} /run/current-system/sw/bin/darwin-rebuild switch --impure --flake ${dotfilesDir}#${cfg.hostname}"
    else
      "DOTNIX_CONFIG=${configPath} home-manager switch --impure --flake ${dotfilesDir}#${cfg.username}";
in
{
  imports = [
    ./agent-tooling/axi.nix
    ./agent-tooling/rtk.nix
    ./agent-tooling/caveman.nix
    ./agent-tooling/ccusage.nix
    ./agent-tooling/codegraph.nix
  ];

  home.username = cfg.username;
  home.homeDirectory = cfg.homeDirectory;
  home.stateVersion = "23.11";
  home.language.base = "en_US.UTF-8";
  home.sessionPath = [
    "$HOME/.local/bin"    # native Claude Code + other manual/native installs
    "$HOME/.cargo/bin"    # rust / cargo
    "$HOME/.bun/bin"      # bun
    "$HOME/.yarn/bin"     # yarn global binaries
  ];

  # One shared CLI environment on every platform.
  home.packages = with pkgs; [
    git
    curl
    wget
    jq
    fd
    fzf
    fastfetch
    neovim
    ripgrep
    lazygit
    tree
    bun
    rustup
    zip
    unzip
    # Fonts (rendered via fonts.fontconfig on Linux; picked up by the system
    # font path on macOS).
    nerd-fonts.hack
    roboto
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    font-awesome
  ]
  # `killall` is a system builtin on macOS; in nixpkgs it only exists as a
  # Linux package, so only add it there.
  ++ lib.optionals pkgs.stdenv.isLinux [ killall ];

  fonts.fontconfig.enable = true;

  # Skip building the Home Manager options manual/manpages. With flake
  # `useGlobalPkgs = true`, that options.json doc build embeds the nixpkgs
  # source tree path as a bare string (for "Declared in" links), which triggers
  # the "references the store path ... -source without a proper context"
  # warning on every switch. We don't read `man home-configuration.nix`, so turn
  # it off: kills the warning and speeds up the build.
  manual.manpages.enable = false;

  home.sessionVariables = {
    EDITOR = "nvim";
  };

  # Install the standalone `home-manager` CLI on Linux/WSL, where `rebuild`
  # invokes it directly. macOS goes through `darwin-rebuild` (provided by
  # nix-darwin), which already owns the home-manager generation, so enabling
  # the standalone CLI there would be redundant and can conflict.
  programs.home-manager.enable = pkgs.stdenv.isLinux;

  programs.git = {
    enable = true;
    lfs.enable = true;
    signing.format = null;
    settings = {
      user = {
        name = cfg.gitName;
        email = cfg.gitEmail;
      };
      core.editor = "nvim";
      color.ui = true;
      push.autoSetupRemote = true;
      pull.rebase = true;
      rebase.updateRefs = true;
    };
  };

  programs.starship = {
    enable = true;
    settings = {
      command_timeout = 1000;
      add_newline = false;
      format = "$username$hostname$directory$git_branch$git_state$git_status$cmd_duration$line_break$character";

      directory.style = "blue";

      character = {
        success_symbol = "[❯](purple)";
        error_symbol = "[❯](red)";
        vimcmd_symbol = "[❮](green)";
      };

      git_branch = {
        format = "[$branch]($style)";
        style = "bright-black";
      };

      git_status = {
        format = "[[(*$conflicted$untracked$modified$staged$renamed$deleted)](218) ($ahead_behind$stashed)]($style)";
        style = "cyan";
        stashed = "≡";
      };

      git_state = {
        format = "\\([$state( $progress_current/$progress_total)]($style)\\) ";
        style = "bright-black";
      };

      cmd_duration = {
        format = "[$duration]($style) ";
        style = "yellow";
      };

      python = {
        format = "[$virtualenv]($style) ";
        style = "bright-black";
      };
    };
  };

  programs.zsh = {
    enable = true;
    oh-my-zsh = {
      enable = true;
      plugins = [ "git" ];
    };
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    shellAliases = {
      ".." = "cd ..";
      cc = "claude --dangerously-skip-permissions";
      co = "codex --full-auto";
      m = "git switch main";
      mst = "git switch master";
      pull = "git pull";
      push = "git push";
      pushf = "git push --force";
      add = "git add .";
      amend = "git commit --amend";
      reset = "git reset --soft HEAD^";
      rebasem = "git rebase -i main";
      rebasemst = "git rebase -i master";
      rebuild = rebuildAlias;
    } // lib.optionalAttrs pkgs.stdenv.isDarwin {
      # On-demand Homebrew upgrade (macOS only). `darwin-rebuild switch` only
      # installs missing declared packages; run this when you actually want to
      # bump already-installed brews/casks. Zap means only the declared set is
      # present, so this never touches anything outside modules/darwin.nix.
      brewup = "brew update && brew upgrade";
    };
    initContent = ''
      bindkey '^f' autosuggest-accept

      # With `nix.enable = false` (Determinate Nix), nix-darwin owns /etc/zshrc
      # but won't source the Nix daemon profile, so `nix` isn't on PATH in
      # interactive shells. Source it ourselves to close that gap. (Harmless on
      # Linux/WSL, where the profile lives at the same path.)
      if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
      fi

      # Homebrew (macOS only) - MUST run before anything that calls `brew`.
      # Apple Silicon -> /opt/homebrew, Intel -> /usr/local. Runtime-guarded, so
      # it is a no-op on Linux/WSL where neither path exists.
      if [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      elif [ -x /usr/local/bin/brew ]; then
        eval "$(/usr/local/bin/brew shellenv)"
      fi

      # nvm
      export NVM_DIR="$HOME/.nvm"
      [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
      [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

      # pyenv (only if actually installed)
      export PYENV_ROOT="$HOME/.pyenv"
      [ -d "$PYENV_ROOT/bin" ] && export PATH="$PYENV_ROOT/bin:$PATH"
      command -v pyenv >/dev/null && eval "$(pyenv init -)"

      # bun completions
      [ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"
    '';
  };

  # Dotfiles symlinked from this repo (out-of-store, so edits take effect
  # without a rebuild). Every agent config dir gets the same AGENTS.md + the
  # RULES.md/TOOLING.md/RTK.md it imports, since each @import resolves relative
  # to its own dir.
  home.file = {
    ".config/wezterm".source          = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.config/wezterm";
    ".config/nvim".source             = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.config/nvim";
    "AGENTS.md".source                = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/AGENTS.md";
    ".claude/CLAUDE.md".source        = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/AGENTS.md";
    ".claude/RULES.md".source         = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/RULES.md";
    ".claude/TOOLING.md".source       = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/TOOLING.md";
    ".claude/settings.json".source    = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.claude/settings.json";
    ".codex/AGENTS.md".source         = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/AGENTS.md";
    ".codex/RULES.md".source          = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/RULES.md";
    ".codex/TOOLING.md".source        = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/TOOLING.md";
    ".codex/hooks.json".source        = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.codex/hooks.json";
    ".codex/config.toml".source       = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.codex/config.toml";
    ".config/opencode/AGENTS.md".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/AGENTS.md";
    ".config/opencode/RULES.md".source  = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/RULES.md";
    ".config/opencode/TOOLING.md".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/TOOLING.md";
  };
}
