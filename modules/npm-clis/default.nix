{ pkgs, ... }:

# Published npm CLIs with no nixpkgs package, pinned via ./npm-packages.nix.
#
# These previously lived as `npm i -g` globals inside the nvm-managed Node
# prefix, which meant a `nodeVersion` bump in modules/nvm.nix silently orphaned
# every one of them (the audit that prompted this found several stranded under
# Node versions that no longer had a `node` binary at all).
#
# PATH note: the profile outranks nvm's bin dir (see "PATH precedence" in
# README.md), so the Nix copy wins over any leftover global of the same name -
# no need to uninstall the old global first for this to take effect.

let
  npmClis = import ./npm-packages.nix { inherit pkgs; };
in
{
  home.packages = [ npmClis.vercel ];
}
