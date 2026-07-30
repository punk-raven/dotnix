# Summary

<!-- What changes, and why. One logical change per pull request. -->

## Surfaces affected

<!-- Delete what does not apply. Windows runs the Linux path under WSL2. -->

- [ ] macOS (nix-darwin)
- [ ] Linux (standalone home-manager)
- [ ] Windows / WSL2
- [ ] Docs or repo tooling only

## What I ran

<!--
Paste the actual commands and their outcome. See CONTRIBUTING.md for the full
commands. Evaluate, do not build. Never run install.sh for real in a checkout.
-->

```
```

- [ ] `nix eval` succeeds on the **darwin** surface
- [ ] `nix eval` succeeds on the **linux** surface
- [ ] `bash tests/install_test.sh` passes (required if `install.sh`,
      `install.ps1`, or the bootstrap refs in `flake.nix` / `README.md` changed)

## Checklist

- [ ] No per-user value is hardcoded; anything user-specific is read from `cfg`
- [ ] No secrets, tokens, or real `config.nix` contents committed
- [ ] `README.md` updated if documented behaviour changed
- [ ] No auto-generated file hand-edited
- [ ] If the zsh `initContent` block order changed, I diffed `command -v` for the
      affected tools between the old and new generated `.zshrc`

## Notes

<!-- Anything a reviewer should know: trade-offs, follow-ups, things left out. -->
