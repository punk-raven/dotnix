{ config, pkgs, lib, ... }:

let
  version = "1.3.0";

  # CodeGraph (https://github.com/colbymchenry/codegraph): a local, pre-indexed
  # code knowledge graph (SQLite + tree-sitter) that exposes an MCP server so
  # coding agents get surgical context (symbols, call paths, blast radius) in one
  # `codegraph_explore` call instead of file-by-file exploration. Also a CLI
  # (`codegraph index|serve|...`).
  #
  # Distributed as a self-contained GitHub-release bundle: a ~120MB vendored Node
  # runtime + the compiled TS app + a tiny POSIX `bin/codegraph` launcher that
  # resolves its own symlinks and execs `<bundle>/node lib/dist/bin/codegraph.js`.
  # Nothing to compile. Per-system prebuilt bundle selector below, sha256-pinned
  # via fetchurl -> reproducible with no build. The vendored node is
  # adhoc/linker-signed, so `dontFixup` keeps Nix from stripping it and
  # invalidating the signature.
  #
  # Do NOT `npm i -g @colbymchenry/codegraph`, run install.sh, or `codegraph
  # upgrade` - a bare npm/curl install drifts out of Nix's control. This module
  # is the single source of truth; bump the version here instead.
  #
  # Version bump: change `version`, set the relevant hash to pkgs.lib.fakeHash,
  # rebuild to surface the real SRI hash. To grab a hash directly:
  #   nix store prefetch-file --json \
  #     https://github.com/colbymchenry/codegraph/releases/download/v<VER>/<asset>.tar.gz
  sources = {
    "aarch64-darwin" = { asset = "codegraph-darwin-arm64"; hash = "sha256-FydS681SY45zT+xknc7Xx7eb+RWfH0ERaDXnJSrQMLQ="; };
    "x86_64-darwin"  = { asset = "codegraph-darwin-x64"; hash = "sha256-ugkT1HBu5Q03cRsm7iqWWN1FfDHg7FBzJlOEH39VZ2s="; };
    "aarch64-linux"  = { asset = "codegraph-linux-arm64"; hash = "sha256-0R//x19TFsrMv7vdVDbS+9eRhJ8hb/VoMIE5knr0/14="; };
    "x86_64-linux"   = { asset = "codegraph-linux-x64"; hash = "sha256-vaVYG+DhNCxROtIvKJv+UFyC+woKQVIAJKh8jq1U1RY="; };
  };
  source = sources.${pkgs.stdenv.hostPlatform.system};

  codegraph = pkgs.stdenv.mkDerivation {
    pname = "codegraph";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://github.com/colbymchenry/codegraph/releases/download/v${version}/${source.asset}.tar.gz";
      inherit (source) hash;
    };

    # Archive has a top-level <asset>/ dir; land inside it.
    sourceRoot = source.asset;
    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/libexec"
      cp -R . "$out/libexec/codegraph"
      # Relative symlink so the launcher's symlink-walk lands on the real bundle
      # dir inside the store (DIR = dirname(realpath($0))/..), matching how
      # upstream install.sh links ~/.local/bin/codegraph -> <bundle>/bin/codegraph.
      mkdir -p "$out/bin"
      ln -s ../libexec/codegraph/bin/codegraph "$out/bin/codegraph"
      runHook postInstall
    '';

    meta = {
      description =
        "Local pre-indexed code knowledge graph + MCP server for coding agents";
      homepage = "https://github.com/colbymchenry/codegraph";
      license = lib.licenses.mit;
      mainProgram = "codegraph";
      platforms = builtins.attrNames sources;
    };
  };
in
{
  # `codegraph` on PATH. Agents reach its MCP server via the bare `codegraph
  # serve --mcp` command. Both agents are wired declaratively (do NOT run
  # `codegraph install` - it mutates agent config out of band):
  #   - Codex:       files/.codex/config.toml  [mcp_servers.codegraph]
  #   - Claude Code: the activation script below (see why it can't be a symlink).
  home.packages = [ codegraph ];

  # Claude Code's global (user-scope) MCP server lives ONLY in ~/.claude.json - a
  # stateful file Claude Code owns and rewrites constantly (auth, project history,
  # migration flags), so it CAN'T be a store symlink like Codex's config.toml.
  # Instead we declaratively *merge* the codegraph entry into it on every
  # activation with jq: idempotent, writes only when the value changes, preserves
  # all existing state, creates the file if absent, and bails (never blocks a
  # rebuild) if the file is unparseable. Top-level mcpServers.codegraph is exactly
  # what `claude mcp add --transport stdio codegraph --scope user -- codegraph
  # serve --mcp` writes; this is the reproducible equivalent. The entry invokes
  # the bare `codegraph` on PATH (stable across version bumps).
  #
  # Caveats worth knowing: (1) add-only - dropping this module leaves the entry
  # orphaned in ~/.claude.json; remove it by hand or `claude mcp remove codegraph
  # -s user`. (2) A live Claude Code session writing ~/.claude.json at the same
  # instant as a rebuild could race; the write is atomic (temp + mv) so the file
  # stays valid JSON, and the next activation re-adds the entry if a concurrent
  # write dropped it.
  home.activation.codegraphClaudeMcp =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      claudeJson="${config.home.homeDirectory}/.claude.json"
      if [ -s "$claudeJson" ]; then cur="$(cat "$claudeJson")"; else cur='{}'; fi
      if new="$(printf '%s' "$cur" | ${pkgs.jq}/bin/jq \
          '.mcpServers.codegraph = {type:"stdio",command:"codegraph",args:["serve","--mcp"],env:{}}' \
          2>/dev/null)"; then
        if [ "$new" != "$cur" ]; then
          printf '%s\n' "$new" > "$claudeJson.codegraph.tmp"
          $DRY_RUN_CMD mv "$claudeJson.codegraph.tmp" "$claudeJson"
          $DRY_RUN_CMD chmod 600 "$claudeJson"
        fi
      else
        echo "codegraph: ~/.claude.json is not valid JSON; skipped Claude Code MCP wiring" >&2
      fi
    '';
}
