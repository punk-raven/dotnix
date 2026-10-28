{ config, pkgs, lib, ... }:

# Railway agent tooling: the declarative equivalent of
#
#     curl -fsSL agents.railway.com | sh
#
# That one-liner is a wrapper for `railway.com/install.sh --agents -y`, which
# (1) downloads the latest `railway` CLI into ~/.railway/bin and tries to append
# a PATH line to the shell rc file, then (2) runs `railway setup agent -y`,
# which copies the `use-railway` skill into every detected agent's skills dir
# and writes a `railway` MCP server (`railway mcp`, the stdio proxy to
# mcp.railway.com) into each agent's MCP config.
#
# Do NOT run that installer here. The rc files are home-manager store symlinks
# (the PATH edit cannot land, which is why the MCP server failed with "railway
# not found in $PATH"), and `setup agent` overwrites the store-symlinked
# ~/.codex/config.toml with a plain file. This module does the same three
# things, pinned:
#   - CLI:   the official prebuilt release binary, hash-pinned per system.
#   - Skill: `use-railway` from railwayapp/railway-skills at a pinned rev,
#            wired with the same two tiers as modules/agent-tooling/axi.nix.
#   - MCP:   Codex in files/.codex/config.toml [mcp_servers.railway]; Claude
#            Code merged into ~/.claude.json by the activation below.
#
# nixpkgs' `railway` is not used: on the 26.05 train it is 4.x, which predates
# `railway setup agent` and the `railway mcp proxy` default.
#
# Version bump (CLI): change `version`, then for each asset
#   gh-axi api repos/railwayapp/cli/releases/tags/v<VER> \
#     | grep -E '^    (name|digest): '
#   nix hash convert --hash-algo sha256 --to sri <hex>
# Version bump (skill): set `skillsRev` to a railway-skills commit, then
#   nix store prefetch-file --json --unpack \
#     https://github.com/railwayapp/railway-skills/archive/<rev>.tar.gz

let
  version = "5.71.0";

  # Linux uses the statically linked musl builds, as upstream install.sh does,
  # so the binary runs unpatched on any distro/WSL.
  sources = {
    "aarch64-darwin" = { target = "aarch64-apple-darwin"; hash = "sha256-NQdI8u30H0ayLF1mzqQpTWYOdkgE4lLdugiiexnNC9E="; };
    "x86_64-darwin"  = { target = "x86_64-apple-darwin"; hash = "sha256-G0HddykmV8gK49/MvnZTu7QLfNyVqPSwbCwfDCoAmRk="; };
    "aarch64-linux"  = { target = "aarch64-unknown-linux-musl"; hash = "sha256-0WCtKgKeqsS0yFASrbZ8H1cJuoH3Mg7bWie+koIR1jg="; };
    "x86_64-linux"   = { target = "x86_64-unknown-linux-musl"; hash = "sha256-Lmgv0t341v355G2dmdmWRv8AIqarsMK8qTARNIomn7k="; };
  };
  source = sources.${pkgs.stdenv.hostPlatform.system};

  railway = pkgs.stdenv.mkDerivation {
    pname = "railway";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://github.com/railwayapp/cli/releases/download/v${version}/railway-v${version}-${source.target}.tar.gz";
      inherit (source) hash;
    };

    # Bare `railway` binary at the archive root.
    sourceRoot = ".";
    dontConfigure = true;
    dontBuild = true;
    # Release binaries are adhoc/linker-signed; stripping on Darwin breaks the
    # signature and the binary refuses to launch.
    dontFixup = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 railway "$out/bin/railway"
      runHook postInstall
    '';

    meta = {
      description = "Railway CLI (deploys, logs, MCP proxy for coding agents)";
      homepage = "https://github.com/railwayapp/cli";
      license = lib.licenses.mit;
      mainProgram = "railway";
      platforms = builtins.attrNames sources;
    };
  };

  skillsRev = "526e95524e964ed326689cbac4464d97a58ab81c";
  railwaySkills = pkgs.fetchFromGitHub {
    owner = "railwayapp";
    repo = "railway-skills";
    rev = skillsRev;
    hash = "sha256-IF5+cAqMNl4MRLLSKIn6Fk2kyMMmZTg3aRv9wd6uVc8=";
  };
in
{
  home.packages = [ railway ];

  # The store binary cannot replace itself, and the CLI's updater tracks an
  # auto-applied skills rev (~/.railway/skills.json) that it can write into
  # ~/.agents/skills behind the flake's back (the failure mode described for
  # `npx skills update` in flake.nix). Bump the pins above instead.
  home.sessionVariables.RAILWAY_NO_AUTO_UPDATE = "1";

  home.file = {
    # tier 1: Nix owns the store-backed skill dir under ~/.agents/skills
    ".agents/skills/use-railway".source = "${railwaySkills}/plugins/railway/skills/use-railway";
    # tier 2: discovery indirection ~/.claude/skills/<name> -> ~/.agents/skills/<name>
    ".claude/skills/use-railway".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.agents/skills/use-railway";
  };

  # Claude Code's user-scope MCP servers live only in ~/.claude.json, a stateful
  # file it rewrites constantly, so the entry is merged in with jq exactly like
  # codegraphClaudeMcp in modules/agent-tooling/codegraph.nix (same caveats:
  # add-only, atomic write, never blocks a rebuild). The value is what
  # `claude mcp add --scope user railway -- railway mcp` writes; it invokes the
  # bare `railway` on PATH, stable across version bumps.
  home.activation.railwayClaudeMcp =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      claudeJson="${config.home.homeDirectory}/.claude.json"
      if [ -s "$claudeJson" ]; then cur="$(cat "$claudeJson")"; else cur='{}'; fi
      if new="$(printf '%s' "$cur" | ${pkgs.jq}/bin/jq \
          '.mcpServers.railway = {type:"stdio",command:"railway",args:["mcp"],env:{}}' \
          2>/dev/null)"; then
        if [ "$new" != "$cur" ]; then
          printf '%s\n' "$new" > "$claudeJson.railway.tmp"
          $DRY_RUN_CMD mv "$claudeJson.railway.tmp" "$claudeJson"
          $DRY_RUN_CMD chmod 600 "$claudeJson"
        fi
      else
        echo "railway: ~/.claude.json is not valid JSON; skipped Claude Code MCP wiring" >&2
      fi
    '';
}
