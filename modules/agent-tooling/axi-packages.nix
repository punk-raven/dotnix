{ pkgs }:

let
  # Pinned nixpkgs' default pkgs.nodejs (24.16.0) has a Darwin-specific runtime
  # bug: under the worker-thread-heavy FD churn of a real `pnpm install`
  # (191 deps), it hits an EXC_GUARD kqueue guard violation and gets SIGKILL'd
  # (kernel log: "[node: killed] exiting with signal 9", exit code 137),
  # reproduced consistently through the real `nix build` sandbox. Node 22 from
  # the SAME pinned nixpkgs revision does not exhibit this bug, so pin the
  # whole toolchain (fetch + build + runtime) to it instead. This is still
  # fully pinned/reproducible via the flake's nixpkgs input, not a floating
  # version.
  nodejs = pkgs.nodejs_22;
  pnpm = pkgs.pnpm_11.override { nodejs-slim = pkgs.nodejs-slim_22; };

  mkAxi =
    { pname, version, srcHash, pnpmHash, binPath, buildScript ? "pnpm build" }:
    pkgs.stdenv.mkDerivation (finalAttrs: {
      inherit pname version;

      src = pkgs.fetchFromGitHub {
        owner = "kunchenguid";
        repo = pname;
        rev = "${pname}-v${version}";
        hash = srcHash;
      };

      pnpmDeps = pkgs.fetchPnpmDeps {
        inherit (finalAttrs) pname version src;
        inherit pnpm;
        hash = pnpmHash;
        # See `nodejs`/`pnpm` comment above: current nixpkgs' fetchPnpmDeps
        # requires an explicit fetcherVersion (fetcherVersion 1/2 were
        # removed upstream).
        fetcherVersion = 3;
        # pnpm 11's supply-chain policy rejects lockfile entries it deems
        # "trust downgrades". The build hook already sets this (see
        # pnpm-config-hook.sh), but fetchPnpmDeps runs separately.
        prePnpmInstall = "export pnpm_config_trust_lockfile=true";
      };

      nativeBuildInputs = [ nodejs pnpm pkgs.pnpmConfigHook pkgs.makeWrapper ];

      buildPhase = ''
        runHook preBuild
        ${buildScript}
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        mkdir -p "$out/lib/${pname}" "$out/bin"
        cp -r dist node_modules package.json skills "$out/lib/${pname}/"
        makeWrapper ${nodejs}/bin/node "$out/bin/${pname}" \
          --add-flags "$out/lib/${pname}/${binPath}"
        runHook postInstall
      '';

      meta.mainProgram = pname;
    });
in
{
  gh-axi = mkAxi {
    pname = "gh-axi";
    version = "0.1.43";
    binPath = "dist/bin/gh-axi.js";
    srcHash = "sha256-xHGr9V5Mhw/RTuA0dz3Crc7DgASQdq92bqCkar/4eCE=";
    pnpmHash = "sha256-2vlp9u0I8gb5/VGEQwS9Z57/wOMzV+YW6U+/JL482d0=";
  };

  chrome-devtools-axi = mkAxi {
    pname = "chrome-devtools-axi";
    version = "0.1.44";
    binPath = "dist/bin/chrome-devtools-axi.js";
    srcHash = "sha256-r+W3k58Duwq4Z+Vg0rr6Ma2K6E3LqSs/NiV1jMOcu8g=";
    pnpmHash = "sha256-MhpAmNmUAB8M0p8AlJpw80iRgWIdvKOjv88XAjFqYaU=";
  };

  lavish-axi = mkAxi {
    pname = "lavish-axi";
    version = "0.1.90";
    binPath = "dist/cli.mjs";
    # lavish's `pnpm build` = node scripts/build.js (mkAxi's default buildScript runs it)
    srcHash = "sha256-S+WhKGMaj98pizczXA6HsZqNKPBTCO9MYKxce/WTkNY=";
    pnpmHash = "sha256-kZ//hT7zRQWt/fdd9Wj3NF6Napmrr6L7YVmXbRLVJ2Q=";
  };

  tasks-axi = mkAxi {
    pname = "tasks-axi";
    version = "0.2.6";
    binPath = "dist/bin/tasks-axi.js";
    srcHash = "sha256-nf6KkZEoJ+BD7PeGat/GVk8FQbuAJ0AHR5XuX+bwlZo=";
    pnpmHash = "sha256-BtnZnvjHsPRchvlsy1vhkTf4+aYlx97Eh6RyjWpKcLg=";
  };

  quota-axi = mkAxi {
    pname = "quota-axi";
    version = "0.1.65";
    binPath = "dist/bin/quota-axi.js";
    srcHash = "sha256-TLzGRYEGw1ele+0HOHgHoBFIs7HPDQUsUKj6EzmBfmQ=";
    pnpmHash = "sha256-6iItfcjzCzU2MwEgAsLJrJDG8Rr1TNrWV7/xvJN+fPc=";
  };

  # The engine chrome-devtools-axi drives through CHROME_DEVTOOLS_AXI_MCP_PATH
  # (axi.nix). It must be 1.8.0 or newer: chrome-devtools-axi sends `pageId` on
  # every page-scoped tool call, and only 1.8.0+ accepts it by default
  # (`--pageIdRouting`, on by default; 1.7.0 had it behind
  # --experimentalPageIdRouting). 1.6.0 rejects it: "Unknown argument for tool
  # take_snapshot: pageId".
  #
  # Installed from the registry tarball, not built from source: since v1.7.0
  # the repo carries devtools-frontend as a git submodule whose nested
  # submodules live on chrome-internal.googlesource.com (requires Google
  # auth), so a source build cannot fetch them. The published tarball is the
  # rollup bundle upstream ships (`npm run bundle`) and declares no
  # dependencies, so it runs as-is - the same files `npx chrome-devtools-mcp`
  # installs. To bump: change version, then
  #   nix store prefetch-file --hash-type sha256 <tarball url>  -> hash
  chrome-devtools-mcp = let version = "1.12.0"; in pkgs.stdenvNoCC.mkDerivation {
    pname = "chrome-devtools-mcp";
    inherit version;
    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/chrome-devtools-mcp/-/chrome-devtools-mcp-${version}.tgz";
      hash = "sha256-Sq3jFnw+eBx5fWEJ7WA6DKW4yzY6KJ4uqsqpsMXSo2A=";
    };
    dontBuild = true;
    # Same layout as an npm global install, so the path axi.nix exports is
    # stable across bumps. chrome-devtools-axi runs it with its own node
    # (nodejs_22 above), so no wrapper or shebang patching is needed.
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/lib/node_modules/chrome-devtools-mcp"
      cp -R . "$out/lib/node_modules/chrome-devtools-mcp/"
      runHook postInstall
    '';
  };
}
