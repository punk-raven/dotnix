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
`wezterm`, `amethyst`, `docker-desktop`, `opensuperwhisper`, `zulu@17`

## Linux / WSL equivalents (`modules/linux.nix`)

nixpkgs versions of the portable brews above:
`ffmpeg`, `direnv`, `gh`, `watchman`, `act`, `opentofu`, `ktlint`, `autoconf`,
`bear`, `cf-terraforming`, `git-filter-repo`, `mongodb-tools`, `pyenv`,
`zulu17`, `pinentry-curses`, plus `herdr` from its own flake.

**Linux-only additions** - these have no brew counterpart because macOS gets the
same capability from the OS:

| Package | Closes |
|---------|--------|
| `gcc`, `binutils`, `pkg-config` | No compiler on a stock Ubuntu/WSL distro. macOS gets clang + ld from the Xcode CLT that `install.sh` triggers. Needed by `rustup` (rustc links via `cc`), neovim `:TSInstall`, and native npm/pre-commit hooks |
| `docker-client`, `docker-compose`, `docker-buildx` | The client half of the `docker-desktop` cask. See the Docker note below |

macOS-only tools (`cocoapods`, `pinentry-mac`) have no entry. GUI apps come from
`modules/gui.nix` and are skipped entirely when `headless = true`:

| Package | Closes |
|---------|--------|
| `wezterm` | The `wezterm` cask, wrapped in nixGL so it finds a GL driver on a non-NixOS host |
| `brave` | `chrome-devtools-axi` and the `brave-cdp` helper in `agent-tooling/axi.nix` need a browser on `:9222`. macOS opens the app bundle, installed outside this flake |
| `wl-clipboard`, `xclip` | `clipboard = "unnamedplus"` in the nvim config is a silent no-op on Linux without an external provider. macOS uses pbcopy/pbpaste natively. WSLg offers both Wayland and X11, so both providers ship |

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
- **Docker is asymmetric on purpose.** macOS gets the whole engine from the
  `docker-desktop` cask in `modules/darwin.nix`. Linux/WSL2 gets only the
  clients (`docker-client`, `docker-compose`, `docker-buildx`) in
  `modules/linux.nix`: standalone home-manager is unprivileged, and `dockerd`
  needs root plus an init system, so no home-manager module can install or run
  it. On WSL2 the daemon comes from Docker Desktop for Windows with WSL
  integration turned on for the distro; on native Linux it is a root-level
  concern (`services.docker`, or the distro package).
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
