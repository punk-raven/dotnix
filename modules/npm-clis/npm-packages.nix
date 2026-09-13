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
    version = "59.16.0";
    tarballHash = "sha256-WEl7g9pY8Sci2NW75M1rOWW5GFB4meRZ/upK9KVxd3E=";
    npmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    lock = ./locks/vercel-59.16.0.json;
  };

  playwright-cli = mkNpmCli {
    pname = "playwright-cli";
    npmName = "@playwright/cli";
    version = "0.1.19";
    tarballHash = "sha256-Cm/KBjcfp+ab4z9nMPeNe91p0Dc5AEXEBQ6WHosd/u4=";
    npmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    lock = ./locks/playwright-cli-0.1.19.json;
  };

  tanstack-cli = mkNpmCli {
    pname = "tanstack-cli";
    npmName = "@tanstack/cli";
    version = "0.71.0";
    tarballHash = "sha256-vGfUbcvV4v8TcXOIYgheZDMgRjpMzNdyYaf+uvQ3yYY=";
    npmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    lock = ./locks/tanstack-cli-0.71.0.json;
  };

  clerk = mkNpmCli {
    pname = "clerk";
    version = "3.3.0";
    tarballHash = "sha256-FzPSjmS8sGjtgQLltdjZ1+yZHueoWnrTzuppMIECzGo=";
    npmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    lock = ./locks/clerk-3.3.0.json;
  };

  ruflo = mkNpmCli {
    pname = "ruflo";
    version = "3.41.2";
    tarballHash = "sha256-GALYeEfFsDBwPYEwrmjRlXaX+NeDwIfW8rgZ9Lpjjnk=";
    npmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    lock = ./locks/ruflo-3.41.2.json;
  };

  gnhf = mkNpmCli {
    pname = "gnhf";
    version = "0.1.49";
    tarballHash = "sha256-SIKglBLe7UVUhp3CC8ZM6d+9ukqSJQbRNtSkFJ18Abs=";
    npmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    lock = ./locks/gnhf-0.1.49.json;
  };
}
