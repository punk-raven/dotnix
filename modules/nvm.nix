# nvm itself, plus a pinned default LTS Node, on every surface (macOS, Linux,
# WSL2). Imported from modules/common.nix, so all three get the identical path.
#
# WHY AN ACTIVATION STEP RATHER THAN A PACKAGE
#
# nvm is not a program - it is a ~160KB shell-function library you `source`, and
# its entire job is to write Node toolchains into a mutable $NVM_DIR at runtime.
# That rules out every tidier mechanism, each checked rather than assumed:
#   - nixpkgs ships no `nvm` at all. `pkgs ? nvm` is false on the pinned 26.05
#     channel; `fnm` and `nodenv` exist but are different tools with different rc
#     integration, and neither is what the initContent block in
#     modules/common.nix or README.md's PATH contract describe.
#   - Homebrew does have an `nvm` formula, but Homebrew is macOS-only in this
#     repo (modules/darwin.nix), so a brew answers one surface out of three.
#   - $NVM_DIR cannot be a store symlink. nvm writes versions/, alias/ and
#     .cache/ *inside* it, and the store is read-only - the same class of failure
#     as the ~/.config/herdr note in modules/common.nix.
#   - nvm's own curl|bash installer resolves "latest" at run time and rewrites
#     shell profiles. Unpinned, and it would fight the initContent block that
#     already does the sourcing.
#
# So the split is: the nvm scripts are fetched at BUILD time, hash-pinned, into
# the store (`nvmScripts` below), and activation only *copies* them into
# $NVM_DIR. The reproducible part stays in Nix; the small stateful part exists
# only because nvm owns that directory. The activation logic itself lives in
# lib/nvm-bootstrap.sh so tests/nvm_test.sh can run it for real.
#
# Node itself is still nvm's, not Nix's: no node/npm/npx/corepack is declared
# anywhere in this flake, and the PATH ordering in modules/common.nix keeps the
# Nix profile above nvm's global-install dir for exactly that reason. The
# `nodejs_22` in modules/agent-tooling/axi-packages.nix is a private build-time
# dep of the AXI CLIs and never reaches PATH.
{ config, pkgs, lib, ... }:

let
  # Version bumps: change these two. `nvmVersion` needs a new `hash` (set it to
  # pkgs.lib.fakeHash and rebuild to surface the real one, or grab it directly
  # with `nix store prefetch-file --json --unpack <url>` - unpacking matters,
  # fetchzip hashes the tree, not the tarball). `nodeVersion` needs no hash;
  # nvm downloads it at activation. Pick a real LTS from
  # https://nodejs.org/dist/index.json - "--lts" is deliberately NOT used, so a
  # rebuild never silently changes the Node a machine runs.
  nvmVersion = "0.40.6";
  nodeVersion = "v24.18.1"; # Krypton, the active LTS line

  # fetchzip, not fetchurl: it hashes the unpacked tree, so a GitHub tarball
  # re-compression cannot invalidate the pin.
  nvmSrc = pkgs.fetchzip {
    url = "https://github.com/nvm-sh/nvm/archive/refs/tags/v${nvmVersion}.tar.gz";
    hash = "sha256-60diMTawrIlyB29GrYcRuv5RBawGxpW82FHYWmHQgbg=";
  };

  # Just nvm's runtime files. nvm.sh is the library the shell sources, nvm-exec
  # is the only sibling nvm.sh ever execs (it backs `nvm exec`), and
  # bash_completion is what the rc file sources for completions - grep nvm.sh
  # for "$NVM_DIR/" and those are the only files it expects next to itself.
  # Everything else upstream ships is docs, CI, and its test suite.
  nvmScripts = pkgs.runCommand "nvm-${nvmVersion}" { } ''
    install -Dm755 ${nvmSrc}/nvm.sh          "$out/nvm.sh"
    install -Dm755 ${nvmSrc}/nvm-exec        "$out/nvm-exec"
    install -Dm644 ${nvmSrc}/bash_completion "$out/bash_completion"
  '';

  # Appended to, never prepended over, the activation PATH: nvm shells out to
  # curl/tar/xz/uname to fetch and unpack a Node build, and a stock WSL distro
  # is not guaranteed to have all of them. Appending means the host's own tools
  # still win where they exist (`sysctl` on darwin, for instance) and these only
  # fill gaps.
  fetchTools = lib.makeBinPath (with pkgs; [
    curl coreutils gnutar xz gzip gnugrep gnused gawk
  ]);
in
{
  # Runs after writeBoundary, so $HOME's managed links already exist. Cheap on
  # the common path: two file tests and a `cat`, no network, no writes. See
  # lib/nvm-bootstrap.sh for the idempotency and failure contract - notably that
  # it never exits non-zero, so a failed Node download cannot take an otherwise
  # good activation down with it.
  home.activation.nvmBootstrap = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    DOTNIX_NVM_SRC=${nvmScripts} \
    DOTNIX_NVM_VERSION=${nvmVersion} \
    DOTNIX_NODE_VERSION=${nodeVersion} \
    NVM_DIR="${config.home.homeDirectory}/.nvm" \
    PATH="$PATH:${fetchTools}" \
      $DRY_RUN_CMD ${pkgs.bash}/bin/bash ${../lib/nvm-bootstrap.sh}
  '';
}
