# The programs the lock test bed needs, from one pinned nixpkgs, so that a run today and
# a run in a month use the same compositor, the same screenshot tool and the same Python.
#
#   nix build --no-link --print-out-paths --impure -f tests/lock/tools.nix
#
# prints one store path holding bin/ (labwc, Hyprland, hyprctl, grim, python3 with
# pywayland), share/ltproto (Python bindings of the input protocols) and share/us.xkb (the
# keymap the virtual keyboard sends). run.sh does this itself.
#
# Why this nixpkgs and not the repo's flake.lock: the flake pins nixos-26.05 for the
# package, whose Hyprland is 0.55.4, while the shell runs on 0.57.1 from nixos-unstable
# (the owner's system takes Hyprland from there). The lock screen is a conversation with
# the compositor, so the test bed uses the compositor the shell actually meets: this is
# the nixos-unstable revision the owner's system is built from, and its Hyprland is the
# very store path the real session runs. Move the pin when the system's Hyprland moves.
#
# Quickshell is deliberately not here: the shell under test is started through the
# installed `h2s-shell` launcher, with the Quickshell that launcher puts on PATH, as in
# real use. PAM modules are not here either: run.sh takes them from the libpam that
# Quickshell itself loads, since a module must match the library that loads it.
{ system ? builtins.currentSystem }:

let
  nixpkgs = builtins.fetchTree {
    type = "github";
    owner = "NixOS";
    repo = "nixpkgs";
    rev = "1d060086d60cb76a40cf37109f979d88a5bd6396";
    narHash = "sha256-jQp1wKvbwWdLBASTXkSi/VYmDJ5AbBi1WvcMt9HWJC8=";
  };
  pkgs = import nixpkgs { inherit system; config = { }; overlays = [ ]; };

  python = pkgs.python3.withPackages (packages: [ packages.pywayland ]);

  # The virtual keyboard and pointer protocols are not installed by any package as XML
  # (wlroots implements them from its own source tree), so they are taken from there
  # (the scanner asks pkg-config where the core protocol lives, even when given its path)
  protocols = pkgs.runCommand "h2s-locktest-protocols"
    { nativeBuildInputs = [ python pkgs.pkg-config pkgs.wayland-scanner ]; } ''
    mkdir -p $out
    pywayland-scanner -o $out/ltproto -i \
      ${pkgs.wayland-scanner}/share/wayland/wayland.xml \
      ${pkgs.wlroots.src}/protocol/virtual-keyboard-unstable-v1.xml \
      ${pkgs.wlroots.src}/protocol/wlr-virtual-pointer-unstable-v1.xml
    touch $out/ltproto/__init__.py
  '';

  # A plain US layout, compiled once: the virtual keyboard has to hand the compositor a
  # full keymap, and the key codes in input/ltinput.py are this layout's
  keymap = pkgs.runCommand "h2s-locktest-us.xkb" { nativeBuildInputs = [ pkgs.libxkbcommon ]; } ''
    xkbcli compile-keymap --rules evdev --model pc105 --layout us > $out
  '';
in
pkgs.linkFarm "h2s-locktest-tools" [
  { name = "bin/labwc"; path = "${pkgs.labwc}/bin/labwc"; }
  { name = "bin/Hyprland"; path = "${pkgs.hyprland}/bin/Hyprland"; }
  { name = "bin/hyprctl"; path = "${pkgs.hyprland}/bin/hyprctl"; }
  { name = "bin/grim"; path = "${pkgs.grim}/bin/grim"; }
  { name = "bin/python3"; path = "${python}/bin/python3"; }
  { name = "share/ltproto"; path = "${protocols}/ltproto"; }
  { name = "share/us.xkb"; path = keymap; }
]
