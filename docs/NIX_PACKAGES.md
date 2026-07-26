# Nix setup - installed packages

Full inventory of everything this flake installs. Paths refer to the module that
declares each item, so the layout in [`../README.md`](../README.md) is the index
and this file is the contents.

## Shared `home.packages` (`modules/common.nix`)

Installed on macOS, Linux and WSL alike.

**CLI / dev tools:**
`git`, `curl`, `wget`, `jq`, `fd`, `fzf`, `fastfetch`, `neovim`, `ripgrep`,
`lazygit`, `tree`, `bun`, `rustup`, `uv`, `gnumake`, `pre-commit`, `zip`,
`unzip`

**Linux only:** `killall` (a system builtin on macOS, a package only on Linux)

**Fonts:**
`nerd-fonts.hack`, `roboto`, `noto-fonts`, `noto-fonts-cjk-sans`,
`noto-fonts-color-emoji`, `font-awesome`

**Programs enabled via home-manager modules:**
`git` (+ lfs), `starship`, `zsh` (oh-my-zsh, autosuggestion, syntax-highlighting),
`home-manager` (the standalone CLI, Linux/WSL only - macOS goes through
`darwin-rebuild`)

## nix-darwin `environment.systemPackages` (`modules/darwin.nix`)

`starship`

## Custom Nix-managed agent tooling (`modules/agent-tooling/`)

| Module | On PATH |
|--------|---------|
| `axi.nix` | `gh-axi`, `chrome-devtools-axi`, `lavish-axi` (+ pinned `chrome-devtools-mcp` engine as dep) |
| `rtk.nix` | `rtk` |
| `caveman.nix` | `caveman-activate`, `caveman-mode-tracker`, `python3` |
| `ccusage.nix` | `ccusage` |
| `codegraph.nix` | `codegraph` |

Release artifacts are selected by `system`, so Linux and Intel hosts pull their
own binaries from the same pinned versions.

## Homebrew - macOS only (`modules/darwin.nix`, zap-cleaned)

**Tap:** `mongodb/brew`

**Brews:**
`autoconf`, `herdr`, `act`, `bear`, `cf-terraforming`, `cocoapods`, `direnv`,
`ffmpeg`, `gh`, `git-filter-repo`, `ktlint`, `mongodb-database-tools`,
`opentofu`, `pinentry-mac`, `pyenv`, `watchman`

**Casks:**
`wezterm`, `amethyst`, `opensuperwhisper`, `zulu@17`

## Linux / WSL equivalents (`modules/linux.nix`)

nixpkgs versions of the portable brews above:
`ffmpeg`, `direnv`, `gh`, `watchman`, `act`, `opentofu`, `ktlint`, `autoconf`,
`bear`, `cf-terraforming`, `git-filter-repo`, `mongodb-tools`, `pyenv`,
`zulu17`, `pinentry-curses`, plus `herdr` from its own flake.

macOS-only tools (`cocoapods`, `pinentry-mac`) have no entry. GUI apps come from
`modules/gui.nix` (`wezterm`, wrapped in nixGL so it finds a GL driver on a
non-NixOS host) and are skipped entirely when `headless = true`.

## Neovim plugins (`files/.config/nvim/`)

NOT Nix-managed. The neovim binary comes from Nix (`modules/common.nix`); the
config is an out-of-store symlink and plugins are fetched by neovim's built-in
`vim.pack`, pinned in `nvim-pack-lock.json`. Listed here for completeness.

| Plugin | Source | Purpose |
|--------|--------|---------|
| `plenary.nvim` | nvim-lua/plenary.nvim | Lua lib; hard dep of neogit + diffview |
| `mini.icons` | nvim-mini/mini.icons | Icon provider (oil, snacks, neogit) |
| `snacks.nvim` | folke/snacks.nvim | QoL collection (picker, explorer, notifier, indent...) |
| `oil.nvim` | stevearc/oil.nvim | Edit filesystem like a buffer |
| `neogit` | NeogitOrg/neogit | Magit-style git interface |
| `diffview.nvim` | sindrets/diffview.nvim | Side-by-side git diff / file history |
| `gitsigns.nvim` | lewis6991/gitsigns.nvim | Git gutter signs + line blame |
| `which-key.nvim` | folke/which-key.nvim | Popup of `<leader>` mappings |

## Notes

- `git`, `gh`, `neovim` intentionally sourced from Nix, not (only) Homebrew.
  Homebrew `gh` coexists; Nix `neovim` is the single source of truth.
- Homebrew is `onActivation.cleanup = "zap"`: any brew/cask NOT declared in
  `modules/darwin.nix` gets removed on every switch. That includes anything
  installed by hand, so declare it or expect to lose it.
- **No Docker here.** Docker Desktop is installed outside Homebrew, which is why
  zap leaves it alone. Declaring the `docker-desktop` cask requires adopting the
  existing app first (`brew install --cask --adopt docker-desktop`), after which
  zap owns it.
- **Postgres is gone on purpose.** `postgresql@18` + `postgis` were removed
  because databases now come from a per-project compose container, which also
  ends the race for `:5432`.
- **Two Python managers, on purpose.** `pyenv` and `uv` both stay. pyenv's shims
  sit early on `PATH`, so a project that pins its interpreter with
  `uv python install <version>` should export `UV_MANAGED_PYTHON=1` to make uv
  ignore them. Inside such a project uv wins; pyenv keeps everything else. No
  global interpreter is declared here for the same reason - a third python would
  only add another candidate.
- `gnumake` is 4.4.1, ahead of the 3.81 that ships with the Xcode CLT, and it
  shadows `/usr/bin/make` on `PATH`.
