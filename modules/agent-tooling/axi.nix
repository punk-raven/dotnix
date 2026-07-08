{ config, pkgs, lib, ... }:

let
  axi = import ./axi-packages.nix { inherit pkgs; };

  # The remote-debugging launcher differs per platform: macOS opens the app
  # bundle via `open`, Linux execs the browser binary directly. Both expose the
  # same `brave-cdp` helper chrome-devtools-axi attaches to on :9222.
  braveCdp =
    if pkgs.stdenv.isDarwin then ''
      # Launch Brave with remote debugging so chrome-devtools-axi can attach:
      #   brave-cdp ; then CHROME_DEVTOOLS_AXI_BROWSER_URL=http://127.0.0.1:9222 chrome-devtools-axi open <url>
      brave-cdp() {
        open -na "Brave Browser" --args --remote-debugging-port=9222 "$@"
      }
    '' else ''
      # Launch Brave/Chromium with remote debugging so chrome-devtools-axi can
      # attach on :9222. Uses whichever of brave/brave-browser/chromium is on PATH.
      brave-cdp() {
        for b in brave brave-browser chromium chromium-browser google-chrome; do
          if command -v "$b" >/dev/null 2>&1; then
            "$b" --remote-debugging-port=9222 "$@" & return
          fi
        done
        echo "brave-cdp: no brave/chromium binary found on PATH" >&2
        return 1
      }
    '';
in
{
  # Agent wiring has two tiers, both declarative:
  #   1. On-demand skills - the ".agents/skills" + ".claude/skills" symlinks below.
  #   2. Ambient AXI SessionStart hooks (AXI spec s7) - these run each CLI's
  #      content-first home view at session start so agents get live state up
  #      front. Those hooks can only live in the agents' own config files, so they
  #      are declared there, invoking the bare binary names put on PATH here
  #      (stable across version bumps, unlike the store paths `<cli> setup hooks`
  #      would hardcode):
  #        - Claude Code: files/.claude/settings.json  (hooks.SessionStart)
  #        - Codex:       files/.codex/hooks.json + files/.codex/config.toml
  #      Both are symlinked into place by modules/common.nix. Do NOT run
  #      `<cli> setup hooks` - it writes version-pinned /nix/store paths that
  #      break on the next rebuild.
  #
  # The three CLIs go on PATH. chrome-devtools-mcp is the engine consumed via
  # CHROME_DEVTOOLS_AXI_MCP_PATH (below), not a user-facing command, so it is
  # kept off PATH (it ships a generically-named `chrome-devtools` bin); the
  # sessionVariable reference below keeps it in the generation closure.
  home.packages = [ axi.gh-axi axi.chrome-devtools-axi axi.lavish-axi ];

  home.file = {
    # tier 1: Nix owns the store-backed skill dirs under ~/.agents/skills
    ".agents/skills/gh-axi".source = "${axi.gh-axi}/lib/gh-axi/skills/gh-axi";
    ".agents/skills/chrome-devtools-axi".source =
      "${axi.chrome-devtools-axi}/lib/chrome-devtools-axi/skills/chrome-devtools-axi";
    ".agents/skills/lavish".source = "${axi.lavish-axi}/lib/lavish-axi/skills/lavish";

    # tier 2: discovery indirection ~/.claude/skills/<name> -> ~/.agents/skills/<name>
    ".claude/skills/gh-axi".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.agents/skills/gh-axi";
    ".claude/skills/chrome-devtools-axi".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.agents/skills/chrome-devtools-axi";
    ".claude/skills/lavish".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.agents/skills/lavish";
  };

  home.sessionVariables.CHROME_DEVTOOLS_AXI_MCP_PATH =
    "${axi.chrome-devtools-mcp}/lib/node_modules/chrome-devtools-mcp/build/src/bin/chrome-devtools-mcp.js";

  programs.zsh.initContent = lib.mkAfter braveCdp;
}
