# Cross-platform Nix dotfiles

One shared package set and agent-tooling environment across **macOS**, **Linux**,
and **Windows (WSL2)**, driven by a single Nix flake and an interactive installer
that prompts for the per-user values instead of hardcoding them.

- macOS -> `nix-darwin` + home-manager
- Linux (any distro) -> standalone home-manager
- Windows -> WSL2 + the identical Linux path (Nix does not run natively on Windows)

The only file that differs between users/machines is [`config.nix`](config.example.nix).

## Prerequisites per OS

| OS | Needs |
|----|-------|
| **macOS** | Xcode Command Line Tools (installer triggers them), admin rights (nix-darwin uses `sudo`). Homebrew is managed declaratively by `nix-homebrew`. |
| **Linux** | `git` + `curl` (installer prints the package command if missing). Multi-user Nix needs `sudo`/systemd; rootless works otherwise. |
| **Windows** | Windows 10 21H2+/11, virtualization enabled in BIOS/UEFI, one elevated PowerShell to enable WSL2. WSLg (bundled) for GUI apps; headless installs skip them. |

Nix itself is installed by the script (Determinate installer) if absent.

## Install

Clone this repo first (you commit your generated `config.nix` to your fork).

**macOS / Linux / inside a WSL distro:**

```sh
curl -fsSL https://raw.githubusercontent.com/allanjeo/dotfiles/main/install.sh | sh
```

**Windows (elevated / Administrator PowerShell):**

```powershell
irm https://raw.githubusercontent.com/allanjeo/dotfiles/main/install.ps1 | iex
```

The installer detects your `system`, prompts for `username`, `homeDirectory`,
`gitName`, and `gitEmail` (press enter to accept the auto-detected defaults),
writes `config.nix`, `git add -f`s it so the flake can see it, and activates.
Re-running re-prompts with your existing values as defaults.

**After it finishes**, load Nix into your current shell (a brand-new install is
not on the `PATH` of the shell that started before Nix existed):

```sh
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
```

or just open a new terminal. From then on `nix`, your packages, and the
`rebuild` alias are available. Apply later config edits with `rebuild`.

## How `config.nix` is generated

`config.nix` holds the six per-user values and is the only file that differs
between machines. It is **git-ignored** so this repo never carries a real user's
values - you generate your own.

Two ways to create it:

1. **Automatic (installer).** `install.sh` detects `system`, prompts for
   `username`, `homeDirectory`, `gitName`, `gitEmail` (auto-detected defaults;
   press enter to accept), fills in `hostname` and `headless`, and writes
   `config.nix`.
2. **Manual.** Copy the template and edit it:
   ```sh
   cp config.example.nix config.nix
   $EDITOR config.nix
   ```

**Why it is force-added.** A Nix flake in a git repo ignores *untracked* files,
so a freshly written `config.nix` is invisible to `nix build` / `darwin-rebuild`
until it is in git's index. The installer therefore runs `git add -f config.nix`
after writing it (the `.gitignore` entry only guards the template; `-f`
overrides it). If you do this manually, force-add it yourself:

```sh
git add -f config.nix
```

Commit it to your fork so your machine is reproducible. (Alternative: leave it
untracked and build with `--impure`, reading an absolute path - less
reproducible, so tracked-file is the default.)

## What you get

- **Shared CLI** (all platforms): git, curl, wget, jq, fd, fzf, fastfetch,
  neovim, ripgrep, lazygit, tree, bun, rustup, zip, unzip, Nerd/Noto fonts.
- **Shell**: zsh (oh-my-zsh, autosuggestion, syntax-highlighting) + starship,
  with the same aliases everywhere (`rebuild` re-applies the config per platform).
- **Agent tooling** (all platforms): `gh-axi`, `chrome-devtools-axi`, `lavish-axi`,
  `rtk`, `ccusage`, `codegraph`, and caveman - each pinned and reproducible, with
  the Linux/Intel release artifacts selected automatically by `system`.
- **macOS extras**: Homebrew brews/casks (with `zap` cleanup) and
  `system.defaults` in [`modules/darwin.nix`](modules/darwin.nix).
- **Linux extras**: nixpkgs equivalents of the portable brews + optional desktop
  GUI apps (wezterm), skipped when `headless = true`.

## Layout

```
flake.nix                 darwinConfigurations + homeConfigurations, imports config.nix
config.nix                generated per-user (git-ignored template guard; force-added)
config.example.nix        committed template with placeholders
modules/
  common.nix              SHARED: packages, git/zsh/starship, dotfile symlinks
  darwin.nix              macOS-only: homebrew, system.defaults, nix-homebrew
  linux.nix               Linux/WSL-only: nixpkgs brew equivalents, GUI opt-in
  gui.nix                 cross-platform GUI apps (wezterm)
  agent-tooling/          axi, rtk, caveman, ccusage, codegraph (system-keyed sources)
files/                    dotfiles symlinked by home-manager (nvim, wezterm, agent cfg)
install.sh                POSIX entry point: macOS + Linux + inside-WSL
install.ps1               Windows: enable WSL2, install distro, hand to install.sh
lib/prompt.sh             shared prompt/detect helpers
tests/install_test.sh     hermetic PATH-masked stub test
```

## Applying changes

Edit the Nix config, then run `rebuild` (aliased per platform), or directly:

```sh
# macOS
darwin-rebuild switch --flake ~/dotfiles#<hostname>
# Linux / WSL
home-manager switch --flake ~/dotfiles#<username>
```
