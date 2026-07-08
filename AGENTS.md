# Working on this repo

Cross-platform Nix dotfiles: one flake, three surfaces (nix-darwin, standalone
home-manager, WSL2 -> Linux path). Per-user values live only in `config.nix`,
which is kept OUTSIDE the repo at `~/.config/dotnix/config.nix` (override with
`$DOTNIX_CONFIG`) and read impurely by the flake, so a real user's values are
never committed. Every module reads them from `cfg` (threaded via specialArgs),
never hardcoded.

## Never run the installer for real here

`install.sh` / `install.ps1` install Nix and activate a real system. NEVER run
them in CI or a dev checkout. All validation is hermetic:

```bash
bash tests/install_test.sh
```

It runs the actual `install.sh` against a PATH-masked sandbox of stub
executables (curl, sh, nix, darwin-rebuild, sudo, git, xcode-select, uname) for
the macOS-fresh, macOS-installed, Linux-fresh, and no-git paths, plus a static
`install.ps1` hand-off check - without touching the network, Nix store,
Homebrew, sudo, or system state. Every intentional write is guarded against
escaping the temp sandbox.

## Validating Nix changes without building

Eval, don't build (building compiles everything). config.nix is read from
outside the flake, so every eval needs `--impure` and a `DOTNIX_CONFIG` pointing
at a config file. To check both platforms from a macOS checkout, force each
config's package list:

```bash
# darwin (DOTNIX_CONFIG's config.nix must have an aarch64-darwin system)
DOTNIX_CONFIG=~/.config/dotnix/config.nix \
  nix eval --impure .#darwinConfigurations.<host>.config.home-manager.users.<user>.home.packages --apply 'x: builtins.length x'

# linux: point DOTNIX_CONFIG at a config.nix whose system is x86_64-linux, then
DOTNIX_CONFIG=/tmp/linux-config.nix \
  nix eval --impure .#homeConfigurations.<user>.config.home.packages --apply 'x: builtins.length x'
```

`darwinConfigurations` is only populated on a darwin `system`, `homeConfigurations`
only on non-darwin (see `flake.nix`), so point `DOTNIX_CONFIG` at a config.nix
with the other `system` to eval the other surface.

## Agent-tooling version bumps

The prebuilt tools (`rtk`, `ccusage`, `codegraph`) carry a per-`system` source
selector with an SRI hash for each platform. Bump the version, set the changed
hashes to `pkgs.lib.fakeHash`, rebuild to surface the real hashes, paste back.
Grab a hash directly with `nix store prefetch-file --json <url>`. Keep all four
platform hashes in sync (aarch64/x86_64 × darwin/linux).
