# A classic configuration for tests/system/nixos/build.sh (@REPO@: the checkout, put in by it)
{ ... }:
{
  imports = [ (builtins.getFlake "path:@REPO@").nixosModules.default ./build.nix ];
}
