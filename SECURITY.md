# Security Policy

## Reporting a Vulnerability

Please **do not** open a public issue for security problems.

Report vulnerabilities privately through GitHub's
[Private Vulnerability Reporting](https://github.com/punk-raven/dotnix/security/advisories/new)
(Security tab -> "Report a vulnerability"). You will receive an acknowledgement
within a few days.

## Scope

This repository contains cross-platform Nix dotfiles (macOS, Linux, WSL2) and
installer scripts. Security-relevant areas include:

- `install.sh` / `install.ps1` - bootstrap scripts that run with user privileges.
- `flake.nix` / `flake.lock` - pinned dependency inputs.
- `modules/` - system and agent-tooling configuration.

## Handling Secrets

Do **not** commit secrets. This repo is public and has GitHub secret scanning
with push protection enabled. Per-user identity lives in `config.nix`, which is
kept **outside** the repo (`~/.config/dotnix/config.nix`) and read impurely by
the flake, so it is never committed. Even so, `config.nix` is for non-secret
identity only (name, email, paths); never place tokens, keys, or passwords in it
or any tracked file. Keep real secrets in your local environment or an ignored
file.

## Supported Versions

The latest tagged release and `main` receive fixes. Older tags are not
maintained.
