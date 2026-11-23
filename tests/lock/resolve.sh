# shellcheck shell=bash
# Finds the tests' tools and Quickshell: one way to find them, for tests/headless.sh (the
# unit and module suites) and tests/lock/run.sh. Sourced. The caller defines setup_error
# (prints, cleans up, exits 2), LOCKTEST_DIR (this directory), temp_base (a plain temp
# path), PROBE_TIMEOUT, `probe` (empty; the launcher probe's temp dir while it exists, for
# setup_error to remove) and LOCKTEST_NEED, what it uses:
#
#   unit   labwc, setpriv, setsid, timeout, fc-match
#   lock   the lock test bed's whole set (below), setsid, timeout, and a launcher
#   python python3 and timeout only (tests/device/deploy-check.sh reads JSON with it): the
#          pinned set's bin/python3, or the one on PATH; no launcher, no Quickshell. Sets
#          LOCKTEST_PYTHON and prints one tools line
#
# The tools come from one source for the whole run, never tool by tool (they depend on each
# other, and a mix of pinned and system parts is a configuration nobody tests):
#
#   H2S_TEST_TOOLS=nix      the pinned build of tools.nix
#   H2S_TEST_TOOLS=system   every tool from PATH, whatever version is installed
#   (not set)               nix when a `nix` command exists, else system
#
# setsid and timeout are taken from PATH with either source (tools.nix does not hold them).
#
# With nix, the store path it built is remembered, so that a later start does not have nix
# evaluate tools.nix again (seconds, at every runner's start): a file in
# ${XDG_CACHE_HOME:-$HOME/.cache}/h2s-shell-tests/, named after a hash of what the build is
# made from — tools.nix, every file it names (tools_inputs, below) and the system. The
# remembered path is taken only while it is still there and holds what this caller needs,
# from a file and a directory that belong to the user;
# otherwise nix is asked as before and the file rewritten. H2S_TEST_TOOLS_CACHE=0 asks nix
# whatever is remembered (and rewrites the file). Without a cache directory that can be
# written, or without sha256sum, nix is asked every time.
#
# The lock bed's set is what tools.nix builds: bin/ (labwc, Hyprland, hyprctl, grim, python3
# with pywayland, setpriv, xkbcli, dbus-daemon, gdbus, wl-copy, wl-paste, wlr-randr) and
# share/ (ltproto: the Python bindings of the input protocols; us.xkb and keymaps/: the
# layouts the virtual keyboard sends). With the system source the programs are those on
# PATH, and the caller has share/ made for the run, in a directory of the run's own, with
# make_system_tools <directory> (below): the same set in the same layout, so the test bed
# reads one LOCKTEST_TOOLS either way. Making it takes pywayland's scanner, pkg-config (the
# scanner asks it where the core protocol is, and so does this file, for wayland.xml and
# xdg-shell.xml) and the two protocol files in protocols/, which tools.nix reads too.
#
# The launcher (the lock need starts the shell through one, the unit need only asks it for
# its Quickshell), in this order: LOCKTEST_LAUNCHER; h2s-shell on PATH; for the lock need,
# the test bed's own launcher.sh — a stand-in for a machine without an h2s-shell command,
# which does what the packaged one does with H2S_SHELL_DIR set (LOCKTEST_LAUNCHER_FROM says
# which it was: given, path or stand-in).
#
# Quickshell is never pinned here. In this order: LOCKTEST_QS; the one the launcher runs,
# asked of the launcher; qs, then quickshell, on PATH. A launcher that is there and does not
# answer is an error, not a reason to take another Quickshell.
#
# Prints what it took, before any test (the launcher line for the lock need only):
#
#   tools: system (PATH, not pinned) — labwc 0.9.1, setpriv 2.42.4, Hyprland 0.57.2
#   tools: nix (tests/lock/tools.nix, pinned: /nix/store/…-h2s-locktest-tools, remembered from an earlier run) — …
#   launcher: /…/tests/lock/launcher.sh (the test bed's stand-in: no LOCKTEST_LAUNCHER, no h2s-shell on PATH)
#   quickshell: /usr/bin/qs 0.3.2 (asked of the launcher /…/tests/lock/launcher.sh)
#
# Versions are printed, not checked. What is missing is a set-up error naming every missing
# tool at once, each with its use; nothing is skipped and nothing else is tried.
#
# Sets LOCKTEST_TOOL_SOURCE (nix or system), LOCKTEST_TOOLS (tools.nix's store path; empty
# with system, until the caller has made the set), LOCKTEST_LABWC, SETPRIV,
# LOCKTEST_LAUNCHER (empty when the unit need found none), LOCKTEST_LAUNCHER_FROM,
# LOCKTEST_QS.

