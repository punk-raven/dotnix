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
- [What you get](#what-you-get) - [PATH precedence](#path-precedence)
- [Flake inputs](#flake-inputs)
- [Repository layout](#repository-layout)
- [License](#license) · [Contributing](#contributing)
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

**OpenCode** (`opencode`) - optional; its config is symlinked either way. See
https://opencode.ai.

> **Brave is no longer manual on Linux/WSL.** `chrome-devtools-axi` and the
> `brave-cdp` helper need a browser to attach to on `:9222`, so `brave` is
> declared in [`modules/gui.nix`](modules/gui.nix) and installed on every
> non-headless install. A headless install still has no browser by design.
>
> **Neither is the C toolchain.** A stock Ubuntu/WSL distro ships no compiler,
> which breaks `rustup` (rustc uses `cc` as its linker), neovim `:TSInstall`,
> and native npm/pre-commit hooks. macOS gets clang from the Xcode Command Line
> Tools that `install.sh` triggers, so `gcc`, `binutils`, and `pkg-config` are
> declared in [`modules/linux.nix`](modules/linux.nix) to match.
>
> **`pyenv` build headers stay manual.** `pyenv install` compiles CPython from
> source and looks for system headers that Nix does not put where it searches.
> Either `sudo apt install libssl-dev zlib1g-dev libbz2-dev libreadline-dev
> libsqlite3-dev libffi-dev liblzma-dev tk-dev`, or prefer `uv python install`
> (see the pyenv/uv precedence rule in [`docs/NIX_PACKAGES.md`](docs/NIX_PACKAGES.md)).

### 🪟 Windows (WSL2)

**System**

- **Windows 10 21H2+ / Windows 11** with virtualization enabled in BIOS/UEFI.
- **One elevated (Administrator) PowerShell** to enable WSL2 (`install.ps1`).
- **WSLg** (bundled with recent WSL) for GUI apps; headless installs skip them.

**Manual tools** - once WSL2 + a distro are up, you are **inside Linux**, so the
prerequisites collapse to the [Linux](#-linux) list above, run inside the distro.
GUI apps display through WSLg; alternatively use a Windows-side browser for
`chrome-devtools-axi`.

**Docker** - the one thing this flake cannot fully declare on WSL2. Standalone
home-manager runs unprivileged and `dockerd` needs root plus an init system, and
nixpkgs has no `docker-desktop` package for Linux at all. So
[`modules/linux.nix`](modules/linux.nix) declares only the clients
(`docker-client`, `docker-compose`, `docker-buildx`) and the daemon comes from
outside Nix. Two options:

1. **Docker Desktop for Windows + WSL integration** (recommended; no distro
   changes). Settings → Resources → WSL integration → enable this distro. It
   exposes `/var/run/docker.sock` inside WSL and the declared clients then behave
   exactly as they do on macOS.
2. **Docker Desktop for Linux inside the distro** (Ubuntu 24.04/26.04 LTS only,
   and not a configuration Docker documents as supported). It requires Windows 11
   for nested virtualization, plus systemd, which WSL2 leaves off by default:
   ```ini
   # %UserProfile%\.wslconfig   (Windows side)
   [wsl2]
   nestedVirtualization=true
   ```
   ```ini
   # /etc/wsl.conf              (inside the distro)
   [boot]
   systemd=true
   ```
   Then `wsl --shutdown` from Windows, reopen the distro, and verify KVM actually
   arrived **before** installing anything - if `/dev/kvm` is missing, the steps
   above did not take effect and the install will not yield a working daemon:
   ```sh
   ls -l /dev/kvm && sudo usermod -aG kvm "$USER"
   ```
   Then follow https://docs.docker.com/desktop/setup/install/linux/ubuntu/ and
   start it with `systemctl --user start docker-desktop`.

> Either way the Nix profile precedes `/usr/bin` on `PATH`, so the declared
> `docker` client wins over any CLI a `.deb` drops in. It honors
> `~/.docker/config.json` and contexts, so it follows Docker Desktop's
> `desktop-linux` context correctly; only `docker --version` differs.

> **macOS Homebrew extras** (`herdr`, `zulu@17`, `opentofu`, …) are installed
> declaratively in [`modules/darwin.nix`](modules/darwin.nix), so they are **not**
> manual on macOS. Their portable equivalents come from
> [`modules/linux.nix`](modules/linux.nix) on Linux; the remaining macOS-only apps
> (`amethyst`, `opensuperwhisper`, `cocoapods`) have no Linux counterpart.
>
> **herdr** is managed declaratively on every platform - Homebrew on macOS
> ([`modules/darwin.nix`](modules/darwin.nix)), and its own Nix flake on
> Linux/WSL ([`modules/linux.nix`](modules/linux.nix), pinned in `flake.nix`), so
> it is **not** a manual install. Its config
> ([`files/.config/herdr/config.toml`](files/.config/herdr/config.toml) - tmux
> keymap, `ctrl+b` prefix, `hjkl` pane focus) is versioned here and linked as a
> **single file**, never as a directory: herdr owns `~/.config/herdr` as runtime
> state (live sockets, rotating logs), and a whole-directory symlink is what
> broke its startup with `EEXIST`. The reasoning is inline in
> [`modules/common.nix`](modules/common.nix). herdr writes its own
> `config.toml` on first run, so that path often already exists unmanaged. Both
> surfaces rename such a file to `<name>.backup` instead of aborting the whole
> switch: macOS via `home-manager.backupFileExtension = "backup"` in
> [`flake.nix`](flake.nix), Linux/WSL via `-b backup` on the standalone
> `home-manager switch` the `rebuild` alias runs. That applies to every path
> this flake manages, not just herdr's. Note the `herdr` SessionStart hook
> in the agent configs points at a machine-local script
> (`~/.claude/hooks/herdr-agent-state.sh`); if that script is absent the hook
> simply no-ops, safe to ignore unless you use herdr.

---

## Install

Your generated `config.nix` lives outside this repo (at
`~/.config/dotnix/config.nix`), so nothing personal is ever committed.

**macOS / Linux / inside a WSL distro:**

```sh
curl -fsSL https://raw.githubusercontent.com/punk-raven/dotnix/main/install.sh | sh
```

**Windows (elevated / Administrator PowerShell):**

```powershell
irm https://raw.githubusercontent.com/punk-raven/dotnix/main/install.ps1 | iex
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

## Applying changes: `rebuild`

After editing your config, run `rebuild` to re-apply it. The alias is identical
on every platform - only what it expands to differs:

| Platform | `rebuild` runs |
| --- | --- |
| 🍎 **macOS** | `darwin-rebuild switch` (via `nix-darwin`, under `sudo`) |
| 🐧 **Linux** / 🪟 **WSL2** | `home-manager switch` (standalone) |

Both pass `--impure` so the flake can read your out-of-tree
`~/.config/dotnix/config.nix`.

The `rebuild` alias only exists in shells started **after** the first successful
activation. If it is not found yet, either open a new terminal or source the
Nix profile first, then rebuild:

```sh
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
rebuild
```

If the alias is still unavailable, run the raw Linux/WSL command directly:

```sh
DOTNIX_CONFIG=~/.config/dotnix/config.nix \
  home-manager switch -b backup --impure --flake ~/dotfiles#<username>
```

`-b backup` is what the `rebuild` alias passes too: any unmanaged file already
sitting at a path this flake manages is renamed to `<name>.backup` rather than
failing the switch. Drop it and the whole activation aborts on the first such
file.

The standalone `home-manager` CLI is installed by the config itself, so it only
exists **after** a first successful activation. If you get
`command not found: home-manager`, bootstrap without it via `nix run` (this is
what the installer does on the first pass):

```sh
DOTNIX_CONFIG=~/.config/dotnix/config.nix \
  nix run github:nix-community/home-manager/release-26.05 -- \
  switch -b backup --impure --flake ~/dotfiles#<username>
```

The ref is pinned to the same 26.05 release branch as the `home-manager` input
in `flake.nix`, so the bootstrap CLI matches the flake it activates.

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
  `fastfetch`, `neovim`, `ripgrep`, `lazygit`, `tree`, `bun`, `rustup`, `uv`,
  `gnumake`, `pre-commit`, `zip`, `unzip`, Nerd/Noto fonts.
- **Shell**: `zsh` (oh-my-zsh, autosuggestion, syntax-highlighting) + `starship`,
  with the same aliases everywhere (`rebuild` re-applies the config per platform).
- **Agent tooling** (all platforms): `gh-axi`, `chrome-devtools-axi`,
  `lavish-axi`, `tasks-axi`, `rtk`, `ccusage`, `codegraph`, and caveman - each
  pinned and reproducible, with the Linux/Intel release artifacts selected
  automatically by `system`. The pinned build is also the one that *runs*: see
  [PATH precedence](#path-precedence) for why that needs saying.
- **macOS extras**: Homebrew brews/casks (with `zap` cleanup) and
  `system.defaults` in [`modules/darwin.nix`](modules/darwin.nix).
- **Linux extras**: nixpkgs equivalents of the portable brews + optional desktop
  GUI apps (wezterm), skipped when `headless = true`.

> **Two Python managers, on purpose.** `pyenv` (brew/nixpkgs, initialised in the
> zsh `initContent`) and `uv` (shared CLI set) are both installed and both stay.
> They resolve interpreters independently, and pyenv's shims sit early on `PATH`,
> so a project that assumes one can silently get the other - the usual symptom is
> a version gate reporting a 3.x nobody asked for.
>
> Precedence rule: **inside a project, uv wins.** A project that pins its
> interpreter with `uv python install <version>` should export
> `UV_MANAGED_PYTHON=1` (in its Makefile, `.envrc`, or bootstrap script), which
> makes uv ignore pyenv shims and system pythons entirely. `uv python list` shows
> what uv actually resolves. pyenv stays for everything outside such a project.
>
> No interpreter is declared in `modules/common.nix` itself for the same reason:
> another python on `PATH` would only add a candidate to that race. One does
> arrive indirectly - `modules/agent-tooling/caveman.nix` declares `pkgs.python3`
> because the caveman-compress skill ships Python scripts - and the `PATH`
> ordering below is arranged so it never displaces pyenv or the system python.

### PATH precedence

The zsh `initContent` in [`modules/common.nix`](modules/common.nix) initialises
pyenv, Homebrew and nvm, and each of those **prepends** to `PATH`. Left alone
they land in front of the profile home-manager builds, which is where every
Nix-declared binary lives - so an `npm i -g` copy of a CLI this flake pins would
win. It did: `lavish-axi` resolved to an npm global while the flake pinned a
different version.

The blocks are therefore ordered so the resulting `PATH` reads:

```
pyenv shims  >  Homebrew  >  ~/.local/bin  >  ~/.cargo/bin  >  ~/.bun/bin
  >  Nix profile  >  nvm  >  ~/.yarn/bin  >  system
```

Read it as three rules:

- **Nix beats the global-install dirs.** `~/.nvm/versions/node/<v>/bin` is where
  stray `npm i -g` binaries land, and `~/.yarn/bin` is the yarn-v1 equivalent, so
  both sit *below* the Nix profile even though `~/.yarn/bin` is a
  `home.sessionPath` entry. nvm still owns Node itself - no
  `node`/`npm`/`npx`/`corepack` is declared anywhere in this flake.
- **pyenv and Homebrew keep Python.** They stay *above* the Nix profile. The only
  names in both `/opt/homebrew/bin` and the Nix profile are the Python family
  (`python3`, `pydoc3`, `idle3`, `python3-config`), and `pyenv global system`
  resolves through `PATH` - hoisting Nix over Homebrew would silently swap the
  system interpreter. Python belongs to pyenv/uv, per the note above. This is one
  of two bounded places "Nix-declared wins" is deliberately not absolute; if a
  Nix-declared CLI ever gains a same-named brew, that ordering has to be
  revisited.
- **Three `home.sessionPath` dirs keep their own tools.** `~/.local/bin`,
  `~/.cargo/bin` and `~/.bun/bin` stay above the Nix profile, exactly as
  home-manager orders them. `~/.local/bin` holds self-updating agent runtimes
  that are *not* Nix-declared and must win (`claude`, `codex`, `cursor-agent`,
  `no-mistakes`, `treehouse`) - demoting it would let a stale or missing Nix
  entry shadow the live runtime, which is worse than the latent shadowing it
  would prevent. `~/.cargo/bin` and `~/.bun/bin` keep rustup and bun managing
  their own toolchains, and since `rustup` and `bun` *are* declared in the shared
  CLI set, that is the second bounded exception to "Nix-declared wins" alongside
  Python. `~/.yarn/bin` is excluded from this hoist for the reason in the first
  rule.

Nothing beyond the overlaps listed above collides, so the ordering changes
resolution for only the CLIs this flake pins.

> **One-time host cleanup.** The ordering fix makes the pinned build win even
> while a same-named npm global is installed, but leaving the duplicates around
> is still confusing (`npm ls -g` disagrees with `command -v`) and they keep
> self-updating. After the next `rebuild`, remove them once:
>
> ```sh
> npm uninstall -g lavish-axi tasks-axi
> ```
>
> Run it in a normal shell on the host, per Node version that has them - nvm
> keeps a separate global prefix for each, so `nvm use <version>` and repeat if
> more than one is installed. Check with `npm ls -g --depth=0` before and after;
> `npm prefix -g` shows which prefix you are operating on. Do **not** remove
> `quota-axi` - it is an npm global this flake does not declare, so it is the
> real source for that command.

---

## Flake inputs

The three core inputs track the **26.05 release train**, not a rolling
development head. A `rebuild` therefore picks up backported fixes for a stable
package set instead of whatever landed upstream that morning.

| Input | Ref | Why this ref |
| --- | --- | --- |
| `nixpkgs` | `nixos-26.05` | The **general** 26.05 channel - serves macOS, Linux and WSL from one package set |
| `nix-darwin` | `nix-darwin-26.05` | Matching release branch |
| `home-manager` | `release-26.05` | Matching release branch |

> [!IMPORTANT]
> `nixpkgs` must **not** be switched to `nixpkgs-26.05-darwin`. That channel is
> macOS-only, and this repo serves Linux and WSL from the same input. There is
> no `nixpkgs-26.05` branch upstream - the non-darwin release branch is named
> `nixos-*`, which is why the ref reads `nixos-26.05` rather than `nixpkgs-*`.

The bootstrap `nix run` invocations in `install.sh` (first-pass `darwin-rebuild`
on macOS, first-pass `home-manager` on Linux/WSL) are pinned to these same refs,
so the tool that performs the very first activation matches the flake it is
activating. `tests/install_test.sh` reads the refs straight out of `flake.nix`
and asserts that `install.sh` and this README's bootstrap command both match, so
bumping the release train means editing `flake.nix`, `install.sh`, the documented
bootstrap command and this table together - the test assertions themselves follow
`flake.nix` on their own.

`nix-homebrew` is pinned to an explicit **commit** rather than a branch: it
publishes no release channel and no tags at all, so there is no ref to follow.
Bumping it is therefore a deliberate, manual edit of the rev in `flake.nix` -
`nix flake update` cannot move it. `herdr` stays on its own release tag and
`nixgl` follows its upstream default; both are unaffected.

`nix flake update` bumps within these branches. Moving to the next release means
changing the refs, not running an update.

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
files/                    dotfiles symlinked by home-manager (nvim, wezterm, herdr, agent cfg)
install.sh                POSIX entry point: macOS + Linux + inside-WSL
install.ps1               Windows: enable WSL2, install distro, hand to install.sh
lib/prompt.sh             shared prompt/detect helpers
tests/install_test.sh     hermetic PATH-masked stub test
docs/
  NIX_PACKAGES.md         full inventory of what this flake installs, per module
  CROSS_PLATFORM_PLAN.md  the design/build plan this repo was cut from
  blog.md                 write-up of the macOS-only predecessor
CONTRIBUTING.md           setup, how to validate a change, pull request expectations
SECURITY.md               private vulnerability reporting, secret handling
LICENSE                   MIT-0 (MIT No Attribution)
```

---

## License

[MIT-0](LICENSE) (MIT No Attribution). Use, copy, modify, and redistribute
freely; no attribution required, no warranty given.

---

## Contributing

Contributions are welcome - see [`CONTRIBUTING.md`](CONTRIBUTING.md) for setup,
the eval commands that validate a change on both surfaces, and what a pull
request should carry. Security problems go through
[`SECURITY.md`](SECURITY.md), never a public issue.

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
  home-manager switch -b backup --impure --flake ~/dotfiles#<username>
```
