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
    version = "0.1.30";
    binPath = "dist/bin/gh-axi.js";
    srcHash = "sha256-E9SahmNcpY2a1Uy5CqLe3A5BIv1ecO/xZtZd6zGpv5c=";
    pnpmHash = "sha256-2vlp9u0I8gb5/VGEQwS9Z57/wOMzV+YW6U+/JL482d0=";
  };

  chrome-devtools-axi = mkAxi {
    pname = "chrome-devtools-axi";
    version = "0.1.29";
    binPath = "dist/bin/chrome-devtools-axi.js";
    srcHash = "sha256-ZiEtrZDvWV4xpIb68R0BE7H86pWuwm9QRV0o9JmAh8I=";
    pnpmHash = "sha256-MhpAmNmUAB8M0p8AlJpw80iRgWIdvKOjv88XAjFqYaU=";
  };

  lavish-axi = mkAxi {
    pname = "lavish-axi";
    version = "0.1.46";
    binPath = "dist/cli.mjs";
    # lavish's `pnpm build` = node scripts/build.js (mkAxi's default buildScript runs it)
    srcHash = "sha256-TqZUe+55a02+ov08X9ZEoFIIzhSfBaNM/SmJVsS7ydk=";
    pnpmHash = "sha256-y4KeFqPF02TBSlP1mgyj5UFx0Q98ip890xYkBAYF4qY=";
  };

  tasks-axi = mkAxi {
    pname = "tasks-axi";
    version = "0.2.5";
    binPath = "dist/bin/tasks-axi.js";
    srcHash = "sha256-obwgvKls8GljbUdFrl7ht9+k0AEQjdqvLGf4UHscv+M=";
    pnpmHash = "sha256-BtnZnvjHsPRchvlsy1vhkTf4+aYlx97Eh6RyjWpKcLg=";
  };

  quota-axi = mkAxi {
    pname = "quota-axi";
    version = "0.1.19";
    binPath = "dist/bin/quota-axi.js";
    srcHash = "sha256-2sE3inYm2rIt+A9jz8/UzSGp7XJ8sGQ4hqaUM3EP/ac=";
    pnpmHash = "sha256-5r9osgZibmqfjEHExoPLLVXSeebjrn7XWrv8J/FYhwc=";
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
    # The "bundle" script's rollup pass is memory-heavy. Node 22 auto-sizes
    # V8's old-space limit from *available* RAM; under WSL2 the reported
    # figure is small (WSL defaults to ~50% of Windows RAM and under-reports),
    # so V8 caps the heap low and rollup dies with "Reached heap limit
    # Allocation failed - JavaScript heap out of memory". Pin a fixed 4 GB
    # heap so the build is deterministic across hosts regardless of how much
    # RAM the sandbox thinks it has.
    NODE_OPTIONS = "--max-old-space-size=4096";
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
