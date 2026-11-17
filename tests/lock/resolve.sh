# shellcheck shell=bash
# Finds the tests' tools and Quickshell: one way to find them, for tests/headless.sh (the
# unit and module suites) and tests/lock/run.sh. Sourced. The caller defines setup_error
# (prints, cleans up, exits 2), LOCKTEST_DIR (this directory), temp_base (a plain temp
# path), PROBE_TIMEOUT, `probe` (empty; the launcher probe's temp dir while it exists, for
# setup_error to remove) and LOCKTEST_NEED, what it uses:
#
#   unit   labwc, setpriv, setsid, timeout
#   lock   the whole of tools.nix, setsid, timeout, and a launcher
#
# The tools come from one source for the whole run, never tool by tool (they depend on each
# other, and a mix of pinned and system parts is a configuration nobody tests):
#
#   H2S_TEST_TOOLS=nix      the pinned build of tools.nix
#   H2S_TEST_TOOLS=system   every tool from PATH, whatever version is installed
#   (not set)               nix when a `nix` command exists, else system
#
# setsid and timeout are taken from PATH with either source (tools.nix does not hold them).
# The lock need can only be met by nix: the protocol bindings and keymaps it uses are built
# by tools.nix alone.
#
# Quickshell is never pinned here. In this order: LOCKTEST_QS; the one the launcher runs
# (LOCKTEST_LAUNCHER, else h2s-shell on PATH), asked of the launcher; qs, then quickshell,
# on PATH. A launcher that is there and does not answer is an error, not a reason to take
# another Quickshell.
#
# Prints what it took, before any test:
#
#   tools: system (PATH, not pinned) — labwc 0.9.1, setpriv 2.42.4
#   quickshell: /usr/bin/qs 0.3.2 (PATH)
#
# Versions are printed, not checked. What is missing is a set-up error naming every missing
# tool at once, each with its use; nothing is skipped and nothing else is tried.
#
# Sets LOCKTEST_TOOL_SOURCE (nix or system), LOCKTEST_TOOLS (tools.nix's store path; empty
# with system), LOCKTEST_LABWC, SETPRIV, LOCKTEST_LAUNCHER (empty when the unit need found
# none), LOCKTEST_QS.

# What the tests use each tool for: the text of a missing-tool error
tool_use() {
    case "${1##*/}" in
        labwc) echo "the headless compositor the suites' windows open in" ;;
        setpriv) echo "starts every test process with no new privileges" ;;
        setsid) echo "puts the compositor in a process group of its own, to be stopped whole" ;;
        timeout) echo "ends a compositor or a Quickshell that hangs" ;;
        Hyprland | hyprctl) echo "the compositor the lock screen is tested in" ;;
        grim) echo "screenshots of the lock screen" ;;
        python3) echo "the virtual keyboard and pointer" ;;
        xkbcli) echo "tells the virtual keyboard which keys type a character" ;;
        dbus-daemon | gdbus) echo "a private session bus for the notification tests" ;;
        wl-copy | wl-paste) echo "the primary selection of the paste test" ;;
        wlr-randr) echo "sets the headless output's size" ;;
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
    unit | lock) ;;
    *) setup_error "resolve.sh: LOCKTEST_NEED must be unit or lock, not '${LOCKTEST_NEED:-}'" ;;
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
if [ "$LOCKTEST_NEED" = lock ] && [ "$LOCKTEST_TOOL_SOURCE" = system ]; then
    setup_error "the lock test bed cannot take its tools from the system yet (its protocol bindings and keymaps are built by tests/lock/tools.nix only): it needs nix. The unit and module suites run without."
fi

# ---- Tools ----------------------------------------------------------------------------
# Everything missing is collected and reported at once, below
missing=()
if [ "$LOCKTEST_TOOL_SOURCE" = nix ]; then
    # Pinned in tools.nix; built (or fetched from the cache) once and reused from the store
    echo "resolving tools (tools.nix)…"
    nix_log=$(mktemp "$temp_base/locktest-nix.XXXXXX") || setup_error "cannot create a temp file in $temp_base"
    LOCKTEST_TOOLS=$(nix build --no-link --print-out-paths --impure -f "$LOCKTEST_DIR/tools.nix" 2> "$nix_log" | tail -n 1)
    if [ -z "$LOCKTEST_TOOLS" ]; then
        cat "$nix_log" >&2
        rm -f "$nix_log"
        setup_error "nix could not build tests/lock/tools.nix (output above)"
    fi
    rm -f "$nix_log"
    if [ "$LOCKTEST_NEED" = lock ]; then
        needed_tools=(bin/labwc bin/Hyprland bin/hyprctl bin/grim bin/python3 bin/setpriv bin/xkbcli bin/dbus-daemon
            bin/gdbus bin/wl-copy bin/wl-paste bin/wlr-randr share/ltproto share/us.xkb share/keymaps)
    else
        needed_tools=(bin/labwc bin/setpriv)
    fi
    for tool in "${needed_tools[@]}"; do
        [ -e "$LOCKTEST_TOOLS/$tool" ] || missing+=("the pinned tool set ($LOCKTEST_TOOLS) lacks $tool ($(tool_use "$tool"))")
    done
    LOCKTEST_LABWC=$LOCKTEST_TOOLS/bin/labwc
    SETPRIV=$LOCKTEST_TOOLS/bin/setpriv
    needed_tools=(setsid timeout)
else
    LOCKTEST_TOOLS=""
    LOCKTEST_LABWC=$(type -P labwc)
    SETPRIV=$(type -P setpriv)
    needed_tools=(labwc setpriv setsid timeout)
fi
for tool in "${needed_tools[@]}"; do
    type -P "$tool" > /dev/null || missing+=("$tool not found on PATH ($(tool_use "$tool"))")
done

# ---- Quickshell: what can be said without starting anything ---------------------------
quickshell_from=""
if [ -n "${LOCKTEST_QS:-}" ]; then
    { [ -f "$LOCKTEST_QS" ] && [ -x "$LOCKTEST_QS" ]; } || setup_error "LOCKTEST_QS ($LOCKTEST_QS) is not an executable file"
    quickshell_from="LOCKTEST_QS"
fi
LOCKTEST_LAUNCHER=${LOCKTEST_LAUNCHER:-$(type -P h2s-shell)}
if [ -n "$LOCKTEST_LAUNCHER" ]; then
    { [ -f "$LOCKTEST_LAUNCHER" ] && [ -x "$LOCKTEST_LAUNCHER" ]; } || setup_error "LOCKTEST_LAUNCHER ($LOCKTEST_LAUNCHER) is not an executable file"
elif [ "$LOCKTEST_NEED" = lock ]; then
    # The shell is started the way it is for real: through the h2s-shell launcher
    missing+=("h2s-shell not found on PATH (the launcher the shell under test is started through; LOCKTEST_LAUNCHER names another)")
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
    tools_line="tools: nix (tests/lock/tools.nix, pinned: $LOCKTEST_TOOLS)"
    pinned_hyprland=$(version_line "$LOCKTEST_TOOLS/bin/Hyprland")
else
    tools_line="tools: system (PATH, not pinned)"
fi
tools_line+=" — labwc $(tool_version "$LOCKTEST_LABWC"), setpriv $(tool_version "$SETPRIV")"
[ "$LOCKTEST_NEED" = lock ] && tools_line+=", Hyprland $(version_number "$pinned_hyprland")"
echo "$tools_line"

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
