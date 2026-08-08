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
      "DOTNIX_CONFIG=${configPath} home-manager switch -b backup --impure --flake ${dotfilesDir}#${cfg.username}";

  # `home.sessionPath` entries that must NOT be hoisted above the Nix profile.
  # Both are global-install dirs - somewhere `npm i -g` or `yarn global add
  # <cli>` can drop a copy of a CLI this flake pins - so both belong BELOW the
  # profile. `dotnix.nvm.nodeBinDir` is the pinned Node's bin dir, published by
  # modules/nvm.nix so the version lives in one place; `~/.yarn/bin` is the
  # yarn-v1 equivalent. Excluding them here does not drop them from PATH:
  # home-manager's own session-vars prefix already places them there, and the
  # re-prepend below then moves the profile in front of them.
  demotedSessionPathDirs = [ config.dotnix.nvm.nodeBinDir "$HOME/.yarn/bin" ];

  # The directories home-manager itself puts at the front of the session PATH,
  # in home-manager's own order: the declared `home.sessionPath` entries (minus
  # the demoted ones above), then the profile that holds every Nix-declared
  # binary. Read from `config` rather than re-listed, so it stays correct when
  # `home.sessionPath` changes and on both surfaces - `home.profileDirectory` is
  # /etc/profiles/per-user/<user> under nix-darwin (`useUserPackages = true`)
  # and ~/.nix-profile under standalone home-manager on Linux/WSL. Re-asserted
  # in .zshenv and in the zsh init below.
  managedPathDirs = lib.concatStringsSep " " (map (p: "\"${p}\"")
    (lib.subtractLists demotedSessionPathDirs config.home.sessionPath
      ++ [ "${config.home.profileDirectory}/bin" ]));

  # The re-prepend itself, shared by .zshenv and .zshrc so the two can never
  # drift. `''${path:|arr}` drops the stale copies instead of duplicating them,
  # so this reorders rather than grows PATH and is idempotent if the file it
  # sits in gets re-sourced.
  managedPathReassert = lib.removeSuffix "\n" ''
    typeset -a _dotnix_managed_path
    _dotnix_managed_path=( ${managedPathDirs} )
    path=( $_dotnix_managed_path ''${path:|_dotnix_managed_path} )
    unset _dotnix_managed_path
  '';

  # Nix's `''` strings strip only the LITERAL parts' common indentation, so an
  # interpolated multi-line block lands flush against the interpolation point
  # and every later line at column 0. This re-indents one so the generated file
  # stays readable when the block sits inside an `if`.
  indentBlock = prefix: block:
    lib.concatMapStringsSep "\n" (l: if l == "" then l else prefix + l)
      (lib.splitString "\n" (lib.removeSuffix "\n" block));

  # Set once .zshrc has finished assembling PATH, and read by .zshenv. See the
  # comment on `envExtra` below for what it guards against.
  pathAssembledMarker = "__DOTNIX_PATH_ASSEMBLED";

  # Opening line of the `envExtra` block below. A real comment in the generated
  # .zshenv, so it costs nothing at runtime, and unique, so the check below can
  # locate the block by it.
  envExtraMarker = "# dotnix: PATH precedence for non-interactive shells";

  # home-manager assembles .zshenv from several fragments, and `envExtra`
  # currently lands AFTER the one that sources hm-session-vars.sh - the fragment
  # that exports `home.sessionPath` in front of everything. That is the only
  # order in which re-prepending the profile can work, and nothing in
  # home-manager's API promises it, so assert it rather than trust it: were a
  # home-manager bump to move `envExtra` above that line, non-interactive shells
  # would silently go back to nvm and ~/.yarn/bin outranking the Nix profile -
  # the exact shadowing this repo already fixed once for interactive shells.
  #
  # Matched by suffix rather than by key because the key follows
  # `programs.zsh.dotDir` ("./.zshenv" while that is the home directory).
  zshenvFiles = lib.filterAttrs (n: f: lib.hasSuffix "/.zshenv" n && f.text != null)
    config.home.file;
  zshenvSplit = lib.splitString envExtraMarker
    (lib.concatMapStringsSep "\n" (f: f.text) (lib.attrValues zshenvFiles));
  envExtraLandsAfterSessionVars =
    zshenvFiles != { }
    && builtins.length zshenvSplit == 2
    && lib.hasInfix "hm-session-vars.sh" (builtins.head zshenvSplit);
