# The least a NixOS system evaluates with, the shell's module on and its settings file beside
# the configuration: the fixture configurations of tests/system/nixos/build.sh (a flake, the
# same in git, and a classic one) import it. Evaluated only, never built.
{ ... }:
{
  programs.h2s-shell.enable = true;
  programs.h2s-shell.settingsFile = ./h2s-shell.json;
  boot.loader.grub.enable = false;
  fileSystems."/" = { device = "none"; fsType = "tmpfs"; };
  system.stateVersion = "26.05";
  nixpkgs.hostPlatform = "x86_64-linux";
}
