# NixOS module: `programs.h2s-shell.enable = true;` installs the shell and what it needs
# from the system — its font, and the services its widgets read (battery, Bluetooth,
# network). Hyprland's autostart is still yours to add: see the README.
self:
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.h2s-shell;
in
{
  options.programs.h2s-shell = {
    enable = lib.mkEnableOption "h2s-shell, a desktop shell for Hyprland";
    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "h2s-shell.packages.\${system}.default";
      description = "The h2s-shell package.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
    fonts.packages = [ pkgs.nerd-fonts.jetbrains-mono ];
    # The battery widget reads UPower; profiles, power-profiles-daemon; the Bluetooth
    # widget, BlueZ; the network widget, NetworkManager. mkDefault: a machine's own
    # setting wins (e.g. TLP instead of power-profiles-daemon).
    services.upower.enable = lib.mkDefault true;
    services.power-profiles-daemon.enable = lib.mkDefault true;
    hardware.bluetooth.enable = lib.mkDefault true;
    networking.networkmanager.enable = lib.mkDefault true;
  };
}