in
{
  imports = [
    ./nvm.nix
    ./agent-tooling/axi.nix
    ./agent-tooling/rtk.nix
    ./agent-tooling/caveman.nix
    ./agent-tooling/ccusage.nix
    ./agent-tooling/codegraph.nix
    ./npm-clis
  ];

  home.username = cfg.username;
  home.homeDirectory = cfg.homeDirectory;
  home.stateVersion = "23.11";
  home.language.base = "en_US.UTF-8";
  home.sessionPath = [
    "$HOME/.local/bin"    # native Claude Code + other manual/native installs
    "$HOME/.cargo/bin"    # rust / cargo
    "$HOME/.bun/bin"      # bun
    # Maestro's mobile UI test runner, which its installer drops in this dir.
    # Not demoted below the profile: `demotedSessionPathDirs` is for
    # global-install dirs, where an `npm i -g`/`yarn global add` can land a
    # same-named copy of a CLI this flake pins. This one is owned by a single
    # installer and holds a single tool, so nothing arbitrary can appear in it
    # to shadow anything. It is declared here rather than left to Maestro's
    # installer because that installer appends to `~/.zshrc`, which
    # home-manager owns and makes a read-only store symlink - the append
    # silently no-ops and the binary stays invisible.
    "$HOME/.maestro/bin"
    # The pinned Node from modules/nvm.nix. It is here, and not left to the
    # nvm.sh sourcing in the zsh init below, because that init only runs for
    # INTERACTIVE shells - so `zsh -c 'node ...'`, editor tasks, hooks and cron
    # saw no `node` at all. Listed before ~/.yarn/bin so the two keep the
    # documented relative order once both are demoted below the Nix profile.
    config.dotnix.nvm.nodeBinDir
    "$HOME/.yarn/bin"     # yarn global binaries
  ];

  # See `envExtraLandsAfterSessionVars` above: this guards the one home-manager
  # implementation detail the non-interactive PATH ordering rests on.
  assertions = [{
    assertion = envExtraLandsAfterSessionVars;
    message = ''
      modules/common.nix: could not confirm that programs.zsh.envExtra still
      lands after the hm-session-vars.sh line in the generated .zshenv.

      That ordering is what keeps the Nix profile above nvm and ~/.yarn/bin in
      non-interactive shells. Re-check how home-manager assembles .zshenv
      (modules/programs/zsh/default.nix), then either restore the ordering or
      move the PATH-precedence block into a fragment that runs after
      hm-session-vars.sh. Its first line is:
        ${envExtraMarker}
    '';
  }];

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
    # The circom circuit compiler. Previously a `cargo install --path` from a
    # local clone of iden3/circom, which left ~/.cargo/bin/circom with no
    # recorded provenance beyond that directory - move the clone and nothing
    # says what the binary was built from. nixpkgs carries the identical
    # version, so declaring it costs nothing and is not a version change.
    circom
    zip
    unzip
    # Python/dev toolchain. `gnumake` is here because a stock Ubuntu/WSL distro
    # ships no `make` at all, while macOS gets 3.81 from the Xcode CLT that
    # install.sh already triggers - declaring it keeps both platforms equal.
    # No interpreter is declared here: projects pin their own via
    # `uv python install`. One still reaches the profile indirectly, via
    # agent-tooling/caveman.nix, which is why the PATH ordering below keeps the
    # profile behind pyenv and Homebrew - see "PATH precedence" in README.md.
    uv
    gnumake
    pre-commit
    # Signed commits. `commit.gpgsign` is on per-repo, so a missing gpg does not
    # warn - it fails the commit outright ("cannot run gpg"). It was undeclared
    # and got zapped on the first switch to this flake; declaring it here keeps
    # it on both platforms.
    #
    # Installing a pinentry is NOT enough to pair it with gnupg, and for a long
    # time this comment claimed otherwise. gpg-agent never reads a passphrase
    # itself: it execs a separate pinentry binary at the absolute path given by
    # `pinentry-program` in gpg-agent.conf. It does not search PATH. With no
    # such config it falls back to a compiled-in `<gnupg>/bin/pinentry`, and the
    # nixpkgs gnupg output ships no pinentry there - so signing failed with
    # `gpg: signing failed: No pinentry` even though pinentry was installed and
    # on PATH. That line is now generated on both surfaces: `services.gpg-agent`
    # in modules/linux.nix, and the darwin-only gpg-agent.conf below.
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
      # Bump the AXI pins to their latest release and resolve the new hashes.
      # Rewrites modules/agent-tooling/axi-packages.nix and stops - review the
      # diff, then `rebuild`. This replaces reaching for `npx skills update`,
      # which writes into ~/.agents/skills behind the flake's back and breaks
      # the next activation; see the header of lib/update-axi.sh.
      update-axi = "bash ${dotfilesDir}/lib/update-axi.sh";
    } // lib.optionalAttrs pkgs.stdenv.isDarwin {
      # On-demand Homebrew upgrade (macOS only). `darwin-rebuild switch` only
      # installs missing declared packages; run this when you actually want to
      # bump already-installed brews/casks. Zap means only the declared set is
      # present, so this never touches anything outside modules/darwin.nix.
      brewup = "brew update && brew upgrade";
    };

    # .zshenv - read by EVERY zsh, interactive or not, and the only dotfile a
    # `zsh -c ...` reads at all. home-manager's own fragment above this one
    # exports `home.sessionPath` in front of the whole inherited PATH, which
    # would put the two demoted dirs (nvm's pinned Node, ~/.yarn/bin) above the
    # Nix profile - so re-assert the managed order right after it, exactly as
    # the interactive init does further down.
    #
    # WHY THE GUARD. A non-interactive zsh spawned FROM an interactive one
    # inherits a PATH that .zshrc already assembled, pyenv and Homebrew
    # included, and .zshrc will not run again to put them back on top. Hoisting
    # the profile unconditionally there would demote Homebrew's python3 below
    # the Nix one for every `zsh -c` - the one collision "PATH precedence" in
    # README.md says must not happen. So the hoist runs only when no parent
    # shell has already done the full assembly; when one has, its PATH is
    # already correct and the right move is to leave it alone.
    envExtra = ''
      ${envExtraMarker}
      if [ -z "''${${pathAssembledMarker}-}" ]; then
      ${indentBlock "  " managedPathReassert}
      fi
    '';

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
      #     > ~/.maestro/bin > Nix profile > nvm > ~/.yarn/bin > system
      #
      # Rationale per block is inline below; the short version is that the Nix
      # profile has to outrank nvm (that is where stray `npm i -g` binaries
      # live) without displacing pyenv's or Homebrew's Python, which is the one
      # place the two goals genuinely conflict. See "PATH precedence" in
      # README.md.
      #
      # This runs for INTERACTIVE shells only. Non-interactive ones get the
      # same tail of that order (profile > nvm > ~/.yarn/bin) from the
      # `envExtra` block above, which is why the pinned Node is a
      # `home.sessionPath` entry and not only an nvm.sh side effect.
      # ---------------------------------------------------------------------

      # nvm. Runs first, so it ends up BELOW the Nix profile: npm globals
      # installed into the active Node version's bin must never shadow a CLI
      # this flake pins. nvm still owns Node itself - no node/npm/npx/corepack
      # is declared in this flake, so nothing here competes with it, and nvm's
      # own `nvm use` reshuffling continues to work because it rewrites only
      # its own entry.
      #
      # nvm and a default LTS Node are installed by modules/nvm.nix (a pinned
      # fetch into the store, copied into $NVM_DIR on activation) - that module
      # explains why nvm can't just be a package. The `-s` guards stay: they
      # keep a brand-new shell working on the one machine where that
      # activation's Node download failed, and cost a stat either way.
      #
      # Sourcing nvm.sh is what makes `nvm use <v>` and a user-chosen `nvm alias
      # default` take effect: nvm strips every $NVM_DIR entry from PATH and
      # re-adds the one it selected, which includes the pinned entry .zshenv
      # put there. So interactive shells follow nvm, non-interactive ones get
      # the pinned Node - the only version lib/nvm-bootstrap.sh guarantees is
      # installed.
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
      # same name. Four `home.sessionPath` dirs are re-prepended ahead of the
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
      #   - `~/.maestro/bin` holds one installer-managed tool (`maestro`) and
      #     nothing else can land in it, so it carries no shadowing risk.
      # Neither `~/.yarn/bin` nor nvm's pinned Node dir is an exception - both
      # are global-install dirs, so `demotedSessionPathDirs` above keeps them
      # out of this array and they stay below the profile where home-manager
      # already put them.
      ${managedPathReassert}

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

      # PATH is now fully assembled, pyenv and Homebrew included. Exported so a
      # non-interactive child zsh (which reads .zshenv but never this file) can
      # tell "inherited a finished PATH" from "starting from scratch" and skip
      # the re-prepend there - see the `envExtra` block above. It has to be set
      # after the four blocks, not inside one of them, because only here is the
      # claim actually true.
      export ${pathAssembledMarker}=1

      # bun completions
      [ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

      ${lib.optionalString pkgs.stdenv.isDarwin ''
      # gpg-agent draws the passphrase prompt on the terminal named by GPG_TTY.
      # `git commit -S` hands gpg a pipe on stdin, so gpg cannot infer the
      # terminal from its own descriptors; without this the pinentry fails with
      # "Inappropriate ioctl for device". It has to be per-shell, which is why
      # it lives here and not in `home.sessionVariables` - those are evaluated
      # once at build time, where the current tty is meaningless. `$TTY` is a
      # zsh builtin, so this costs no fork.
      #
      # darwin only: on Linux/WSL `services.gpg-agent.enableZshIntegration`
      # (modules/linux.nix) emits exactly this same `export GPG_TTY=$TTY` line,
      # so exporting it here too would just be a duplicate.
      export GPG_TTY=$TTY
      ''}

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
    # herdr: SINGLE FILE only. Do NOT symlink ~/.config/herdr itself. herdr owns
    # that directory as runtime state - it writes live sockets (herdr.sock,
    # herdr-client.sock) and rotating logs there on every run. A whole-dir
    # mkOutOfStoreSymlink pointed it at a nonexistent files/.config/herdr,
    # leaving a dangling symlink; herdr's startup mkdir() then failed with
    # EEXIST and the server never came up. Linking config.toml on its own leaves
    # the directory a real directory that herdr keeps owning, so that failure
    # cannot recur. Any future herdr file must be linked the same way, one
    # entry per file.
    #
    # Unguarded on purpose: herdr is present on every surface this repo
    # configures - Homebrew on macOS (modules/darwin.nix), its own flake input
    # on Linux and WSL2 (`herdrPkg` in modules/linux.nix) - so there is no
    # platform where this link would dangle.
    ".config/herdr/config.toml".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.config/herdr/config.toml";
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
  }
  # Point gpg-agent at its pinentry on macOS. Linux/WSL gets the equivalent
  # from `services.gpg-agent` in modules/linux.nix, which also supervises the
  # agent; that module cannot be reused here because its `pinentry.package`
  # takes a nixpkgs derivation, and macOS uses Homebrew's `pinentry-mac`
  # (declared in modules/darwin.nix) - there is no `pkgs` attribute to hand it.
  # So this is a literal path, chosen by CPU because Homebrew's prefix differs:
  # /opt/homebrew on Apple Silicon, /usr/local on Intel. It is deliberately not
  # a /nix/store path - pinentry-mac is not in the store at all.
  #
  # This lives in common.nix rather than modules/darwin.nix because darwin.nix
  # is a nix-darwin SYSTEM module and has no `home.file`; common.nix is the only
  # home-manager module on the darwin surface (see flake.nix).
  #
  # ONE-TIME MIGRATION, both platforms: a hand-written ~/.gnupg/gpg-agent.conf
  # already exists on machines that were unblocked manually. home-manager
  # refuses to clobber an unmanaged file, so the first switch fails until it is
  # removed, and the agent caches its config at startup so it must be restarted
  # afterwards:
  #     rm ~/.gnupg/gpg-agent.conf && rebuild && gpgconf --kill gpg-agent
  # See "GPG signing" in README.md.
  // lib.optionalAttrs pkgs.stdenv.isDarwin {
    ".gnupg/gpg-agent.conf".text = ''
      pinentry-program ${
        if pkgs.stdenv.hostPlatform.isAarch64
        then "/opt/homebrew/bin/pinentry-mac"
        else "/usr/local/bin/pinentry-mac"
      }
      default-cache-ttl 3600
      max-cache-ttl 28800
    '';
  };
}
