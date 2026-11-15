# The programs the lock test bed needs, from one pinned nixpkgs, so that a run today and
# a run in a month use the same compositor, the same screenshot tool and the same Python.
#
#   nix build --no-link --print-out-paths --impure -f tests/lock/tools.nix
#
# prints one store path holding bin/ (labwc, Hyprland, hyprctl, grim, setpriv, python3
# with pywayland, xkbcli, dbus-daemon, gdbus), share/ltproto (Python bindings of the input
# and window protocols), share/us.xkb (the keymap the virtual keyboard sends by default) and
# share/keymaps/<name>.xkb (the others a test may ask for). run.sh does this itself.
#
# Why this nixpkgs and not the repo's flake.lock: the flake pins nixos-26.05 for the
# package, whose Hyprland is 0.55.4, while the shell runs on 0.57.1 from nixos-unstable
# (the owner's system takes Hyprland from there). The lock screen is a conversation with
# the compositor, so the test bed uses the compositor the shell actually meets: this is
# the nixos-unstable revision the owner's system is built from, and its Hyprland is the
# very store path the real session runs. Move the pin when the system's Hyprland moves
# (run.sh prints a NOTE when the two versions differ).
#
# Quickshell is deliberately not here: the shell under test is started through the
# installed `h2s-shell` launcher, with the Quickshell that launcher puts on PATH, as in
# real use. PAM modules are not here either: run.sh takes them from the libpam that
# Quickshell itself loads, since a module must match the library that loads it.
{ system ? builtins.currentSystem }:

let
  # fetchTarball with a hash rather than fetchTree: the same store path, without needing
  # the fetch-tree (or flakes) experimental feature
  nixpkgs = builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/1d060086d60cb76a40cf37109f979d88a5bd6396.tar.gz";
    sha256 = "sha256-jQp1wKvbwWdLBASTXkSi/VYmDJ5AbBi1WvcMt9HWJC8=";
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
      ${pkgs.wlroots.src}/protocol/wlr-virtual-pointer-unstable-v1.xml \
      ${pkgs.wayland-protocols}/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml
    touch $out/ltproto/__init__.py
  '';

  # A plain US layout, compiled once: the virtual keyboard has to hand the compositor a
  # full keymap, and the key codes in input/ltinput.py are this layout's
  keymap = pkgs.runCommand "h2s-locktest-us.xkb" { nativeBuildInputs = [ pkgs.libxkbcommon ]; } ''
    xkbcli compile-keymap --rules evdev --model pc105 --layout us > $out
  '';

  # The layouts a test may type with (lib.sh: stack_start --keymap <name>). The virtual
  # keyboard works out which key and modifiers type a character from the keymap itself
  # (xkbcli how-to-type), so a layout here needs no table of its own.
  #   us          the default
  #   us-intl     dead keys (' " ` ~ ^ are dead_acute, dead_diaeresis, …) and AltGr characters
  #   us-compose  the plain US layout with a Compose key on the right Alt
  keymaps = pkgs.runCommand "h2s-locktest-keymaps" { nativeBuildInputs = [ pkgs.libxkbcommon ]; } ''
    mkdir -p $out
    xkbcli compile-keymap --rules evdev --model pc105 --layout us > $out/us.xkb
    xkbcli compile-keymap --rules evdev --model pc105 --layout us --variant intl > $out/us-intl.xkb
    xkbcli compile-keymap --rules evdev --model pc105 --layout us --options compose:ralt > $out/us-compose.xkb
  '';
in
pkgs.linkFarm "h2s-locktest-tools" [
  { name = "bin/labwc"; path = "${pkgs.labwc}/bin/labwc"; }
  { name = "bin/Hyprland"; path = "${pkgs.hyprland}/bin/Hyprland"; }
  { name = "bin/hyprctl"; path = "${pkgs.hyprland}/bin/hyprctl"; }
  { name = "bin/grim"; path = "${pkgs.grim}/bin/grim"; }
  { name = "bin/python3"; path = "${python}/bin/python3"; }
  # Every process of a test runs with no new privileges (setpriv --no-new-privs)
  { name = "bin/setpriv"; path = "${pkgs.util-linux}/bin/setpriv"; }
  # The virtual keyboard asks it which key and modifiers type a character (how-to-type)
  { name = "bin/xkbcli"; path = "${pkgs.libxkbcommon}/bin/xkbcli"; }
  # A private session bus, for the tests that need notifications (stack_start
  # --session-bus): the shell's notification server registers there, gdbus sends to it
  { name = "bin/dbus-daemon"; path = "${pkgs.dbus}/bin/dbus-daemon"; }
  { name = "bin/gdbus"; path = "${pkgs.glib.bin}/bin/gdbus"; }
  { name = "share/ltproto"; path = "${protocols}/ltproto"; }
  { name = "share/us.xkb"; path = keymap; }
  { name = "share/keymaps"; path = keymaps; }
]
