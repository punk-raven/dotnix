{ pkgs, lib, ... }:

let
  version = "0.2.0";

  # floci (https://github.com/floci-io/floci-cli): the CLI for Floci, an
  # open-source local cloud emulator for AWS, GCP, Azure and OCI. It drives a
  # container that stands the emulators up locally - `floci start`,
  # `eval $(floci env)`, then the normal `aws`/`gcloud`/`az`/`oci` CLIs point at
  # it.
  #
  # It needs a Docker-compatible daemon at runtime; that is already covered on
  # both surfaces - the `docker-desktop` cask in modules/darwin.nix and
  # `docker-client` in modules/linux.nix (whose daemon lives on the Windows side
  # under WSL2). Nothing extra is declared here for it.
  #
  # Installed as the official prebuilt native-image binary for the host
  # platform, sha256-pinned, rather than building the Java sources with GraalVM
  # on every rebuild. Upstream's alternatives are all unsuitable here: the
  # install script writes to /usr/local/bin, Homebrew/Scoop put the binary in a
  # package manager this flake does not own, and the `floci.jar` fallback would
  # drag in a JDK 25 runtime for a tool that ships a native binary for every
  # platform we target.
  #
  # `floci update` self-updates by overwriting its own binary. Against a
  # /nix/store path that write fails (read-only store), and it should: the
  # version is pinned here. Bump `version` and the hashes below instead.
  #
  # Unlike the other prebuilt tools in this repo, the release assets are BARE
  # binaries rather than tarballs - hence `dontUnpack` and installing straight
  # from `$src`.
  #
  # Version bump: change `version`, then read the four digests out of the
  # release's own checksum file - no download needed:
  #   curl -sL https://github.com/floci-io/floci-cli/releases/download/<VER>/sha256sums.txt
  #   nix hash convert --hash-algo sha256 --to sri <hex>
  sources = {
    "aarch64-darwin" = { asset = "floci-darwin-arm64"; hash = "sha256-b987LyXanLkoehAGmhkTS7M7Inyk7F1/Ln5yTn9vTsg="; };
    "x86_64-darwin"  = { asset = "floci-darwin-amd64"; hash = "sha256-QnxNPxz4T/M4ctwGE5vfBTzJe40ecuVMDEyzfyulAAg="; };
    "aarch64-linux"  = { asset = "floci-linux-arm64"; hash = "sha256-HD+JiFz4DmnDOKuvr+nB/amOwp1JvVkcJ67CD6++rT4="; };
    "x86_64-linux"   = { asset = "floci-linux-amd64"; hash = "sha256-akWyP3s6n66SFOECgZDFY5jfrzW9/T/iwkxnNb6EGTM="; };
  };
  source = sources.${pkgs.stdenv.hostPlatform.system};

  floci = pkgs.stdenv.mkDerivation {
    pname = "floci";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://github.com/floci-io/floci-cli/releases/download/${version}/${source.asset}";
      inherit (source) hash;
    };

    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;

    # The Linux assets are dynamically linked against the host's glibc
    # (`INTERP: /lib64/ld-linux-x86-64.so.2`), which no Nix-managed system is
    # required to provide. autoPatchelfHook rewrites the interpreter and RPATH
    # to this nixpkgs' glibc/zlib so the closure is self-contained rather than
    # dependent on whatever the distro ships. Stripping is skipped: the binary
    # is a GraalVM native image and there is nothing to gain from touching it.
    #
    # On Darwin fixup is skipped entirely - the release binaries are
    # adhoc/linker-signed, and stripping them invalidates the signature so they
    # refuse to launch. Same reason modules/agent-tooling/rtk.nix sets it.
    nativeBuildInputs = lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.autoPatchelfHook ];
    buildInputs = lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.zlib pkgs.stdenv.cc.cc.lib ];
    dontFixup = pkgs.stdenv.hostPlatform.isDarwin;
    dontStrip = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 "$src" "$out/bin/floci"
      runHook postInstall
    '';

    meta = {
      description =
        "CLI for Floci - a local cloud emulator for AWS, GCP, Azure and OCI";
      homepage = "https://github.com/floci-io/floci-cli";
      license = lib.licenses.mit;
      mainProgram = "floci";
      platforms = builtins.attrNames sources;
    };
  };
in
{
  # `floci` on PATH. No files are declared alongside it: ~/.floci is live
  # runtime state (container ids, per-cloud emulator data, logs) and must stay
  # writable and unmanaged, the same rule modules/common.nix applies to
  # ~/.config/herdr.
  home.packages = [ floci ];
}
