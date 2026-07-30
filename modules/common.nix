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

  # `home.sessionPath` entries that must NOT be hoisted above the Nix profile.
  # `~/.yarn/bin` is the yarn-v1 global-binary dir - the same class as the nvm
  # global dir, i.e. somewhere `yarn global add <cli>` can drop a copy of a CLI
  # this flake pins - so it belongs BELOW the profile for exactly the reason nvm
  # does. Excluding it here does not drop it from PATH: home-manager's own
  # session-vars prefix already places it there, below the profile.
  demotedSessionPathDirs = [ "$HOME/.yarn/bin" ];

  # The directories home-manager itself puts at the front of the session PATH,
  # in home-manager's own order: the declared `home.sessionPath` entries (minus
  # the demoted ones above), then the profile that holds every Nix-declared
  # binary. Read from `config` rather than re-listed, so it stays correct when
  # `home.sessionPath` changes and on both surfaces - `home.profileDirectory` is
  # /etc/profiles/per-user/<user> under nix-darwin (`useUserPackages = true`)
  # and ~/.nix-profile under standalone home-manager on Linux/WSL. Re-asserted
  # in the zsh init below.
  managedPathDirs = lib.concatStringsSep " " (map (p: "\"${p}\"")
    (lib.subtractLists demotedSessionPathDirs config.home.sessionPath
      ++ [ "${config.home.profileDirectory}/bin" ]));
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
    # Python/dev toolchain. `gnumake` is here because a stock Ubuntu/WSL distro
    # ships no `make` at all, while macOS gets 3.81 from the Xcode CLT that
    # install.sh already triggers - declaring it keeps both platforms equal.
    # Interpreters stay out: projects pin their own via `uv python install`.
    uv
    gnumake
    pre-commit
    # Signed commits. `commit.gpgsign` is on per-repo, so a missing gpg does not
    # warn - it fails the commit outright ("cannot run gpg"). It was undeclared
    # and got zapped on the first switch to this flake; declaring it here keeps
    # it on both platforms. The pinentry pairs with it: pinentry-mac (brew) on
    # darwin, pinentry-curses (nixpkgs) on Linux.
    gnupg
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

      # ---------------------------------------------------------------------
      # PATH assembly. These four blocks each PREPEND, so the LAST one to run
      # ends up FIRST on PATH. The resulting order is deliberate:
      #
      #   pyenv shims > Homebrew > ~/.local/bin > ~/.cargo/bin > ~/.bun/bin
      #     > Nix profile > nvm > ~/.yarn/bin > system
      #
      # Rationale per block is inline below; the short version is that the Nix
      # profile has to outrank nvm (that is where stray `npm i -g` binaries
      # live) without displacing pyenv's or Homebrew's Python, which is the one
      # place the two goals genuinely conflict. See "PATH precedence" in
      # README.md.
      # ---------------------------------------------------------------------

      # nvm. Runs first, so it ends up BELOW the Nix profile: npm globals
      # installed into the active Node version's bin must never shadow a CLI
      # this flake pins. nvm still owns Node itself - no node/npm/npx/corepack
      # is declared in this flake, so nothing here competes with it, and nvm's
      # own `nvm use` reshuffling continues to work because it rewrites only
      # its own entry.
      export NVM_DIR="$HOME/.nvm"
      [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
      [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

      # Nix profile precedence - MUST run after the nvm block above and before
      # the Homebrew and pyenv blocks below.
      #
      # home-manager builds the session PATH as
      #   <home.sessionPath...>:<profileDirectory>/bin:<system dirs>
      # but every block here prepends to that, which left the profile holding
      # every Nix-declared binary at PATH position 11 - behind pyenv, Homebrew
      # and nvm. The symptom was `lavish-axi` resolving to an npm global
      # instead of the version this flake pins (`tasks-axi` the same).
      #
      # Re-prepending the same dirs, in home-manager's own order, restores the
      # intent: a binary this repo declares beats a stray global install of the
      # same name. Three `home.sessionPath` dirs are re-prepended ahead of the
      # profile, exactly as home-manager orders them, and each is a deliberate
      # exception to "Nix-declared wins":
      #   - `~/.local/bin` holds self-updating agent runtimes that are NOT
      #     Nix-declared and must win (claude, codex, cursor-agent,
      #     no-mistakes, treehouse). Demoting it would invert the risk - a
      #     stale or absent Nix entry could shadow the live runtime, which is
      #     worse than the latent shadowing demotion would prevent.
      #   - `~/.cargo/bin` and `~/.bun/bin`: rustup and bun manage their own
      #     toolchains out of those dirs, so they keep owning
      #     `cargo`/`rustc`/`rustup` and `bun`/`bunx`.
      # `~/.yarn/bin` is NOT an exception - it is a global-install dir like
      # nvm's, so `demotedSessionPathDirs` above keeps it out of this array and
      # it stays below the profile where home-manager already put it.
      #
      # `''${path:|arr}` drops the stale copies instead of duplicating them, so
      # this reorders rather than grows PATH and is idempotent if the rc file
      # gets re-sourced.
      typeset -a _dotnix_managed_path
      _dotnix_managed_path=( ${managedPathDirs} )
      path=( $_dotnix_managed_path ''${path:|_dotnix_managed_path} )
      unset _dotnix_managed_path

      # Homebrew (macOS only) - MUST run before anything that calls `brew`.
      # Apple Silicon -> /opt/homebrew, Intel -> /usr/local. Runtime-guarded, so
      # it is a no-op on Linux/WSL where neither path exists.
      #
      # Deliberately AFTER the block above, i.e. Homebrew still outranks the Nix
      # profile. This is the one spot where "Nix-declared wins" and "do not
      # disturb the Python setup" conflict: the ONLY names present in both
      # /opt/homebrew/bin and the Nix profile are the Python family (`python3`,
      # `pydoc3`, `idle3`, `python3-config`) - Nix pulls a python3 in because
      # modules/agent-tooling/caveman.nix needs one for the caveman-compress
      # scripts. `pyenv global system` resolves through PATH, so hoisting the
      # Nix profile over Homebrew would silently swap the system interpreter.
      # Python belongs to pyenv/uv (see README.md), so Homebrew keeps the edge.
      # Nothing else collides, and Homebrew and nvm are disjoint, so their
      # relative order carries no meaning. If a Nix-declared CLI ever gains a
      # same-named brew, revisit this block rather than the one above.
      if [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      elif [ -x /usr/local/bin/brew ]; then
        eval "$(/usr/local/bin/brew shellenv)"
      fi

      # pyenv (only if actually installed). Runs last of the four, so its shims
      # stay at the very front and pyenv remains the Python version manager.
      export PYENV_ROOT="$HOME/.pyenv"
      [ -d "$PYENV_ROOT/bin" ] && export PATH="$PYENV_ROOT/bin:$PATH"
      command -v pyenv >/dev/null && eval "$(pyenv init -)"

      # bun completions
      [ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

      # direnv - load a directory's .envrc automatically on cd. MUST be last so
      # it wraps the final precmd/chpwd hooks. This is what makes a repo-local
      # .envrc take effect, e.g. a GH_TOKEN that points `gh` at a specific
      # account only inside that folder. direnv itself comes from darwin.nix /
      # linux.nix; a directory still has to be trusted once with `direnv allow`.
      if command -v direnv >/dev/null; then
        eval "$(direnv hook zsh)"
      fi
    '';
  };

  # Dotfiles symlinked from this repo (out-of-store, so edits take effect
  # without a rebuild). Every agent config dir gets the same AGENTS.md + the
  # RULES.md/TOOLING.md/RTK.md it imports, since each @import resolves relative
  # to its own dir.
  home.file = {
    ".config/wezterm".source          = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.config/wezterm";
    ".config/nvim".source             = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.config/nvim";
    # NOTE: do NOT symlink ~/.config/herdr. herdr owns that directory as runtime
    # state - it writes live sockets (herdr.sock, herdr-client.sock) and rotating
    # logs there on every run. A whole-dir mkOutOfStoreSymlink pointed it at a
    # nonexistent files/.config/herdr, leaving a dangling symlink; herdr's startup
    # mkdir() then failed with EEXIST and the server never came up. To version
    # herdr config, symlink only ".config/herdr/config.toml" (a single file),
    # never the directory.
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
