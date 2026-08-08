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

  mkNpmCli =
    { pname, version, tarballHash, npmDepsHash, lock }:
    let
      # The registry tarball plus the vendored lock, with devDependencies and
      # scripts stripped so `npm ci` sees exactly the tree the lock describes.
      src = pkgs.stdenvNoCC.mkDerivation {
        pname = "${pname}-src";
        inherit version;

        src = pkgs.fetchurl {
          url = "https://registry.npmjs.org/${pname}/-/${pname}-${version}.tgz";
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
    version = "58.4.4";
    tarballHash = "sha256-JNLDs9ITyXr63dqbksm9NHhtu0fPL1W8fXY50yan1CQ=";
    npmDepsHash = "sha256-6I6zcs3SKhwi7wZM6UQwDT8AhUTCqfM7WxMfAB0Gb6U=";
    lock = ./locks/vercel-58.4.4.json;
  };
}
