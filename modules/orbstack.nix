# OrbStack - lightweight Docker and Linux VM runtime for macOS.
#
# Installed via a nix-darwin activation script rather than a Homebrew cask
# because the upstream cask's postflight step is incompatible with Homebrew 6
# ("unknown install step: run"), and brew bundle's rollback deletes the app
# from /Applications on failure.
#
# The DMG is fetched at build time and hash-pinned in the store. Activation
# copies OrbStack.app to /Applications (like nix-darwin's own app linker) and
# strips com.apple.quarantine so macOS does not block the launch. The copy is
# skipped when the installed version already matches.
#
# Version bump: change `version` and `build`, set the hash to
# `pkgs.lib.fakeHash`, rebuild to surface the real hash, paste it back.
# Or grab it directly:
#   nix store prefetch-file --json <url>
{ pkgs, lib, cfg, ... }:

let
  version = "2.2.3";
  build = "20963";

  sources = {
    "aarch64-darwin" = {
      asset = "OrbStack_v${version}_${build}_arm64.dmg";
      hash = "sha256-fKd4aPOg19n1ez+YYVqtMMxZ0jzIS7/xP3iEbfC0k9Q=";
    };
    "x86_64-darwin" = {
      asset = "OrbStack_v${version}_${build}_amd64.dmg";
      hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    };
  };
  source = sources.${pkgs.stdenv.hostPlatform.system};

  orbstackApp = pkgs.stdenv.mkDerivation {
    pname = "orbstack";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://cdn-updates.orbstack.dev/${
        if pkgs.stdenv.hostPlatform.isAarch64 then "arm64" else "amd64"
      }/${source.asset}";
      inherit (source) hash;
    };

    nativeBuildInputs = [ pkgs.undmg ];

    sourceRoot = "OrbStack.app";

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/Applications"
      cp -R . "$out/Applications/OrbStack.app"
      runHook postInstall
    '';

    meta = {
      description = "Replacement for Docker Desktop - fast, light, simple";
      homepage = "https://orbstack.dev";
      platforms = builtins.attrNames sources;
    };
  };
in
{
  system.activationScripts.orbstack.text = ''
    app_src="${orbstackApp}/Applications/OrbStack.app"
    app_dst="/Applications/OrbStack.app"
    marker="$app_dst/.orbstack-nix-version"

    current=""
    if [ -f "$marker" ]; then
      current=$(cat "$marker" 2>/dev/null || true)
    fi

    if [ "$current" != "${version}-${build}" ]; then
      echo "installing OrbStack ${version} (${build}) to /Applications..." >&2
      rm -rf "$app_dst"
      cp -R "$app_src" "$app_dst"
      /usr/bin/xattr -dr com.apple.quarantine "$app_dst"
      echo "${version}-${build}" > "$marker"
    fi
  '';
}
