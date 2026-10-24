{ pkgs, lib, ... }:

let
  version = "20.0.40";

  # ccusage (https://github.com/ccusage/ccusage): a Rust CLI that analyzes
  # coding-agent token usage and cost from local data (Claude Code, Codex,
  # OpenCode, ...) - `ccusage daily|weekly|monthly|session|blocks`.
  #
  # Installed as the official prebuilt binary shipped inside the npm platform
  # package `@ccusage/ccusage-<os>-<arch>` - the same binary their release CI
  # produces from `nix build .#ccusage`. Each links only its platform's libc (no
  # /nix/store deps), so it runs anywhere. Per-system selector below;
  # sha256-pinned via fetchurl -> fully reproducible with no Rust recompile. The
  # prebuilt binaries are adhoc/linker-signed, so `dontFixup` keeps Nix from
  # stripping them and invalidating the signature.
  #
  # Version bump: change `version`, set the relevant hash to pkgs.lib.fakeHash,
  # rebuild to surface the real SRI hash, paste it back. To grab a hash directly:
  #   nix store prefetch-file --json \
  #     https://registry.npmjs.org/@ccusage/ccusage-<os>-<arch>/-/ccusage-<os>-<arch>-<VER>.tgz
  sources = {
    "aarch64-darwin" = { pkg = "ccusage-darwin-arm64"; hash = "sha256-bwGifgYGF8BM7oBCHkIhshuAUn2DDazLLikXNdtfrYE="; };
    "x86_64-darwin"  = { pkg = "ccusage-darwin-x64"; hash = "sha256-u+no+7HKboU4pj7aalVDxyDgFl8Nyzn7fxpA5EpfOdc="; };
    "aarch64-linux"  = { pkg = "ccusage-linux-arm64"; hash = "sha256-X89j4odtfl9Gu4Y3nmEBtRh/hesc8NXnZrkcNB80AQs="; };
    "x86_64-linux"   = { pkg = "ccusage-linux-x64"; hash = "sha256-dQMEJrB9xWGv2SQKlC4nO8QSYLaLBoLnZojlfTcRqgk="; };
  };
  source = sources.${pkgs.stdenv.hostPlatform.system};

  ccusage = pkgs.stdenv.mkDerivation {
    pname = "ccusage";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/@ccusage/${source.pkg}/-/${source.pkg}-${version}.tgz";
      inherit (source) hash;
    };

    # The npm tarball unpacks to package/{bin/ccusage,package.json,LICENSE}.
    sourceRoot = "package";
    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 bin/ccusage "$out/bin/ccusage"
      runHook postInstall
    '';

    meta = {
      description =
        "Analyze coding agent CLI token usage and costs from local data";
      homepage = "https://github.com/ccusage/ccusage";
      license = lib.licenses.mit;
      mainProgram = "ccusage";
      platforms = builtins.attrNames sources;
    };
  };
in
{
  # `ccusage` on PATH - run directly (`ccusage`, `ccusage daily`, `ccusage
  # monthly --json`). It reads each agent's local usage data automatically; no
  # config or wiring needed.
  home.packages = [ ccusage ];
}
