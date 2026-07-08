# config.example.nix - committed template. The installer copies this to
# config.nix, fills in your values, and `git add -f config.nix` so the flake
# (which ignores untracked files) can see it. Commit config.nix to YOUR fork.
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
