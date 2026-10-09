{ pkgs }:

# Published npm CLIs that have no nixpkgs package, built straight from the
# registry tarball.
#
# Why this exists separately from agent-tooling/axi-packages.nix: `mkAxi` there
# is hardcoded to the `kunchenguid` GitHub monorepo and builds from source with
# pnpm. These are third-party CLIs published to npm as prebuilt `dist/` output,
# so there is nothing to build - only a dependency closure to pin.
#
# The awkward part is that npm's published tarballs carry no lockfile, and
# `buildNpmPackage` needs one to produce a fixed-output `npmDeps`. So each
# package gets a lockfile generated once and vendored under ./locks. To add or
# bump one:
#
#   1. curl the tarball, `nix hash file --sri --type sha256 <tgz>`  -> tarballHash
#   2. extract it, `jq 'del(.devDependencies) | del(.scripts)'` over package.json,
#      then `npm install --package-lock-only --ignore-scripts`
#   3. copy the resulting package-lock.json to ./locks/<pname>-<version>.json
#   4. set npmDepsHash to pkgs.lib.fakeHash, build, paste the real hash back
#
# Step 2 must strip devDependencies before generating the lock, and mkNpmCli
# repeats that strip at build time so `npm ci` still validates the lock against
# package.json. It is not just pruning for size: vercel's devDependencies
# reference `@vercel-internals/*`, which are private and 404 on the public
# registry, so a full-tree lock cannot be resolved at all. Dropping "scripts"
# with them keeps a stray lifecycle hook from running during `npm ci`.

let
  # Same pin, same reason as agent-tooling/axi-packages.nix: the pinned
  # nixpkgs' default nodejs (24.x) gets SIGKILL'd by an EXC_GUARD kqueue guard
  # violation under real npm install load on Darwin. Node 22 from the same
  # revision does not.
  nodejs = pkgs.nodejs_22;

  # `npmName` is the registry name, `pname` the Nix-safe attribute name. They
  # differ for scoped packages: "@playwright/cli" is not a usable pname, and its
  # tarball lives at <scope>/<name>/-/<name>-<version>.tgz - the scope appears in
  # the path but NOT in the filename.
  mkNpmCli =
    { pname, version, tarballHash, npmDepsHash, lock, npmName ? pname }:
    let
      tarballName = builtins.baseNameOf npmName;

      # The registry tarball plus the vendored lock, with devDependencies and
      # scripts stripped so `npm ci` sees exactly the tree the lock describes.
      src = pkgs.stdenvNoCC.mkDerivation {
        pname = "${pname}-src";
        inherit version;

        src = pkgs.fetchurl {
          url = "https://registry.npmjs.org/${npmName}/-/${tarballName}-${version}.tgz";
          hash = tarballHash;
        };

        nativeBuildInputs = [ pkgs.jq ];
        dontBuild = true;

        installPhase = ''
          runHook preInstall
          mkdir -p "$out"
          cp -R . "$out/"
          jq 'del(.devDependencies) | del(.scripts)' package.json > "$out/package.json"
          cp ${lock} "$out/package-lock.json"
          runHook postInstall
        '';
      };
    in
    pkgs.buildNpmPackage {
      inherit pname version src npmDepsHash nodejs;

      # The tarball already ships built `dist/` output - there is no build step,
      # and "scripts" was stripped above, so there is no build script to call.
      dontNpmBuild = true;

      meta.mainProgram = pname;
    };
in
{
  vercel = mkNpmCli {
    pname = "vercel";
    version = "63.1.0";
    tarballHash = "sha256-l41Dk7Ii/RzYqalMj7PA46xKDhwPn6FHu1Iah9/RJPo=";
    npmDepsHash = "sha256-5wUfxV6CaJFC5i555uHOULyE6HmAm60P4BomZ/1RBss=";
    lock = ./locks/vercel-63.1.0.json;
  };

  playwright-cli = mkNpmCli {
    pname = "playwright-cli";
    npmName = "@playwright/cli";
    version = "0.1.22";
    tarballHash = "sha256-u0hAvhcAbit7qFYiTcMGL2Vx1fZHNSR2+Vxed/9dZ5o=";
    npmDepsHash = "sha256-HHW0EKGodJs6E6oBUrqi0ScYrbVViufSrbPOaChj4ps=";
    lock = ./locks/playwright-cli-0.1.22.json;
  };

  tanstack-cli = mkNpmCli {
    pname = "tanstack-cli";
    npmName = "@tanstack/cli";
    version = "0.71.1";
    tarballHash = "sha256-RI4MCwdwDiW1Gha2xPwHiqdNLF+Hnyy9bjJx2rxQkQ0=";
    npmDepsHash = "sha256-P09u3c/SsiRCPw0alXA6d7EZOH0cMYb62eNXSChL1Zo=";
    lock = ./locks/tanstack-cli-0.71.1.json;
  };

  clerk = mkNpmCli {
    pname = "clerk";
    version = "3.4.1";
    tarballHash = "sha256-ysXV1SyZvdf6bUSjP6eFCOdjUGHE12B7xVYjyZvmZwM=";
    npmDepsHash = "sha256-USfWsb5UkOs20p2dNxCLsfMNGkDRNWaI/DGGED+A6Ok=";
    lock = ./locks/clerk-3.4.1.json;
  };


  gnhf = mkNpmCli {
    pname = "gnhf";
    version = "0.1.51";
    tarballHash = "sha256-8rrtCWz0npY+V4tsd37SESPlIfElAN69lCIend0Yoew=";
    npmDepsHash = "sha256-jJiO8OK8v8lE+IKNhl8PZXFm+12LwJu5Ihjpmzu/Tj0=";
    lock = ./locks/gnhf-0.1.51.json;
  };
}
