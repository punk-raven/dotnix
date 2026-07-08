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
    version = "0.1.25";
    binPath = "dist/bin/gh-axi.js";
    srcHash = "sha256-ZTgNscokGpJdo4ATgYHKRtZJ35vkvym80s5Ve1SIdzs=";
    pnpmHash = "sha256-MwXUdWOEW2e/xO+V/JiRM+84RLpnhdHaEGNdJqZ8Llk=";
  };

  chrome-devtools-axi = mkAxi {
    pname = "chrome-devtools-axi";
    version = "0.1.26";
    binPath = "dist/bin/chrome-devtools-axi.js";
    srcHash = "sha256-csjr1T+a9MPNIw4qxk1TIgFUoGjB8jhrZ+oc6ObcDts=";
    pnpmHash = "sha256-PSFZX2bJr1DBCYBsFm8b4UTubSOZRwDVDCCsj+ma3IU=";
  };

  lavish-axi = mkAxi {
    pname = "lavish-axi";
    version = "0.1.36";
    binPath = "dist/cli.mjs";
    # lavish's `pnpm build` = node scripts/build.js (mkAxi's default buildScript runs it)
    srcHash = "sha256-VKI2MUgFvEqh58RRqquFH7tyi4TkkEDfzHeZ6JWgXMw=";
    pnpmHash = "sha256-GrNDegz0sUEAS3JsOZs1pcF1nBg/e6ELJwsQOsHce3I=";
  };

  chrome-devtools-mcp = let version = "1.5.0"; in pkgs.buildNpmPackage {
    pname = "chrome-devtools-mcp";
    inherit version;
    # Task 2 established that pinned pkgs.nodejs (24.x) SIGKILLs under real
    # npm/pnpm install load on Darwin; use the same nodejs_22 pin here.
    nodejs = nodejs;   # the `nodejs = pkgs.nodejs_22;` binding from the let block
    src = pkgs.fetchFromGitHub {
      owner = "ChromeDevTools";
      repo = "chrome-devtools-mcp";
      rev = "chrome-devtools-mcp-v${version}";
      hash = "sha256-qDji1ZA46H3+jEZ5SL7ga/pyRhJ9SAdBWYH1jKC/TVg=";
    };
    npmDepsHash = "sha256-t9PwLvjcUaGFBZpW504+V96TbEVukOp3skomtTFs8cA=";
    # The default `npmBuildScript` ("build" = `tsc && node scripts/post-build.ts`)
    # only type-checks/transpiles; the resulting build/src/*.js still `import`s
    # devDependencies (e.g. urlpattern-polyfill) straight from node_modules,
    # which buildNpmPackage's `npm prune --omit=dev` then removes, breaking
    # the binary at runtime (ERR_MODULE_NOT_FOUND). The package's own "bundle"
    # script (clean -> build -> rollup -> strip build/node_modules -> append
    # lighthouse notices) is what upstream actually publishes to npm - rollup
    # inlines devDependencies into build/src, leaving essentially no runtime
    # node_modules requirement. Verified by diffing against `npm pack
    # chrome-devtools-mcp@1.5.0`: the published build/src is rollup-bundled
    # (minified helper names), matching `npm run bundle` output, not `npm run
    # build` output.
    npmBuildScript = "bundle";
    # prevent puppeteer/chromium download during build:
    PUPPETEER_SKIP_DOWNLOAD = "1";
    # buildNpmPackage always runs `npm ci --ignore-scripts`, so npm's
    # "prepare" lifecycle script (which normally runs on a real
    # `npm install`) never fires. That script is load-bearing: it strips a
    # conflicting `declare global` block that chrome-devtools-frontend and
    # @paulirish/trace_engine both declare, which otherwise makes `tsc` fail
    # with TS2717 ("Subsequent property declarations must have the same
    # type"). Reproduced without this step (both under nix build and with a
    # plain `npm ci --ignore-scripts && npm run build` outside nix, using the
    # same pinned nodejs_22). Run the upstream fixup script itself, verbatim,
    # right before the build runs.
    preBuild = ''
      node scripts/prepare.ts
    '';
  };
}
