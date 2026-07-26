# Cross-platform GUI apps available in nixpkgs. Imported by modules/linux.nix
# only when the install is not headless (a WSL install needs WSLg to actually
# display these; a bare server skips the whole module). On macOS the GUI apps
# come from Homebrew casks in modules/darwin.nix instead, so this is not
# imported there.
{ pkgs, nixglPkg, ... }:

let
  # A Nix-built wezterm on a non-NixOS host (plain Linux or WSL2) cannot load
  # the system libEGL/libGL - it only sees its own store closure, which has no
  # GPU vendor driver, so window creation dies with "cannot open libEGL.so.1".
  # nixGL fixes this generically: it sets up nixpkgs Mesa (hardware where
  # available, llvmpipe software fallback otherwise - fine for a terminal) and
  # execs the program with the right driver env. We wrap only the two GUI
  # entrypoints; the mux/CLI binaries need no GL. Env set by nixGL is inherited
  # by the wezterm-gui child, so wrapping the launcher is enough.
  weztermGL = pkgs.symlinkJoin {
    name = "wezterm-nixgl";
    paths = [ pkgs.wezterm ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      for bin in wezterm wezterm-gui; do
        if [ -e "$out/bin/$bin" ]; then
          rm "$out/bin/$bin"
          makeWrapper ${nixglPkg}/bin/nixGLIntel "$out/bin/$bin" \
            --add-flags ${pkgs.wezterm}/bin/$bin
        fi
      done
    '';
  };
in
{
  home.packages = [
    weztermGL
  ] ++ (with pkgs; [
    # Clipboard bridge for neovim. files/.config/nvim/init.lua sets
    # `clipboard = "unnamedplus"`, which macOS satisfies on its own via
    # pbcopy/pbpaste. On Linux nvim needs an external provider or the setting is
    # a silent no-op - yanks never leave the editor. WSLg exposes both a Wayland
    # and an X11 display and syncs the selection to the Windows clipboard, so
    # ship both providers and let nvim pick whichever the session offers.
    wl-clipboard
    xclip

    # Browser for the mandated chrome-devtools-axi workflow. The `brave-cdp`
    # helper in modules/agent-tooling/axi.nix scans PATH for
    # brave/brave-browser/chromium/... and aborts when it finds none; macOS
    # instead opens the app bundle, which is installed outside this flake. This
    # is the only declared way to give the Linux/WSL path a browser to attach
    # to on :9222. GUI-only, hence this module rather than linux.nix.
    brave
  ]);
}
