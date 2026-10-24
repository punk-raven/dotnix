{ pkgs, ... }:

# Prebuilt Go binaries published as GitHub release tarballs.
#
# Both tools shipped here were previously installed by their own curl-style
# installer into ~/.local/bin, which sits ABOVE the Nix profile on PATH (see
# "PATH precedence" in README.md). That means declaring them is only half the
# job: the installer's copy must also be removed, or it silently keeps winning.
#
# Fetch the official prebuilt artifact for the host platform, hash-pinned,
# rather than compiling Go on every rebuild. Both tools share one asset naming
# convention, so the fetch/install logic is written once here.
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
      # invalidates the signature and the binary refuses to launch.
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
    version = "3.1.5";
    description =
      "Pooled, pre-warmed git worktrees so multiple coding agents can share one repo";
    hashes = {
      "aarch64-darwin" = "sha256-asmhIHBYTn0ax55hNDuvgoPo9a0CtfbZ07um9Fcpvt0=";
      "x86_64-darwin" = "sha256-4JRu8219FHpg8HKGJDWYoAycesHODMBOspTZz/9lE2Q=";
      "aarch64-linux" = "sha256-MVtWs7B92agmnnk6cKFBHlnC/zsKP/z/4RQJHcL6L7M=";
      "x86_64-linux" = "sha256-afgycAVmULEEnZUinoNIFT9wUvEbnT/WNKyw82ir0U8=";
    };
  };

  # Only the binary is declared. ~/.no-mistakes is live runtime state - it holds
  # a daemon socket, daemon.pid, rotating logs, worktrees and state.sqlite - so
  # it must stay writable and unmanaged, exactly like ~/.config/herdr in
  # modules/common.nix. Nix owning that directory would break the daemon.
  no-mistakes = mkReleaseBin {
    pname = "no-mistakes";
    version = "1.99.1";
    description =
      "Validation pipeline - review, tests, lint, docs, PR and CI - before changes reach the push target";
    hashes = {
      "aarch64-darwin" = "sha256-F3xTCUGUbSCRi3m4Fw6OMCdBWfiClNtYlRhmqHis2uI=";
      "x86_64-darwin" = "sha256-FiJl/pk6trwFQYQyoabq+ha6JIF3rPuHTR1wtmd7/do=";
      "aarch64-linux" = "sha256-rsgE2TFYp3SKi6FrPFUrgtO3FOhoFdUvE/uQNAM0XPU=";
      "x86_64-linux" = "sha256-iOgNuf4h1NwUGpPF+uz2rs0IFp6swjTq+yVZCPGd88c=";
    };
  };
in
{
  home.packages = [ treehouse no-mistakes ];
}
