# Cross-platform GUI apps available in nixpkgs. Imported by modules/linux.nix
# only when the install is not headless (a WSL install needs WSLg to actually
# display these; a bare server skips the whole module). On macOS the GUI apps
# come from Homebrew casks in modules/darwin.nix instead, so this is not
# imported there.
{ pkgs, ... }:

{
  home.packages = with pkgs; [
    wezterm
  ];
}
