<div align="center">

# Cross-platform Nix dotfiles

**One shared package set and agent-tooling environment across macOS, Linux, and Windows (WSL2)** -
driven by a single Nix flake and an interactive installer that prompts for your
per-user values instead of hardcoding them.

</div>

| Platform | Mechanism | Nix layer |
|----------|-----------|-----------|
| 🍎 **macOS** | `nix-darwin` + home-manager | `darwinConfigurations.<host>` |
| 🐧 **Linux** (any distro) | standalone home-manager | `homeConfigurations.<user>` |
| 🪟 **Windows** | WSL2 + the identical Linux path | `homeConfigurations.<user>` |

> Nix does not run natively on Windows, so Windows runs the identical Linux flow
> inside WSL2. The only file that differs between users/machines is
> [`config.nix`](config.example.nix).

## Contents

- [Prerequisites](#prerequisites) - [macOS](#-macos) · [Linux](#-linux) · [Windows](#-windows-wsl2)
- [Install](#install)
- [How `config.nix` is generated](#how-confignix-is-generated)
- [What you get](#what-you-get)
- [Repository layout](#repository-layout)
- [Applying changes](#applying-changes)

---

## Prerequisites

Nix itself is installed by the installer (Determinate installer) if absent, and
it manages the whole CLI/font/shell/agent-**tooling** set declaratively. A few
things are **not** Nix-managed and must be installed manually - chiefly the agent
**runtimes** (`claude`, `codex`), which are closed-source and self-updating. They
should land on `PATH`; `~/.local/bin` is already configured, which is where their
native installers place them.

The tables below are grouped by OS. Follow each tool's current official docs -
the example commands can drift.

### 🍎 macOS

**System**

- **Xcode Command Line Tools** - for `git` + the build toolchain (the installer
  triggers `xcode-select --install` and waits).
- **Admin rights** - nix-darwin activation uses `sudo`.
- **Homebrew** - managed declaratively by `nix-homebrew`; no separate install.

**Manual tools** (follow each tool's current docs; commands can drift)

**Claude Code** (`claude`) - drives the `cc` alias and `~/.claude/settings.json`
hooks/statusline:

```sh
curl -fsSL https://claude.ai/install.sh | bash
```

**Codex CLI** (`codex`) - drives the `co` alias and `~/.codex/` config & hooks:

```sh
brew install codex          # or: npm i -g @openai/codex
```

**Node.js** - needed by the npm-based agent installs and JS projects (`nvm` is
already sourced by the shell):

```sh
nvm install --lts
```

**Brave / Chromium** - `chrome-devtools-axi` and the `brave-cdp` helper attach to
it on `:9222`:

```sh
brew install --cask brave-browser
```

**OpenCode** (`opencode`) - optional; its config is symlinked either way. See
https://opencode.ai.

### 🐧 Linux

**System**

- **`git` + `curl`** - usually preinstalled; the installer prints the package
  command if missing (`apt`/`dnf`/`pacman`).
- **`sudo` / systemd** - multi-user (daemon) Nix needs them; rootless works
  otherwise.
- **`fontconfig`** - for the bundled fonts (pulled in by home-manager).

**Manual tools** (follow each tool's current docs; commands can drift)

**Claude Code** (`claude`) - drives the `cc` alias and `~/.claude/settings.json`
hooks/statusline:

```sh
curl -fsSL https://claude.ai/install.sh | bash
```

**Codex CLI** (`codex`) - drives the `co` alias and `~/.codex/` config & hooks:

```sh
npm i -g @openai/codex
```

**Node.js** - needed by the npm-based agent installs and JS projects (`nvm` is
already sourced by the shell):

```sh
nvm install --lts
```

**Chromium / Brave** - `chrome-devtools-axi` and the `brave-cdp` helper attach to
it on `:9222`:

```sh
sudo apt install chromium-browser   # or add the Brave apt repo
```

**OpenCode** (`opencode`) - optional; its config is symlinked either way. See
https://opencode.ai.

### 🪟 Windows (WSL2)

**System**

- **Windows 10 21H2+ / Windows 11** with virtualization enabled in BIOS/UEFI.
- **One elevated (Administrator) PowerShell** to enable WSL2 (`install.ps1`).
- **WSLg** (bundled with recent WSL) for GUI apps; headless installs skip them.

**Manual tools** - once WSL2 + a distro are up, you are **inside Linux**, so the
prerequisites collapse to the [Linux](#-linux) list above, run inside the distro.
GUI apps display through WSLg; alternatively use a Windows-side browser for
`chrome-devtools-axi`.

> **macOS Homebrew extras** (`herdr`, `postgresql@18`, `zulu@17`, …) are installed
> declaratively in [`modules/darwin.nix`](modules/darwin.nix), so they are **not**
> manual on macOS. Their portable equivalents come from
> [`modules/linux.nix`](modules/linux.nix) on Linux; the remaining macOS-only apps
> (`amethyst`, `opensuperwhisper`, `cocoapods`) have no Linux counterpart.
>
> **herdr** is managed declaratively on every platform - Homebrew on macOS
> ([`modules/darwin.nix`](modules/darwin.nix)), and its own Nix flake on
> Linux/WSL ([`modules/linux.nix`](modules/linux.nix), pinned in `flake.nix`), so
> it is **not** a manual install. Note the `herdr` SessionStart hook in the agent
> configs points at a machine-local script
> (`~/.claude/hooks/herdr-agent-state.sh`); if that script is absent the hook
> simply no-ops, safe to ignore unless you use herdr.

---

## Install

Your generated `config.nix` lives outside this repo (at
`~/.config/dotnix/config.nix`), so nothing personal is ever committed.

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
writes `~/.config/dotnix/config.nix`, and activates. Re-running re-prompts with
your existing values as defaults.

**After it finishes**, load Nix into your current shell (a brand-new install is
not on the `PATH` of the shell that started before Nix existed):

```sh
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
```

…or just open a new terminal. From then on `nix`, your packages, and the
`rebuild` alias are available. Apply later config edits with `rebuild`.

---

## How `config.nix` is generated

`config.nix` holds the per-user values and is the only file that differs between
machines. It lives **outside this repo** at `~/.config/dotnix/config.nix`
(override with `$DOTNIX_CONFIG`), so a real user's values are never committed to
a shared or template checkout.

**Two ways to create it:**

1. **Automatic (installer).** `install.sh` detects `system`, prompts for
   `username`, `homeDirectory`, `gitName`, `gitEmail` (auto-detected defaults;
   press enter to accept), fills in `hostname` + `headless`, and writes it to
   `~/.config/dotnix/config.nix`.
2. **Manual.** Copy the template and edit:
   ```sh
   mkdir -p ~/.config/dotnix
   cp config.example.nix ~/.config/dotnix/config.nix
   $EDITOR ~/.config/dotnix/config.nix
   ```

**Why it is read impurely.** A Nix flake only sees files inside its own git
tree, so config kept *inside* the repo would have to be committed (leaking your
values) or `git add -f`ed (one accidental commit from leaking). Keeping it
outside the tree avoids that entirely - the flake reads it via
`builtins.getEnv "DOTNIX_CONFIG"`, which requires impure evaluation. Every
activation command therefore passes `--impure` (the `rebuild` alias and the
installer already do this for you).

---

## What you get

- **Shared CLI** (all platforms): `git`, `curl`, `wget`, `jq`, `fd`, `fzf`,
  `fastfetch`, `neovim`, `ripgrep`, `lazygit`, `tree`, `bun`, `rustup`, `zip`,
  `unzip`, Nerd/Noto fonts.
- **Shell**: `zsh` (oh-my-zsh, autosuggestion, syntax-highlighting) + `starship`,
  with the same aliases everywhere (`rebuild` re-applies the config per platform).
- **Agent tooling** (all platforms): `gh-axi`, `chrome-devtools-axi`,
  `lavish-axi`, `rtk`, `ccusage`, `codegraph`, and caveman - each pinned and
  reproducible, with the Linux/Intel release artifacts selected automatically by
  `system`.
- **macOS extras**: Homebrew brews/casks (with `zap` cleanup) and
  `system.defaults` in [`modules/darwin.nix`](modules/darwin.nix).
- **Linux extras**: nixpkgs equivalents of the portable brews + optional desktop
  GUI apps (wezterm), skipped when `headless = true`.

---

## Repository layout

```
flake.nix                 darwinConfigurations + homeConfigurations, reads config.nix impurely
config.example.nix        committed template; real config.nix lives in ~/.config/dotnix/ (out of tree)
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

---

## Applying changes

Edit the Nix config, then run `rebuild` (aliased per platform). Because
`config.nix` is read from outside the flake, direct invocations need `--impure`
and `$DOTNIX_CONFIG` in the environment (`rebuild` sets both for you):

```sh
# macOS (sudo scrubs the env, so pass the var through `sudo env`)
sudo env DOTNIX_CONFIG=~/.config/dotnix/config.nix \
  darwin-rebuild switch --impure --flake ~/dotfiles#<hostname>

# Linux / WSL
DOTNIX_CONFIG=~/.config/dotnix/config.nix \
  home-manager switch --impure --flake ~/dotfiles#<username>
```
