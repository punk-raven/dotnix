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
  nix eval --impure .#darwinConfigurations.<host>.config.home-manager.users.<user>.home.packages --apply 'x: builtins.length (builtins.map (p: p.name) x)'

# linux: point DOTNIX_CONFIG at a config.nix whose system is x86_64-linux, then
DOTNIX_CONFIG=/tmp/linux-config.nix \
  nix eval --impure .#homeConfigurations.<user>.config.home.packages --apply 'x: builtins.length (builtins.map (p: p.name) x)'
```

Mapping over the elements matters: `builtins.length` alone forces only the list
spine, so a package attribute that exists on unstable but not on the release
channel would not surface - exactly the failure a channel bump introduces.

`darwinConfigurations` is only populated on a darwin `system`, `homeConfigurations`
only on non-darwin (see `flake.nix`), so point `DOTNIX_CONFIG` at a config.nix
with the other `system` to eval the other surface.

## Flake inputs are pinned to a release train

`nixpkgs`, `nix-darwin` and `home-manager` track 26.05 release branches, not
rolling heads. README's "Flake inputs" section is authoritative for the refs and
the reasoning.

Two traps worth knowing before you touch them:

- nixpkgs' general release branch is named `nixos-<release>`; there is no
  `nixpkgs-<release>`. `nixpkgs-<release>-darwin` exists but is macOS-only and is
  the wrong input here, because one nixpkgs feeds all three surfaces.
- The bootstrap `nix run` refs are duplicated in `install.sh` and `README.md`.
  `tests/install_test.sh` reads the refs out of `flake.nix` and asserts both
  copies match, so bumping the train without bumping them fails the install
  tests.

## Agent-tooling version bumps

The prebuilt tools (`rtk`, `ccusage`, `codegraph`) carry a per-`system` source
selector with an SRI hash for each platform. Bump the version, set the changed
hashes to `pkgs.lib.fakeHash`, rebuild to surface the real hashes, paste back.
Grab a hash directly with `nix store prefetch-file --json <url>`. Keep all four
platform hashes in sync (aarch64/x86_64 × darwin/linux).

## The zsh PATH assembly is load-bearing, and spans two files

pyenv, Homebrew, nvm and the Nix-profile re-assertion in `modules/common.nix`
all *prepend* to `PATH`, so the order those blocks appear in decides which copy
of a binary wins. The contract, and why each block sits where it does, is
"PATH precedence" in `README.md`; the reasoning is repeated inline in
`modules/common.nix`.

Which generated file a block lands in matters as much as its order:
`initContent` becomes `.zshrc`, read by **interactive shells only**, while
`envExtra` becomes `.zshenv`, read by every zsh. So the tail of the order
(profile > nvm > `~/.yarn/bin`) is asserted in both, and `.zshenv` skips its
copy when `__DOTNIX_PATH_ASSEMBLED` says a parent shell already finished the
job - without that, every `zsh -c` from an interactive shell would demote
Homebrew's python3. `home.sessionPath` entries land *above* the profile unless
`demotedSessionPathDirs` excludes them.

Never verify this by reading the diff. `bash tests/path_test.sh` runs a real
zsh against the generated files in a sandboxed `$HOME` for all three shapes
(fresh non-interactive, fresh interactive, non-interactive child of an
interactive shell); it needs `nix` and a `config.nix` and skips without them.

## nvm is installed by activation, not by a package

nixpkgs ships no `nvm` and `$NVM_DIR` must stay writable, so `modules/nvm.nix`
hash-pins nvm's scripts into the store and a home-manager activation copies them
into `~/.nvm`, then has nvm install a pinned LTS Node. Both pins live at the top
of that module; the reasoning and the rejected alternatives are in its header
comment, and "Node and `nvm`" in `README.md` is the user-facing version.
`nodeVersion` is also published as the read-only `dotnix.nvm.nodeVersion` /
`dotnix.nvm.nodeBinDir` options, because `modules/common.nix` needs that bin dir
on `home.sessionPath` to give non-interactive shells a `node`; consume those
rather than re-deriving the path.

The activation logic is `lib/nvm-bootstrap.sh` rather than inline Nix so it can
be run for real - `bash tests/nvm_test.sh` exercises it against a sandboxed
`$HOME` and a stub nvm (hermetic; `DOTNIX_NVM_TEST_ONLINE=1` adds a real-nvm
scenario). It must stay idempotent, network-free once satisfied, and must never
exit non-zero. Node itself stays nvm's: declaring `node`/`npm`/`npx`/`corepack`
anywhere in the flake breaks the PATH contract above, and the test asserts it.

## Symlink single files into directories an app owns

`home.file` in `modules/common.nix` links most dotfile dirs whole, but not a
directory an application treats as live runtime state. `~/.config/herdr` is the
worked example: herdr writes sockets and rotating logs there, and a whole-dir
`mkOutOfStoreSymlink` dangled and killed its startup with `EEXIST`. Only
`.config/herdr/config.toml` is linked, one entry per file - the constraint and
its history are inline at that entry. Apply the same rule to any new app in the
same position.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
