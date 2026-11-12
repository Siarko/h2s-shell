# The shell's files, read-only in the store, and an `h2s-shell` command that starts them
# through scripts/launch.sh with every program the shell calls on PATH. The running shell
# inherits that PATH, so its own processes (nmcli, python3, cava…) find them too.
#
# systemctl and hyprctl are left to the system: each has to match the daemon it talks to.
#
# H2S_SHELL_DIR=<a git checkout> runs that checkout instead, with the same programs: for
# development, where editing a file reloads the shell (the store copy never changes).
{ lib
, stdenvNoCC
, runtimeShell
, quickshell
, version
, networkmanager
, bluez
, python3
, libnotify
, jq
, glib
, cava
, git
, xdg-utils
, vips
, coreutils
, gnused
, gnugrep
, gawk
, findutils
}:

let
  runtimePrograms = [
    quickshell
    networkmanager # nmcli
    bluez # bluetoothctl
    python3 # scripts/google_auth.py, standard library only
    libnotify # notify-send
    jq # launch.sh reads the icon theme setting
    glib # gsettings, the system icon theme
    cava # the audio visualiser
    git # the version shown in the settings
    xdg-utils # the browser for the Google sign-in
    vips # vipsthumbnail: wallpapers resized to the screen, kept in ~/.cache
    coreutils
    gnused
    gnugrep
    gawk
    findutils
  ];
in
stdenvNoCC.mkDerivation {
  pname = "h2s-shell";
  inherit version;

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.difference ../. (lib.fileset.unions (map lib.fileset.maybeMissing [
      ../docs
      ../site
      ../nix
      ../flake.nix
      ../flake.lock
      ../.github
      ../.devcontainer
      # A local `nix build` leaves this link; building from a checkout would copy it in
      ../result
    ]));
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/h2s-shell $out/bin
    cp -r . $out/share/h2s-shell
    chmod +x $out/share/h2s-shell/scripts/*.sh

    cat > $out/bin/h2s-shell <<EOF
    #!${runtimeShell}
    export PATH="${lib.makeBinPath runtimePrograms}:\$PATH"
    exec "\''${H2S_SHELL_DIR:-$out/share/h2s-shell}/scripts/launch.sh" "\$@"
    EOF
    chmod +x $out/bin/h2s-shell
    runHook postInstall
  '';

  meta = {
    description = "A desktop shell for Hyprland, built with Quickshell";
    homepage = "https://github.com/Siarko/h2s-shell";
    platforms = lib.platforms.linux;
    mainProgram = "h2s-shell";
  };
}
