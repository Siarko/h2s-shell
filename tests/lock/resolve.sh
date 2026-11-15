# Finds the test bed's tools, sourced by tests/lock/run.sh and tests/run-unit.sh (one way to
# find them, for both). The caller defines setup_error (prints, cleans up, exits 2),
# LOCKTEST_DIR (this directory), temp_base (a plain temp path), PROBE_TIMEOUT, and `probe`
# (empty; the launcher probe's temp dir while it exists, for setup_error to remove).
# Sets LOCKTEST_TOOLS (tools.nix's store path), SETPRIV, LOCKTEST_LAUNCHER, LOCKTEST_QS.

# ---- Tools ----------------------------------------------------------------------------
# Pinned in tools.nix; built (or fetched from the cache) once and reused from the store
echo "resolving tools (tools.nix)…"
command -v nix > /dev/null || setup_error "nix is needed to provide the test tools"
nix_log=$(mktemp "$temp_base/locktest-nix.XXXXXX") || setup_error "cannot create a temp file in $temp_base"
LOCKTEST_TOOLS=$(nix build --no-link --print-out-paths --impure -f "$LOCKTEST_DIR/tools.nix" 2> "$nix_log" | tail -n 1)
if [ -z "$LOCKTEST_TOOLS" ]; then
    cat "$nix_log" >&2
    rm -f "$nix_log"
    setup_error "nix could not build tests/lock/tools.nix (output above)"
fi
rm -f "$nix_log"
for tool in bin/labwc bin/Hyprland bin/hyprctl bin/grim bin/python3 bin/setpriv bin/xkbcli bin/dbus-daemon bin/gdbus bin/wl-copy bin/wl-paste bin/wlr-randr \
    share/ltproto share/us.xkb share/keymaps; do
    [ -e "$LOCKTEST_TOOLS/$tool" ] || setup_error "the tool set lacks $tool ($LOCKTEST_TOOLS)"
done
SETPRIV=$LOCKTEST_TOOLS/bin/setpriv

# The pinned Hyprland is meant to be the system's: say so when it is not. Both are asked
# for their version only (`--version` prints and exits; no session is contacted).
hyprland_version() { env -i timeout 5 "$1" --version 2> /dev/null | head -n 1; }
system_hyprland=$(command -v Hyprland 2> /dev/null)
if [ -n "$system_hyprland" ]; then
    pinned_version=$(hyprland_version "$LOCKTEST_TOOLS/bin/Hyprland")
    system_version=$(hyprland_version "$system_hyprland")
    [ "$pinned_version" = "$system_version" ] \
        || echo "NOTE: the pinned Hyprland ($pinned_version) is not the system's ($system_version): move the pin in tools.nix"
fi

# The shell is started the way it is for real: through the h2s-shell launcher
LOCKTEST_LAUNCHER=${LOCKTEST_LAUNCHER:-$(command -v h2s-shell)}
[ -x "$LOCKTEST_LAUNCHER" ] || setup_error "no h2s-shell launcher on PATH (set LOCKTEST_LAUNCHER)"

# The Quickshell that launcher runs: asked of the launcher itself, by pointing it at a
# stand-in shell folder whose launch.sh only says which qs it would run. A launcher that
# ignored H2S_SHELL_DIR would start a real shell here, so the probe gets nothing of the
# session: an empty environment but PATH, a private HOME, an empty runtime dir (no
# Wayland socket to show anything on), D-Bus addresses that lead nowhere, no new
# privileges, its own process group, and a few seconds.
if [ -z "${LOCKTEST_QS:-}" ]; then
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
fi
[ -x "${LOCKTEST_QS:-}" ] || setup_error "cannot find the qs the launcher uses (set LOCKTEST_QS)"
