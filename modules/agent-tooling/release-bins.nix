{ pkgs, ... }:

# Prebuilt Go binaries published as GitHub release tarballs.
#
# Both tools shipped here were previously installed by their own curl-style
# installer into ~/.local/bin, which sits ABOVE the Nix profile on PATH (see
# "PATH precedence" in README.md). That means declaring them is only half the
# job: the installer's copy must also be removed, or it silently keeps winning.
#
# Same shape as modules/agent-tooling/rtk.nix - fetch the official prebuilt
# artifact for the host platform, hash-pinned, rather than compiling Go on every
# rebuild. Unlike rtk these two share one asset naming convention, so the
# fetch/install logic is written once here instead of duplicated per tool.
#
# Version bump: change `version`, set the four hashes to pkgs.lib.fakeHash and
# rebuild to surface them. Faster route, since these releases publish a digest
# per asset - no download needed:
#   gh-axi api repos/kunchenguid/<repo>/releases/tags/v<VER> \
#     | grep -E '^    (name|digest): '
#   nix hash convert --hash-algo sha256 --to sri <hex>

let
  # `<pname>-v<version>-<os>-<arch>.tar.gz`, with the bare binary at the root.
  mkReleaseBin =
    { pname, version, owner ? "kunchenguid", description, hashes }:
    let
      platforms = {
        "aarch64-darwin" = "darwin-arm64";
        "x86_64-darwin" = "darwin-amd64";
        "aarch64-linux" = "linux-arm64";
        "x86_64-linux" = "linux-amd64";
      };
      system = pkgs.stdenv.hostPlatform.system;
      slug = platforms.${system};
    in
    pkgs.stdenv.mkDerivation {
      inherit pname version;

      src = pkgs.fetchurl {
        url = "https://github.com/${owner}/${pname}/releases/download/v${version}/${pname}-v${version}-${slug}.tar.gz";
        hash = hashes.${system};
      };

      sourceRoot = ".";
      dontConfigure = true;
      dontBuild = true;
      # The release binaries are adhoc/linker-signed; stripping them on Darwin
      # invalidates the signature and the binary refuses to launch. Same reason
      # rtk.nix sets this.
      dontFixup = true;

      installPhase = ''
        runHook preInstall
        install -Dm755 ${pname} "$out/bin/${pname}"
        runHook postInstall
      '';

      meta = {
        inherit description;
        homepage = "https://github.com/${owner}/${pname}";
        mainProgram = pname;
        platforms = builtins.attrNames platforms;
      };
    };

  treehouse = mkReleaseBin {
    pname = "treehouse";
    version = "2.1.1";
    description =
      "Pooled, pre-warmed git worktrees so multiple coding agents can share one repo";
    hashes = {
      "aarch64-darwin" = "sha256-3qvrcVO60UZZ6Y2njeUzSv7K6qx+BZiLEGpIiGRnR9M=";
      "x86_64-darwin" = "sha256-9va9cf6CeYJqo18gHnnzQQbBxAVheePoFBlCAn3ZkqY=";
      "aarch64-linux" = "sha256-mANnwCMydOsxgaGaLKjsadCbSliLonNnk30zb5osk44=";
      "x86_64-linux" = "sha256-L+PgEiCuUalnw+W6bM8Q7IO9uujkIDaNGUKFqNBMnvg=";
    };
  };

  # Pinned to v1.45.4, the newest release NOT marked prerelease - upstream has
  # tagged v1.46.0 through v1.48.0 as prereleases, and the tool's own
  # ~/.no-mistakes/update-check.json agrees that 1.45.4 is latest. Track the
  # stable line here rather than whatever tag happens to be newest.
  #
  # Only the binary is declared. ~/.no-mistakes is live runtime state - it holds
  # a daemon socket, daemon.pid, rotating logs, worktrees and state.sqlite - so
  # it must stay writable and unmanaged, exactly like ~/.config/herdr in
  # modules/common.nix. Nix owning that directory would break the daemon.
  no-mistakes = mkReleaseBin {
    pname = "no-mistakes";
    version = "1.45.4";
    description =
      "Validation pipeline - review, tests, lint, docs, PR and CI - before changes reach the push target";
    hashes = {
      "aarch64-darwin" = "sha256-eXi2jJMSBwiNn/fGJVaF9grmskDKFSKPBT1nTtlK+OU=";
      "x86_64-darwin" = "sha256-JZaqIKLDNzuLwoJg5/460xoy58nAuU2uDHnYBawDmTY=";
      "aarch64-linux" = "sha256-GaxixNHXpALX7+gUJPoDa2dhYAHTfZuVr7qcYMDT5FM=";
      "x86_64-linux" = "sha256-EczwvKpXWwa9aRZExmnFc+KmLeahwbmOnlLTTC3yrRk=";
    };
  };
in
{
  home.packages = [ treehouse no-mistakes ];
}
