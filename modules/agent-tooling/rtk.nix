{ config, pkgs, lib, cfg, ... }:

let
  dotfilesDir = cfg.dotfilesDir;

  version = "0.43.0";

  # RTK (Rust Token Killer): a single statically-linked Rust binary that proxies
  # dev commands (git, cargo, npm, tests, cloud CLIs, ...) and compresses their
  # output before it reaches the model - 60-90% fewer tokens on common ops.
  #
  # We install the official prebuilt release for the host platform, sha256-pinned
  # (still fully reproducible), rather than compiling the Rust crate on every
  # rebuild. Per-system artifact selector - note the Linux asymmetry upstream:
  # x86_64-linux ships musl-only, aarch64-linux gnu-only (the musl build is
  # static and runs anywhere). The prebuilt binaries are adhoc/linker-signed, so
  # `dontFixup` keeps Nix from stripping them and invalidating the signature.
  #
  # Version bump: change `version`, set the relevant hash to pkgs.lib.fakeHash,
  # rebuild to surface the real SRI hash from the mismatch error, paste it back.
  # To grab a hash directly:
  #   nix store prefetch-file --json \
  #     https://github.com/rtk-ai/rtk/releases/download/v<VER>/<asset>.tar.gz
  sources = {
    "aarch64-darwin" = { asset = "rtk-aarch64-apple-darwin"; hash = "sha256-ihfkmsvTeJl+sh0Otvf4YREfNbT8mxx07fTHRI5XbGU="; };
    "x86_64-darwin"  = { asset = "rtk-x86_64-apple-darwin"; hash = "sha256-qF9g4mN4Eb5oNmIIuNi5xbobdIy130R3qyDNc9PF2fg="; };
    "aarch64-linux"  = { asset = "rtk-aarch64-unknown-linux-gnu"; hash = "sha256-VRn3yhLlwUOmCfDSigp3uXQTqNzjHCaB8aQcJFGahzE="; };
    "x86_64-linux"   = { asset = "rtk-x86_64-unknown-linux-musl"; hash = "sha256-/4oed2ZJbhdSkaha7KHcl8n/bfM+UeWJPR+8eP6ipgk="; };
  };
  source = sources.${pkgs.stdenv.hostPlatform.system};

  rtk = pkgs.stdenv.mkDerivation {
    pname = "rtk";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://github.com/rtk-ai/rtk/releases/download/v${version}/${source.asset}.tar.gz";
      inherit (source) hash;
    };

    # The tarball is just the bare `rtk` binary at its root.
    sourceRoot = ".";
    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 rtk "$out/bin/rtk"
      runHook postInstall
    '';

    meta = {
      description =
        "Rust Token Killer - token-compressing CLI proxy for coding agents";
      homepage = "https://github.com/rtk-ai/rtk";
      mainProgram = "rtk";
      platforms = builtins.attrNames sources;
    };
  };

  # The RTK usage doc that `rtk init -g` writes to ~/.claude/RTK.md. Vendored in
  # files/.claude/RTK.md and symlinked next to every agent's AGENTS.md/CLAUDE.md
  # so the `@RTK.md` import (appended to files/AGENTS.md) resolves for each one.
  rtkDoc = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.claude/RTK.md";
in
{
  # `rtk` on PATH - usable directly (`rtk gain`, `rtk git status`) and, more
  # importantly, by the Claude Code PreToolUse hook in files/.claude/settings.json.
  home.packages = [ rtk ];

  # Initialization is fully declarative - the equivalent of `rtk init -g`, but
  # committed instead of run. We deliberately do NOT run `rtk init`: it mutates
  # ~/.claude out-of-band (unreproducible) and can bake machine-specific paths,
  # the same reason we hand-declare the AXI SessionStart hooks (see axi.nix).
  # The three artifacts `rtk init -g` produces are vendored here:
  #   1. PreToolUse hook `{ matcher: "Bash", command: "rtk hook claude" }` in
  #      files/.claude/settings.json - transparently rewrites every Bash command
  #      the agent runs into its rtk-compressed equivalent. It calls the BARE
  #      `rtk` on PATH (stable across version bumps), matching the AXI hook
  #      convention.
  #   2. files/.claude/RTK.md - the rtk usage doc, symlinked below.
  #   3. `@RTK.md` import appended to files/AGENTS.md so agents load that doc.
  home.file = {
    ".claude/RTK.md".source = rtkDoc;
    ".codex/RTK.md".source = rtkDoc;
    ".config/opencode/RTK.md".source = rtkDoc;
  };
}