# What the tests use each tool for: the text of a missing-tool error
tool_use() {
    case "${1##*/}" in
        labwc) echo "the headless compositor the suites' windows open in" ;;
        setpriv) echo "starts every test process with no new privileges" ;;
        setsid) echo "puts the compositor in a process group of its own, to be stopped whole" ;;
        timeout) echo "ends a compositor or a Quickshell that hangs" ;;
        fc-match) echo "the characters of the theme's font, for the glyphs suite" ;;
        Hyprland | hyprctl) echo "the compositor the lock screen is tested in" ;;
        grim) echo "screenshots of the lock screen" ;;
        python3) if [ "${LOCKTEST_NEED:-}" = python ]; then echo "reads the shell's answers, JSON"; else echo "the virtual keyboard and pointer"; fi ;;
        xkbcli) echo "tells the virtual keyboard which keys type a character" ;;
        dbus-daemon | gdbus) echo "a private session bus for the notification tests" ;;
        wl-copy | wl-paste) echo "the primary selection of the paste test" ;;
        wlr-randr) echo "sets the headless output's size" ;;
        pkg-config) echo "finds the Wayland protocol files the input bindings are generated from" ;;
        pywayland) echo "the Python module the virtual keyboard and pointer speak Wayland with, and its scanner" ;;
        wayland.xml | xdg-shell.xml) echo "a protocol file the input bindings are generated from" ;;
        ltproto) echo "the Python bindings of the input protocols" ;;
        us.xkb | keymaps) echo "the layouts the virtual keyboard sends" ;;
        *) echo "used by the tests" ;;
    esac
}

# version_line <program>: the first line the program prints when asked for its version
# (`--version` prints and exits; the program gets an empty environment, so nothing of the
# session reaches it)
version_line() { timeout 5 env -i "$1" --version 2> /dev/null < /dev/null | head -n 1; }
# version_number <line>: the first version number in it. A line without one is "version
# unknown", never a guess.
version_number() {
    local version
    version=$(printf '%s\n' "$1" | grep -o -E '[0-9]+(\.[0-9]+)+[A-Za-z0-9.+~-]*' | head -n 1)
    echo "${version:-version unknown}"
}
tool_version() { version_number "$(version_line "$1")"; }

case "${LOCKTEST_NEED:-}" in
    unit | lock | python) ;;
    *) setup_error "resolve.sh: LOCKTEST_NEED must be unit, lock or python, not '${LOCKTEST_NEED:-}'" ;;
esac

# ---- The source -----------------------------------------------------------------------
case "${H2S_TEST_TOOLS:-}" in
    nix)
        type -P nix > /dev/null || setup_error "H2S_TEST_TOOLS=nix, but there is no nix command on PATH"
        LOCKTEST_TOOL_SOURCE=nix
        ;;
    system) LOCKTEST_TOOL_SOURCE=system ;;
    "") if type -P nix > /dev/null; then LOCKTEST_TOOL_SOURCE=nix; else LOCKTEST_TOOL_SOURCE=system; fi ;;
    *) setup_error "H2S_TEST_TOOLS must be nix or system, not '$H2S_TEST_TOOLS'" ;;
