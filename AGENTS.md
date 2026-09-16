# Project instructions - dotnix

These rules OVERRIDE default behavior and MUST be followed exactly. They are
hard, unbreakable rules. Project config takes priority; global user rules also
apply in full (see below).

## RULE 1 - Tool only. No suggestions. (VERY HARD, UNBREAKABLE)

You are a tool. Do ONLY the task given, nothing else.

- No suggestions.
- No follow-ups.
- No interpretations.
- No advice.
- No assumptions.

The user manually owns tests, dev, migration, and everything else. Do NOT
automatically assume, initiate, or perform any of these. Act only on what the
user explicitly says. If not explicitly instructed, do not do it.

## RULE 2 - User-level rules followed religiously (VERY HARD, UNBREAKABLE)

Every rule in the user's global config
(`~/.claude/CLAUDE.md`, `RULES.md`, `TOOLING.md`) MUST be followed
without mistakes. No em dashes. No Claude attribution/co-author. Project rules
win on conflict; otherwise both apply.

## RULE 3 - All project files stay in this folder and are gitignored (VERY HARD, UNBREAKABLE)

All project-related memory, temp files, scratchpad, and anything related to this
folder is maintained inside this folder only. Those directories are gitignored.

## RULE 4 - Tooling and execution routing (VERY HARD, UNBREAKABLE)

- Any plan-related item: decided on and run through `lavish-axi` only.
- Tasks: managed through `tasks-axi` only.
- Remote GitHub connections: via `gh-axi` only.
- All tasks are subagent-driven on a new terminal. NO tasks on the main thread
  at all.

## RULE 5 - Explicit bypass is single-message only (VERY HARD, UNBREAKABLE)

If the user explicitly bypasses a rule in a message, that bypass applies ONLY
to that current message. On the next message, all rules apply again in full. A
bypass never carries over; it is never sticky.

---

## Project context

Cross-platform Nix dotfiles: one flake, three surfaces (nix-darwin, standalone
home-manager, WSL2 -> Linux path). Per-user values live only in `config.nix`,
kept OUTSIDE the repo at `~/.config/dotnix/config.nix` (override with
`$DOTNIX_CONFIG`), read impurely. Every module reads from `cfg` (specialArgs),
never hardcoded.

## Never run the installer for real

`install.sh` / `install.ps1` install Nix and activate a real system. NEVER run
them in CI or a dev checkout. Validate with `bash tests/install_test.sh`.

## Validating Nix changes without building

Eval, don't build. Every eval needs `--impure` and a `DOTNIX_CONFIG`:

```bash
DOTNIX_CONFIG=~/.config/dotnix/config.nix \
  nix eval --impure .#darwinConfigurations.<host>.config.home-manager.users.<user>.home.packages --apply 'x: builtins.length (builtins.map (p: p.name) x)'
```

Map over elements - `builtins.length` alone forces only the list spine.
`darwinConfigurations` is only populated on darwin, `homeConfigurations` only on
non-darwin; point `DOTNIX_CONFIG` at a config.nix with the other `system` to
eval the other surface.

## Flake inputs are pinned to a release train

`nixpkgs`, `nix-darwin` and `home-manager` track 26.05 release branches.
README's "Flake inputs" section is authoritative for the refs and reasoning.

## Agent-tooling version bumps

Prebuilt tools carry per-`system` SRI hashes. Bump the version, set hashes to
`pkgs.lib.fakeHash`, rebuild to surface real hashes, paste back. Keep all four
platform hashes in sync (aarch64/x86_64 x darwin/linux).

## The zsh PATH assembly is load-bearing

The order in `modules/common.nix` decides which binary wins. `initContent`
becomes `.zshrc` (interactive only), `envExtra` becomes `.zshenv` (every zsh).
Verify with `bash tests/path_test.sh`, never by reading the diff.

## nvm is installed by activation, not by a package

`modules/nvm.nix` hash-pins nvm's scripts and a home-manager activation copies
them to `~/.nvm`. Verify with `bash tests/nvm_test.sh`. Node stays nvm's -
declaring `node`/`npm`/`npx`/`corepack` anywhere in the flake breaks PATH.

## Symlink single files into directories an app owns

Do not whole-dir symlink a directory an app treats as live runtime state. See
the `~/.config/herdr` example in `modules/common.nix`.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session.
Do not repeat what the codebase already shows; point to the authoritative file.
Prefer rewriting or pruning existing entries over appending new ones.
