{ config, pkgs, lib, ... }:

let
  version = "1.9.1";
  rev = "0d95a81d35a9f2d123a5e9430d1cfc43d55f1bb0"; # tag v1.9.1

  # Caveman hooks are pure Node (no npm deps), so any Node >=18 runs them. Pin
  # nodejs_22 to match axi-packages.nix (pinned nixpkgs' default 24.x SIGKILLs
  # under Darwin *install* load; harmless here, but one Node story).
  nodejs = pkgs.nodejs_22;

  # The whole caveman tree, pinned. Version bump: change version + rev, set hash
  # to pkgs.lib.fakeHash, rebuild to surface the real hash.
  src = pkgs.fetchFromGitHub {
    owner = "juliusbrussee";
    repo = "caveman";
    inherit rev;
    hash = "sha256-VqRHx3/4SSCnEh3cUJ/he5saIfwNhS0hOzoH/wwtU2o=";
  };

  # Package the tree into the store and expose the two Claude Code hook
  # entrypoints as bare-name executables on PATH, each wrapped with pinned Node
  # and defaulting CAVEMAN_DEFAULT_MODE=lite (belt-and-suspenders with the
  # sessionVariable below; --set-default lets an explicit shell export win).
  # Bare names stay stable across version bumps, so committed settings.json /
  # hooks.json never reference a /nix/store path - same convention as the AXI
  # SessionStart hooks and the rtk PreToolUse hook. Pure Node, so it builds
  # identically on macOS and Linux/WSL.
  caveman = pkgs.stdenv.mkDerivation {
    pname = "caveman";
    inherit version src;
    nativeBuildInputs = [ pkgs.makeWrapper ];
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/lib/caveman"
      cp -R . "$out/lib/caveman/"
      makeWrapper ${nodejs}/bin/node "$out/bin/caveman-activate" \
        --add-flags "$out/lib/caveman/src/hooks/caveman-activate.js" \
        --set-default CAVEMAN_DEFAULT_MODE lite
      makeWrapper ${nodejs}/bin/node "$out/bin/caveman-mode-tracker" \
        --add-flags "$out/lib/caveman/src/hooks/caveman-mode-tracker.js" \
        --set-default CAVEMAN_DEFAULT_MODE lite
      runHook postInstall
    '';
    meta = {
      description = "Ultra-compressed agent communication mode (skills + hooks)";
      homepage = "https://github.com/juliusbrussee/caveman";
      license = lib.licenses.mit;
      platforms = lib.platforms.unix;
    };
  };

  # The 7 skills live at the repo top-level skills/ dir (richer than the plugin's
  # subset; caveman-compress ships its Python scripts there).
  skillNames = [
    "caveman" "caveman-commit" "caveman-compress"
    "caveman-help" "caveman-review" "caveman-stats" "cavecrew"
  ];

  # tier 1: Nix owns store-backed skill dirs under ~/.agents/skills (the shared
  # cross-agent dir Codex + Claude Code read), matching axi.nix.
  agentSkillLinks = lib.listToAttrs (map (n: {
    name = ".agents/skills/${n}";
    value.source = "${caveman}/lib/caveman/skills/${n}";
  }) skillNames);

  # tier 2: ~/.claude/skills/<name> -> ~/.agents/skills/<name> indirection.
  claudeSkillLinks = lib.listToAttrs (map (n: {
    name = ".claude/skills/${n}";
    value.source = config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/.agents/skills/${n}";
  }) skillNames);

  # cavecrew subagent defs -> ~/.claude/agents so /cavecrew can spawn them.
  cavecrewAgents = lib.listToAttrs (map (a: {
    name = ".claude/agents/${a}.md";
    value.source = "${caveman}/lib/caveman/plugins/caveman/agents/${a}.md";
  }) [ "cavecrew-builder" "cavecrew-investigator" "cavecrew-reviewer" ]);
in
{
  # Hook wrappers on PATH; python3 for the caveman-compress skill's scripts.
  home.packages = [ caveman pkgs.python3 ];

  # Auto-activate lite every session. CAVEMAN_DEFAULT_MODE is the highest-priority
  # source in caveman-config.js getDefaultMode(), so SessionStart starts at lite;
  # an in-session `/caveman ultra` reads the command arg directly and still wins.
  home.sessionVariables.CAVEMAN_DEFAULT_MODE = "lite";

  home.file = agentSkillLinks // claudeSkillLinks // cavecrewAgents;
}
