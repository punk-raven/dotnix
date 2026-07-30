# Contributing

Contributions are welcome - bug reports, fixes, new packages, and documentation
all help. This is a personal-scale dotfiles repo, so the bar is "does it stay
correct on all three surfaces", not "does it match a house style".

## Before you start

Read [`AGENTS.md`](AGENTS.md). It is short and covers the traps that cause most
of the breakage here: per-user values live only in `config.nix` (kept **outside**
the repo), the installer must never be run for real in a checkout, and the zsh
`initContent` block order is load-bearing for `PATH` precedence.

For anything larger than a one-line fix, open an issue first so the approach can
be agreed before you spend time on it.

## Development setup

You do not need to activate the flake to work on it. You need Nix with flakes
enabled and a `config.nix` to evaluate against - copy
[`config.example.nix`](config.example.nix) to `~/.config/dotnix/config.nix` (or
anywhere, and point `$DOTNIX_CONFIG` at it).

```bash
mkdir -p ~/.config/dotnix
cp config.example.nix ~/.config/dotnix/config.nix
$EDITOR ~/.config/dotnix/config.nix
```

**Never run `install.sh` or `install.ps1` from a checkout.** They install Nix and
activate a real system. All installer validation is hermetic - see below.

## Validating a change

Three checks cover nearly everything. Run whichever apply, and record what you
ran in your pull request.

**1. Evaluate the flake - do not build it.** Building compiles the world;
evaluating catches the failures that actually matter (a package that exists on
one channel but not another, a broken module reference). `config.nix` is read
from outside the flake, so every eval needs `--impure` and a `DOTNIX_CONFIG`.

```bash
# darwin surface (needs a config.nix whose system is aarch64-darwin)
DOTNIX_CONFIG=~/.config/dotnix/config.nix \
  nix eval --impure .#darwinConfigurations.<host>.config.home-manager.users.<user>.home.packages \
  --apply 'x: builtins.length (builtins.map (p: p.name) x)'

# linux surface (needs a config.nix whose system is x86_64-linux)
DOTNIX_CONFIG=/tmp/linux-config.nix \
  nix eval --impure .#homeConfigurations.<user>.config.home.packages \
  --apply 'x: builtins.length (builtins.map (p: p.name) x)'
```

Mapping over the elements matters: `builtins.length` alone forces only the list
spine, so a package attribute missing on one channel would not surface.

`darwinConfigurations` is only populated on a darwin `system` and
`homeConfigurations` only on non-darwin, so evaluating both surfaces means
pointing `DOTNIX_CONFIG` at two different config files.

**2. Installer tests**, if you touched `install.sh`, `install.ps1`, or the
bootstrap refs in `flake.nix` / `README.md`:

```bash
bash tests/install_test.sh
```

It runs the real `install.sh` against a PATH-masked sandbox of stub executables,
so it never touches the network, the Nix store, Homebrew, sudo, or system state.

**3. Shell/`PATH` changes.** If you reorder or add a block in the zsh
`initContent` in `modules/common.nix`, verify by diffing `command -v` for the
affected tools between the old and new generated `.zshrc` - not by reading the
diff. The contract is documented under "PATH precedence" in `README.md`.

## Scope conventions

- Anything shared by macOS, Linux, and WSL goes in `modules/common.nix`.
- Platform-only packages go in `modules/darwin.nix` or `modules/linux.nix`.
  Windows has no module of its own; it runs the Linux path under WSL2.
- Dotfiles in `files/` are linked out-of-store, so edits take effect without a
  rebuild. Symlink **single files** into directories an application owns as
  runtime state - see the `~/.config/herdr` note in `modules/common.nix` for
  what a whole-directory symlink breaks.
- Never hardcode a per-user value. Read it from `cfg`.
- Do not hand-edit auto-generated files.

## Pull requests

- One logical change per pull request.
- Keep commits scoped; [Conventional Commits](https://www.conventionalcommits.org)
  style (`feat:`, `fix:`, `docs:`, `chore:`) matches the existing history.
- Fill in the pull request template, including what you actually ran.
- If your change alters documented behaviour, update `README.md` in the same
  pull request. `README.md` is authoritative for flake inputs and `PATH`
  precedence.

## Security

Do not report vulnerabilities through issues or pull requests. Follow
[`SECURITY.md`](SECURITY.md).
