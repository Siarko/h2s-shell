# The shell's files, read-only in the store, and an `h2s-shell` command that starts them
# through scripts/launch.sh with every program the shell calls on PATH. The running shell
# inherits that PATH, so its own processes (nmcli, python3, cava…) find them too.
#
# systemctl, systemd-inhibit and hyprctl are left to the system: each has to match the
# daemon it talks to. So are PAM's modules (the lock screen's checks).
#
# H2S_SHELL_DIR=<a git checkout> runs that checkout instead, with the same programs: for
# development, where editing a file reloads the shell (the store copy never changes).
#
# The built-in modules (builtin-modules/ in the repository) go to $out/share/h2s-shell-builtin,
# beside the shell's tree rather than inside it, and the command hands that directory to the
# launcher as H2S_SHELL_BUILTIN_MODULES — always the package's own, whichever tree it runs.
#
# The helper (helper/, a C++/Qt program) is a derivation of its own, `passthru.helper`,
# installed to its libexec/h2s-shell/; the command hands that directory to the launcher as
# H2S_SHELL_LIBEXEC, where launch.sh finds it (unless a checkout run through H2S_SHELL_DIR
# has built its own). Its Qt is the qtbase of the nixpkgs Quickshell is built with, so one
# Qt is loaded per machine; no QPA plugin is loaded, so it is not wrapped.
{ lib
, stdenv
, stdenvNoCC
, cmake
, qt6
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
, util-linux
}:

let
  runtimePrograms = [
    quickshell
    networkmanager # nmcli
    bluez # bluetoothctl
    python3 # scripts/google_auth.py, standard library only
    libnotify # notify-send
    jq # launch.sh reads the icon theme setting
    glib # gsettings (the system icon theme); gdbus (the lock: logind, fprintd)
    cava # the audio visualiser
    git # the version shown in the settings
    xdg-utils # the browser for the Google sign-in
    vips # vipsthumbnail: wallpapers resized to the screen, kept in ~/.cache
    coreutils # timeout, among the rest (the lock's methods script)
    gnused
    gnugrep
    gawk
    findutils
    util-linux # flock: one supervisor per session (launch.sh); setsid: the detached restart
  ];

  helper = stdenv.mkDerivation {
    pname = "h2s-helper";
    # The shell's number, without the revision: `h2s-helper --version` prints it
    version = builtins.head (lib.splitString "+" version);
    src = lib.fileset.toSource {
      root = ../helper;
      fileset = ../helper;
    };
    nativeBuildInputs = [ cmake ];
    buildInputs = [ qt6.qtbase ];
    dontWrapQtApps = true;
    cmakeFlags = [ "-DH2S_VERSION=${builtins.head (lib.splitString "+" version)}" ];
    meta = {
      description = "The h2s-shell's helper: what the shell cannot do from QML";
      platforms = lib.platforms.linux;
    };
  };
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
      # Built on its own (helper, above), installed into libexec
      ../helper
      # The lock test bed: runs against a checkout, with tools of its own
      ../tests/lock
      # A local `nix build` leaves this link; building from a checkout would copy it in
      ../result
    ]));
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share $out/bin
    cp -r builtin-modules $out/share/h2s-shell-builtin
    rm -r builtin-modules
    mkdir -p $out/share/h2s-shell
    cp -r . $out/share/h2s-shell
    chmod +x $out/share/h2s-shell/scripts/*.sh

    cat > $out/bin/h2s-shell <<EOF
    #!${runtimeShell}
    export PATH="${lib.makeBinPath runtimePrograms}:\$PATH"
    export H2S_SHELL_BUILTIN_MODULES="$out/share/h2s-shell-builtin"
    export H2S_SHELL_LIBEXEC="${helper}/libexec/h2s-shell"
    exec "\''${H2S_SHELL_DIR:-$out/share/h2s-shell}/scripts/launch.sh" "\$@"
    EOF
    chmod +x $out/bin/h2s-shell
    runHook postInstall
  '';

  passthru = { inherit helper; };

  meta = {
    description = "A desktop shell for Hyprland, built with Quickshell";
    homepage = "https://github.com/Siarko/h2s-shell";
    platforms = lib.platforms.linux;
    mainProgram = "h2s-shell";
  };
}
