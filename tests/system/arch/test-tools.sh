# shellcheck shell=bash
# The packages the test runners' tools come from on Arch, each with its use: every one
# exists in the repositories (`pacman -Si`, read only). install.sh does not install them;
# one that is not installed is said here, with what it is for — the runners themselves end
# with a set-up error naming the tool.
need pacman "asks the sync database for each package name"

tools=(
    "quickshell|runs the suites and the shell under test"
    "labwc|the headless compositor the suites' windows open in"
    "util-linux|setpriv, setsid, flock, script: the test processes' isolation, the bed's lock, a terminal for install.sh"
    "coreutils|timeout: ends a compositor or a Quickshell that hangs"
    "fontconfig|fc-match: the characters of the theme's font, for the glyphs suite"
    "hyprland|the compositor the lock screen is tested in"
    "grim|screenshots of the lock screen"
    "wlr-randr|sets the headless output's size"
    "wl-clipboard|wl-copy, wl-paste: the primary selection of the paste test"
    "libxkbcommon|xkbcli: tells the virtual keyboard which keys type a character"
    "dbus|dbus-daemon: a private session bus for the notification tests"
    "glib2|gdbus: the same bus, and the stand-ins for logind and fprintd"
    "python|the virtual keyboard and pointer"
    "python-pywayland|the Python module they speak Wayland with, and its scanner"
    "pkgconf|pkg-config: finds the Wayland protocol files the input bindings are generated from"
    "wayland|wayland.xml, one of those protocol files"
    "wayland-protocols|xdg-shell.xml, another"
)
in_repositories() { [ -n "$1" ] && pacman -Si -- "$1" > /dev/null 2>&1; }
for entry in "${tools[@]}"; do
    package=${entry%%|*}
    check "$package is in the repositories (${entry#*|})" in_repositories "$package"
    pacman -Qq -- "$package" > /dev/null 2>&1 || echo "    NOTE $package is not installed here (${entry#*|})"
done
