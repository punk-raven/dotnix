# config.example.nix - committed template. The installer writes your filled-in
# copy to ~/.config/dotnix/config.nix (override with $DOTNIX_CONFIG) - OUTSIDE
# this repo, so it is never committed. The flake reads it impurely from there.
# To set it up by hand: `mkdir -p ~/.config/dotnix && cp config.example.nix
# ~/.config/dotnix/config.nix && $EDITOR ~/.config/dotnix/config.nix`.
#
# Every module reads these instead of hardcoding a username or path, so this is
# the ONLY file that differs between users/machines.
{
  username      = "yourname";
  homeDirectory = "/Users/yourname";        # /home/<user> on Linux/WSL
  dotfilesDir   = "/Users/yourname/dotfiles"; # absolute path to this repo clone
  gitName       = "Your Name";
  gitEmail      = "you@example.com";

  # Auto-detected by the installer from `uname -sm`:
  #   {aarch64,x86_64}-darwin | {aarch64,x86_64}-linux
  system        = "aarch64-darwin";

  # macOS only: the darwinConfigurations attr name (`darwin-rebuild --flake .#<hostname>`).
  hostname      = "mac";

  # Linux/WSL only: skip desktop GUI apps (wezterm) on a headless/server install.
  headless      = false;
}