esac

# ---- The pinned set's path, remembered ------------------------------------------------
# tools_inputs: the files the build of tools.nix is made from, one per line, relative to
# this directory: tools.nix and every file it names with a relative path — one that starts
# with ./ or ../, in its code or in a comment (a directory named so: every file in it). Fails when one of them is not there — then nothing is
# remembered. A file tools.nix reaches any other way (a path put together from strings, a
# file one of these imports) has to be added here: a remembered path that such a change
# does not move would be tests run with old tools.
tools_inputs() {
    local path
    echo tools.nix
    while IFS= read -r path; do
        if [ -f "$path" ]; then
            echo "$path"
        elif [ -d "$path" ]; then
            find "$path" -type f || return 1
        else
            return 1
        fi
    done < <(grep -o -E '\.{1,2}/[A-Za-z0-9._+-][A-Za-z0-9._/+-]*' tools.nix | LC_ALL=C sort -u)
}
# tools_cache_file: the file the path is remembered in, for the tree as it is now; fails
# when there is no way to remember one
tools_cache_file() {
    local base=${XDG_CACHE_HOME:-${HOME:+$HOME/.cache}} inputs key
    [[ "$base" == /* ]] && type -P sha256sum > /dev/null && type -P uname > /dev/null \
        && type -P find > /dev/null && type -P sort > /dev/null && type -P mv > /dev/null || return 1
    inputs=$(cd "$LOCKTEST_DIR" && tools_inputs) && [ -n "$inputs" ] || return 1
    inputs=$(LC_ALL=C sort -u <<< "$inputs") || return 1
    local names=()
    mapfile -t names <<< "$inputs"
    # The system, and each file's name and contents (a file renamed is another build too)
    local system sums
    system=$(uname -sm) && sums=$(cd "$LOCKTEST_DIR" && sha256sum -- "${names[@]}") || return 1
    key=$(printf '%s\n' "h2s-shell test tools 1" "$system" "$sums" | sha256sum) || return 1
    key=${key%% *}
    [ ${#key} = 64 ] || return 1
    echo "$base/h2s-shell-tests/tools-nix-$key"
}
# pinned_parts: what this caller needs the pinned set to hold
pinned_parts() {
    if [ "$LOCKTEST_NEED" = lock ]; then
        printf '%s\n' "${lock_programs[@]/#/bin/}" share/ltproto share/us.xkb share/keymaps
    elif [ "$LOCKTEST_NEED" = python ]; then
        echo bin/python3
    else
        printf '%s\n' bin/labwc bin/setpriv bin/fc-match
    fi
}
# remembered_tools <file>: the path in it, when it is still a tool set this caller can use.
# Only a file of the user's own in a directory of the user's own: the runner executes
# programs from the path it names, and with the cache in a directory others can write,
# another user could have put the file there
remembered_tools() {
    local path part
    [ -O "$1" ] && [ -O "${1%/*}" ] || return 1
    { IFS= read -r path < "$1"; } 2> /dev/null || return 1
    [[ "$path" == /* ]] && [ -d "$path" ] || return 1
    while IFS= read -r part; do
        [ -e "$path/$part" ] || return 1
    done < <(pinned_parts)
    echo "$path"
}
# remember_tools <file> <path>: written beside it and moved into place, so that a reader
# never sees half a path. Not being able to is not an error: nix is asked next time
remember_tools() {
    local directory=${1%/*} new
    mkdir -p "$directory" 2> /dev/null || return 0
    new=$(mktemp "$directory/.tools-nix.XXXXXX" 2> /dev/null) || return 0
    if printf '%s\n' "$2" > "$new" 2> /dev/null && mv -f "$new" "$1" 2> /dev/null; then return 0; fi
    rm -f "$new"
}

# The programs of the lock bed's set, as tools.nix's bin/ names them
lock_programs=(labwc Hyprland hyprctl grim python3 setpriv xkbcli dbus-daemon gdbus wl-copy wl-paste wlr-randr)

# ---- Tools ----------------------------------------------------------------------------
# Everything missing is collected and reported at once, below
missing=()
if [ "$LOCKTEST_TOOL_SOURCE" = nix ]; then
    # Pinned in tools.nix; built (or fetched from nix's binary cache) once and reused from
    # the store. The path nix gave last time is taken when it still stands (above)
    LOCKTEST_TOOLS=""
    tools_remembered=""
    tools_cache=$(tools_cache_file) || tools_cache=""
    if [ -n "$tools_cache" ] && [ "${H2S_TEST_TOOLS_CACHE:-}" != 0 ] && LOCKTEST_TOOLS=$(remembered_tools "$tools_cache"); then
        tools_remembered=1
    else
        echo "resolving tools (tools.nix)…"
        nix_log=$(mktemp "$temp_base/locktest-nix.XXXXXX") || setup_error "cannot create a temp file in $temp_base"
        LOCKTEST_TOOLS=$(nix build --no-link --print-out-paths --impure -f "$LOCKTEST_DIR/tools.nix" 2> "$nix_log" | tail -n 1)
        if [ -z "$LOCKTEST_TOOLS" ]; then
            cat "$nix_log" >&2
            rm -f "$nix_log"
            setup_error "nix could not build tests/lock/tools.nix (output above)"
        fi
        rm -f "$nix_log"
    fi
    while IFS= read -r tool; do
        [ -e "$LOCKTEST_TOOLS/$tool" ] || missing+=("the pinned tool set ($LOCKTEST_TOOLS) lacks $tool ($(tool_use "$tool"))")
    done < <(pinned_parts)
    # Remembered only when it is a set this caller could use
    [ -z "$tools_remembered" ] && [ -n "$tools_cache" ] && [ ${#missing[@]} -eq 0 ] && remember_tools "$tools_cache" "$LOCKTEST_TOOLS"
    LOCKTEST_LABWC=$LOCKTEST_TOOLS/bin/labwc
    SETPRIV=$LOCKTEST_TOOLS/bin/setpriv
    LOCKTEST_PYTHON=$LOCKTEST_TOOLS/bin/python3
    if [ "$LOCKTEST_NEED" = python ]; then needed_tools=(timeout); else needed_tools=(setsid timeout); fi
else
    LOCKTEST_TOOLS=""
    LOCKTEST_LABWC=$(type -P labwc)
    SETPRIV=$(type -P setpriv)
    LOCKTEST_PYTHON=$(type -P python3)
    if [ "$LOCKTEST_NEED" = python ]; then
        needed_tools=(python3 timeout)
    elif [ "$LOCKTEST_NEED" = lock ]; then
        needed_tools=("${lock_programs[@]}" pkg-config setsid timeout)
    else
        needed_tools=(labwc setpriv setsid timeout fc-match)
    fi
fi
for tool in "${needed_tools[@]}"; do
    type -P "$tool" > /dev/null || missing+=("$tool not found on PATH ($(tool_use "$tool"))")
done

# The python need ends here: no launcher, no Quickshell
if [ "$LOCKTEST_NEED" = python ]; then
    if [ ${#missing[@]} -gt 0 ]; then
        setup_error "nothing was run, the tools are not all there (tools from: $LOCKTEST_TOOL_SOURCE):$(printf '\n  %s' "${missing[@]}")"
    fi
    if [ "$LOCKTEST_TOOL_SOURCE" = nix ]; then
        echo "tools: nix (tests/lock/tools.nix, pinned: $LOCKTEST_TOOLS${tools_remembered:+, remembered from an earlier run}) — python3 $(tool_version "$LOCKTEST_PYTHON")"
    else
        echo "tools: system (PATH, not pinned) — python3 $(tool_version "$LOCKTEST_PYTHON")"
    fi
    LOCKTEST_LAUNCHER="" LOCKTEST_LAUNCHER_FROM="" LOCKTEST_QS=""
    return 0
fi

# The lock bed's set from the system: what its share/ is made from. Each is looked at only
# when the program that says is there (one that is not is in the list already).
# protocol_file <pkg-config package> <path below its pkgdatadir>: the file's path, if it is there
protocol_file() {
    local directory
    directory=$(timeout 5 "$system_pkg_config" --variable=pkgdatadir "$1" 2> /dev/null < /dev/null) || return 1
    [ -n "$directory" ] && [ -f "$directory/$2" ] && echo "$directory/$2"
}
if [ "$LOCKTEST_NEED" = lock ] && [ "$LOCKTEST_TOOL_SOURCE" = system ]; then
    system_python=$(type -P python3)
    system_pkg_config=$(type -P pkg-config)
    system_xkbcli=$(type -P xkbcli)
    # (Asked with nothing of the session but PATH; -I: nothing of the user's own packages)
    if [ -n "$system_python" ] && type -P timeout > /dev/null \
        && ! timeout 20 env -i PATH="$PATH" "$system_python" -I -c 'import pywayland.client, pywayland.scanner' > /dev/null 2>&1 < /dev/null; then
        missing+=("pywayland cannot be imported by $system_python ($(tool_use pywayland))")
    fi
    if [ -n "$system_pkg_config" ] && type -P timeout > /dev/null; then
        wayland_xml=$(protocol_file wayland-scanner wayland.xml) \
            || missing+=("wayland.xml not found where pkg-config says wayland-scanner keeps it ($(tool_use wayland.xml))")
        xdg_shell_xml=$(protocol_file wayland-protocols stable/xdg-shell/xdg-shell.xml) \
            || missing+=("xdg-shell.xml not found where pkg-config says wayland-protocols keeps it ($(tool_use xdg-shell.xml))")
    fi
fi

# make_system_tools <directory>: the lock bed's set from the system's tools, as tools.nix
# lays it out (the caller then hands <directory> on as LOCKTEST_TOOLS). <directory> is new
# and the run's own. bin/ links to the programs found on PATH above; share/ is generated
# with them, by the commands tools.nix runs, with nothing of the user's (an XKB config in
# the home directory would change the keymaps). A failure is a set-up error.
make_system_tools() {
    local directory=$1 tool log
    [ "$LOCKTEST_NEED" = lock ] && [ "$LOCKTEST_TOOL_SOURCE" = system ] \
        || setup_error "make_system_tools is for the lock need with the system's tools"
    mkdir -p "$directory/bin" "$directory/share/keymaps" "$directory/home" \
        || setup_error "cannot create the tool set in $directory"
    for tool in "${lock_programs[@]}"; do
        ln -s "$(type -P "$tool")" "$directory/bin/$tool" || setup_error "cannot link $tool into $directory/bin"
    done
    log=$directory/generate.log
    if ! env -i PATH="$PATH" ${PKG_CONFIG_PATH:+PKG_CONFIG_PATH="$PKG_CONFIG_PATH"} HOME="$directory/home" \
        "$system_python" -I -B -m pywayland.scanner -o "$directory/share/ltproto" -i \
        "$wayland_xml" "$LOCKTEST_DIR/protocols/virtual-keyboard-unstable-v1.xml" \
        "$LOCKTEST_DIR/protocols/wlr-virtual-pointer-unstable-v1.xml" "$xdg_shell_xml" > "$log" 2>&1 < /dev/null \
        || ! touch "$directory/share/ltproto/__init__.py" 2>> "$log"; then
        cat "$log" >&2
        setup_error "pywayland's scanner could not generate the input protocol bindings (output above)"
    fi
    # compile_keymap <name> <xkbcli options…>: share/keymaps/<name>.xkb
    compile_keymap() {
        local name=$1
        shift
        env -i HOME="$directory/home" "$system_xkbcli" compile-keymap --rules evdev --model pc105 "$@" \
            > "$directory/share/keymaps/$name.xkb" 2> "$log" < /dev/null && [ -s "$directory/share/keymaps/$name.xkb" ] && return 0
        cat "$log" >&2
        setup_error "xkbcli could not compile the $name keymap (output above)"
    }
    # The layouts a test may type with: the same three, by the same options, as tools.nix
    compile_keymap us --layout us
    compile_keymap us-intl --layout us --variant intl
    compile_keymap us-compose --layout us --options compose:ralt
    cp "$directory/share/keymaps/us.xkb" "$directory/share/us.xkb" || setup_error "cannot write $directory/share/us.xkb"
    rm -rf "$log" "$directory/home"
}

# ---- Quickshell: what can be said without starting anything ---------------------------
quickshell_from=""
if [ -n "${LOCKTEST_QS:-}" ]; then
    { [ -f "$LOCKTEST_QS" ] && [ -x "$LOCKTEST_QS" ]; } || setup_error "LOCKTEST_QS ($LOCKTEST_QS) is not an executable file"
    quickshell_from="LOCKTEST_QS"
fi
# The launcher: the one named, else the installed one, else — for the lock need, which
# starts the shell through it — the test bed's stand-in
LOCKTEST_LAUNCHER_FROM=""
launcher_said=""
if [ -n "${LOCKTEST_LAUNCHER:-}" ]; then
    LOCKTEST_LAUNCHER_FROM=given
    launcher_said="LOCKTEST_LAUNCHER"
elif LOCKTEST_LAUNCHER=$(type -P h2s-shell); then
    LOCKTEST_LAUNCHER_FROM=path
    launcher_said="h2s-shell on PATH"
elif [ "$LOCKTEST_NEED" = lock ]; then
    LOCKTEST_LAUNCHER=$LOCKTEST_DIR/launcher.sh
    LOCKTEST_LAUNCHER_FROM=stand-in
    launcher_said="the test bed's stand-in: no LOCKTEST_LAUNCHER, no h2s-shell on PATH"
else
    LOCKTEST_LAUNCHER=""
fi
if [ -n "$LOCKTEST_LAUNCHER" ]; then
    case "$LOCKTEST_LAUNCHER_FROM" in given) launcher_name="LOCKTEST_LAUNCHER" ;; *) launcher_name="the launcher" ;; esac
    { [ -f "$LOCKTEST_LAUNCHER" ] && [ -x "$LOCKTEST_LAUNCHER" ]; } || setup_error "$launcher_name ($LOCKTEST_LAUNCHER) is not an executable file"
fi
if [ -z "$quickshell_from" ] && [ -z "$LOCKTEST_LAUNCHER" ]; then
    LOCKTEST_QS=$(type -P qs || type -P quickshell)
    if [ -n "$LOCKTEST_QS" ]; then
        quickshell_from="PATH"
    else
        missing+=("Quickshell (qs or quickshell) not found on PATH (it runs the suites; LOCKTEST_QS names one, LOCKTEST_LAUNCHER a launcher to ask)")
    fi
fi

if [ ${#missing[@]} -gt 0 ]; then
    setup_error "nothing was run, the tests' tools are not all there (tools from: $LOCKTEST_TOOL_SOURCE):$(printf '\n  %s' "${missing[@]}")"
fi

if [ "$LOCKTEST_TOOL_SOURCE" = nix ]; then
    tools_line="tools: nix (tests/lock/tools.nix, pinned: $LOCKTEST_TOOLS${tools_remembered:+, remembered from an earlier run})"
    pinned_hyprland=$(version_line "$LOCKTEST_TOOLS/bin/Hyprland")
    hyprland_version=$(version_number "$pinned_hyprland")
else
    tools_line="tools: system (PATH, not pinned)"
    hyprland_version=$(tool_version "$(type -P Hyprland)")
fi
tools_line+=" — labwc $(tool_version "$LOCKTEST_LABWC"), setpriv $(tool_version "$SETPRIV")"
[ "$LOCKTEST_NEED" = lock ] && tools_line+=", Hyprland $hyprland_version"
echo "$tools_line"
[ "$LOCKTEST_NEED" = lock ] && echo "launcher: $LOCKTEST_LAUNCHER ($launcher_said)"

# The pinned Hyprland is meant to be the system's: say so when it is not (the whole line
# is compared: it names the commit too), and when that cannot be told
system_hyprland=$(type -P Hyprland)
if [ "$LOCKTEST_TOOL_SOURCE" = nix ] && [ -n "$system_hyprland" ]; then
    system_version=$(version_line "$system_hyprland")
    if [ -z "$pinned_hyprland" ] || [ -z "$system_version" ]; then
        echo "NOTE: cannot compare the pinned Hyprland (${pinned_hyprland:-version unknown}) with the system's (${system_version:-version unknown})"
    elif [ "$pinned_hyprland" != "$system_version" ]; then
        echo "NOTE: the pinned Hyprland ($pinned_hyprland) is not the system's ($system_version): move the pin in tools.nix"
    fi
fi

# ---- Quickshell: the one the launcher runs --------------------------------------------
# Asked of the launcher itself, by pointing it at a stand-in shell folder whose launch.sh
# only says which qs it would run. A launcher that ignored H2S_SHELL_DIR would start a real
# shell here, so the probe gets nothing of the session: an empty environment but PATH, a
# private HOME, an empty runtime dir (no Wayland socket to show anything on), D-Bus
# addresses that lead nowhere, no new privileges, its own process group, and a few seconds.
if [ -z "$quickshell_from" ]; then
    probe=$(mktemp -d "$temp_base/locktest-probe.XXXXXX") || setup_error "cannot create a temp dir in $temp_base"
    mkdir -p "$probe/scripts" "$probe/home" "$probe/run" || setup_error "cannot fill the probe dir $probe"
    chmod 700 "$probe/run"
    printf '#!/bin/sh\ncommand -v qs\n' > "$probe/scripts/launch.sh"
    chmod +x "$probe/scripts/launch.sh"
    probe_output=$(env -i PATH="$PATH" HOME="$probe/home" XDG_RUNTIME_DIR="$probe/run" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$probe/run/no-session-bus" \
        DBUS_SYSTEM_BUS_ADDRESS="unix:path=$probe/run/no-system-bus" \
        LIBSEAT_BACKEND=disabled-for-test H2S_SHELL_DIR="$probe" \
        "$SETPRIV" --no-new-privs setsid --wait timeout -k 2 "$PROBE_TIMEOUT" "$LOCKTEST_LAUNCHER" \
        2> /dev/null < /dev/null)
    probe_status=$?
    rm -rf "$probe"
    probe=""
    if [ "$probe_status" = 124 ] || [ "$probe_status" = 137 ]; then
        setup_error "the launcher ($LOCKTEST_LAUNCHER) did not answer within ${PROBE_TIMEOUT} s when asked which qs it runs — does it honour H2S_SHELL_DIR? (or set LOCKTEST_QS)"
    fi
    if [ "$(printf '%s\n' "$probe_output" | wc -l)" != 1 ] || [[ "$probe_output" != /* ]] \
        || [ ! -f "$probe_output" ] || [ ! -x "$probe_output" ]; then
        setup_error "the launcher ($LOCKTEST_LAUNCHER) did not name an executable qs (status $probe_status, said: '${probe_output:0:200}'); set LOCKTEST_QS"
    fi
    LOCKTEST_QS=$probe_output
    quickshell_from="asked of the launcher $LOCKTEST_LAUNCHER"
fi
echo "quickshell: $LOCKTEST_QS $(tool_version "$LOCKTEST_QS") ($quickshell_from)"
