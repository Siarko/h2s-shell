# shellcheck shell=bash
# The headless isolation the QML suites run in, shared by tests/run-unit.sh (the shell's
# suites, tests.qml) and tests/run-modules.sh (modules' suites, tests-modules.qml). Sourced;
# the caller sets HEADLESS_NAME (its name, for messages) and REPO (the shell's tree, the
# config root Quickshell is started in) first.
#
# The compositor is a headless labwc (wlroots' headless backend, no input devices) in a
# private runtime dir (outside it, a labwc built with Xwayland also holds an X socket in
# /tmp/.X11-unix and its /tmp/.X<n>-lock for the length of a run, on a display number no
# session uses; nothing is started on it, and both go when labwc ends), with D-Bus addresses that lead nowhere, a private HOME and XDG
# directories (Config is read-only under the runners anyway), no new privileges. The tools
# are found by tests/lock/resolve.sh, shared with the lock test bed: labwc and setpriv from
# the pinned tests/lock/tools.nix where there is a `nix` command, else from PATH
# (H2S_TEST_TOOLS=nix or =system says which); Quickshell is LOCKTEST_QS, else the one the
# h2s-shell launcher runs, else qs or quickshell on PATH. The run's first lines say what was
# taken; a missing tool is a set-up error (exit 2) that names it.
#
# Quickshell and the compositor each run under a memory cap, inside the run's memory budget
# (the compositor only where there is a budget: a scope of the user's service manager)
# (tests/memory-cap.sh: H2S_TEST_MEMORY_MAX, 1536M by default, H2S_TEST_MEMORY_BUDGET; 0 for
# none), so that a suite that runs away is stopped there instead of filling the machine's
# memory. A Quickshell stopped at either is said so by the verdict, with the suites that had
# not reported; one whose scope could not be started (the service manager not answering) too.
#
# Nothing here is shared with another run but the processor — every run has its own
# compositor, runtime dir and home — so these runners take no lock and run side by side
# (the lock test bed, whose tests depend on timing, takes one: tests/lock/run.sh). The
# processor they do share with it: a lock-bed failure seen while these were running on a
# small machine is run again alone before it is believed.
#
#   headless_resolve                       the tools found and what was taken printed (not
#                                          with HEADLESS_QUIET_RESOLVE set); exit 2 on failure
#   headless_setup                         that, then the private dirs and the compositor
#                                          (exit 2 on failure)
#   headless_run <root.qml> <copy> [VAR=value…]
#                                          Quickshell on that root file, with those variables
#                                          added; its output printed (and copied to <copy>
#                                          unless ""); HEADLESS_LOG, HEADLESS_STATUS set.
#                                          An interrupt (INT, TERM, HUP) ends the run at
#                                          once, Quickshell and the compositor with it
#   headless_verdict <title> <expected> <where> [exactly [<suite name>…]]
#                                          the summary; returns 1 on any FAIL line, a
#                                          TypeError / ReferenceError, a non-zero exit of
#                                          Quickshell (a crash after a partial summary
#                                          included), a time-out, a stop at the memory
#                                          cap (HEADLESS_CAPPED), a suite reporting 0/0, more
#                                          PASS lines than the summaries count (a check after
#                                          its suite reported), a suite that needs a
#                                          process of its own (OWN-PROCESS) beside others,
#                                          or fewer suites reporting
#                                          than <expected> (<where> says where they are
#                                          registered, or "selected"); with `exactly` (a
#                                          selection was run) also on more suites reporting
#                                          than <expected>, and on a named suite (TestCase's
#                                          suiteName) not reporting; 0 otherwise

LOCKTEST_DIR=$REPO/tests/lock
# Read by resolve.sh
# shellcheck disable=SC2034
PROBE_TIMEOUT=5
# What these runners use of the tools: the compositor, not the lock bed's whole set; the
# caller's HEADLESS_NEED names another need of resolve.sh (tests/run-mockups.sh: mockups)
# shellcheck disable=SC2034
LOCKTEST_NEED=${HEADLESS_NEED:-unit}
probe=""
work=""

headless_cleanup() {
    # A second interrupt while this runs must not end it half-way, with the compositor,
    # Quickshell and the temp dir left behind
    trap '' INT TERM HUP
    # Quickshell, when the run is ended while it runs: `timeout` hands TERM on to it; what
    # is left of the two after a moment is killed. The group: timeout leads a process group
    # of its own, named after its pid, and that number stays ours while anything is in the
    # group — what outlives timeout there is killed too. timeout itself only when it is
    # still there: once it is gone its pid names nothing of ours.
    if [ -n "${quickshell_pid:-}" ]; then
        local quickshell_gone=""
        kill -TERM "$quickshell_pid" 2> /dev/null
        for _ in $(seq 1 20); do
            kill -0 "$quickshell_pid" 2> /dev/null || { quickshell_gone=1; break; }
            sleep 0.1
        done
        kill -KILL -- "-$quickshell_pid" 2> /dev/null
        [ -n "$quickshell_gone" ] || kill -KILL "$quickshell_pid" 2> /dev/null
        # A scope stopped at the cap stays listed by the service manager until cleared
        memory_cap_hit "${headless_cap_unit:-}" 1 > /dev/null 2>&1
    fi
    # The compositor: asked to end, waited for (it takes some tens of milliseconds; two
    # seconds at most), and what is left of its group then is killed. labwc_pid is the
    # `timeout` that leads the group; it ends when labwc has, and until this bash has
    # waited for it, it is still listed, as a zombie
    if [ -n "${labwc_pid:-}" ]; then
        local state
        kill -TERM -- "-$labwc_pid" 2> /dev/null
        for _ in $(seq 1 100); do
            state=""
            { read -r _ _ state _ < "/proc/$labwc_pid/stat"; } 2> /dev/null
            [ -z "$state" ] || [ "$state" = Z ] && break
            sleep 0.02
        done
        kill -KILL -- "-$labwc_pid" 2> /dev/null
        memory_cap_hit "${headless_labwc_unit:-}" 1 > /dev/null 2>&1
    fi
    # The run's budget, when this runner made it (a runner started alone)
    memory_cap_finish 2> /dev/null
    [ -n "$probe" ] && rm -rf "$probe"
    [ -n "$work" ] && rm -rf "$work"
}
trap headless_cleanup EXIT
trap 'exit 130' INT TERM HUP

setup_error() {
    echo "$HEADLESS_NAME: $*" >&2
    exit 2
}

headless_resolve() {
    [ "$(id -u)" != 0 ] || setup_error "do not run as root"
    # No core files, for this runner and everything it starts: a Quickshell that crashes
    # under test would leave some 15 MB outside the run's directories, and the self-test's
    # stand-in ends itself with SIGSEGV at every run (tests/lock/run.sh does the same)
    ulimit -c 0 2> /dev/null
    # shellcheck disable=SC2034  # read by resolve.sh
    temp_base=${TMPDIR:-/tmp}
    # shellcheck source=memory-cap.sh
    source "$REPO/tests/memory-cap.sh"
    # A shard of tests/run-unit.sh: the runner that started it has printed what was taken
    # (and handed it on: LOCKTEST_QS, H2S_TEST_TOOLS); a set-up error still shows (stderr)
    if [ -n "${HEADLESS_QUIET_RESOLVE:-}" ]; then
        # shellcheck source=lock/resolve.sh
        source "$LOCKTEST_DIR/resolve.sh" > /dev/null
        memory_cap_init quiet
    else
        # shellcheck source=lock/resolve.sh
        source "$LOCKTEST_DIR/resolve.sh"
        memory_cap_init
    fi
}

headless_setup() {
    headless_resolve

    # Short: a Unix socket path is limited to 107 bytes
    work=$(mktemp -d /tmp/ut.XXXXXX) || setup_error "cannot create a temp dir"
    chmod 700 "$work"
    mkdir -p "$work/run" "$work/home" "$work/labwc" "$work/xdg/config" "$work/xdg/cache" "$work/xdg/data" "$work/xdg/state"
    chmod 700 "$work/run"
    echo '<?xml version="1.0"?><labwc_config/>' > "$work/labwc/rc.xml"

    isolated=(env -i PATH="${LOCKTEST_TOOLS:+$LOCKTEST_TOOLS/bin:}$PATH" HOME="$work/home" XDG_RUNTIME_DIR="$work/run"
        XDG_CONFIG_HOME="$work/xdg/config" XDG_CACHE_HOME="$work/xdg/cache" XDG_DATA_HOME="$work/xdg/data"
        XDG_STATE_HOME="$work/xdg/state" LANG=en_US.UTF-8
        DBUS_SESSION_BUS_ADDRESS="unix:path=$work/run/no-session-bus"
        DBUS_SYSTEM_BUS_ADDRESS="unix:path=$work/run/no-system-bus" LIBSEAT_BACKEND=disabled-for-test)

    # In the run's budget, with a cap of its own; not under an address-space limit (prlimit,
    # which has no budget to keep it in): what the compositor reserves is no test's doing
    MEMORY_CAP_PREFIX=() MEMORY_CAP_UNIT=""
    [ "${MEMORY_CAP_MODE:-none}" != systemd ] || memory_cap_wrap labwc
    headless_labwc_unit=$MEMORY_CAP_UNIT
    "${MEMORY_CAP_PREFIX[@]}" "${isolated[@]}" WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_HEADLESS_OUTPUTS=1 \
        "$SETPRIV" --no-new-privs setsid timeout 540 "$LOCKTEST_LABWC" -C "$work/labwc" > "$work/labwc.log" 2>&1 < /dev/null &
    labwc_pid=$!
    for _ in $(seq 1 100); do [ -S "$work/run/wayland-0" ] && break; sleep 0.1; done
    [ -S "$work/run/wayland-0" ] || { cat "$work/labwc.log" >&2; setup_error "the headless compositor did not start"; }
}

headless_run() {
    local root=$1 output_copy=$2
    shift 2
    HEADLESS_LOG=$work/unit.log
    headless_started=$SECONDS
    HEADLESS_CAPPED=""
    memory_cap_wrap quickshell
    headless_cap_unit=$MEMORY_CAP_UNIT
    # Above tests.qml's whole-run limit (_runLimitMs, 420 s), so that the runner names a
    # suite that hangs before this ends it; labwc's (540 s, above) outlasts this
    # The cap's words first: systemd-run execs what follows, so the pid is Quickshell's
    # chain (env, setpriv, timeout) all the same
    "${MEMORY_CAP_PREFIX[@]}" "${isolated[@]}" "$@" WAYLAND_DISPLAY=wayland-0 QT_QPA_PLATFORM=wayland \
        "$SETPRIV" --no-new-privs timeout 480 "$LOCKTEST_QS" -p "$root" > "$HEADLESS_LOG" 2>&1 < /dev/null &
    # Waited for, not run in the foreground: bash runs a trap only when the foreground
    # command ends, so an interrupt would be held until Quickshell is done
    quickshell_pid=$!
    wait "$quickshell_pid"
    HEADLESS_STATUS=$?
    quickshell_pid=""
    memory_cap_hit "$headless_cap_unit" "$HEADLESS_STATUS" "$HEADLESS_LOG" && HEADLESS_CAPPED=1
    headless_cap_unit=""
    [ -n "$output_copy" ] && cp "$HEADLESS_LOG" "$output_copy"
    cat "$HEADLESS_LOG"
}

headless_verdict() {
    local title=$1 expected=$2 where=$3 status=$HEADLESS_STATUS failed=0 start_failure summary fails errors reported name empty passes counted
    shift 3
    summary=$(grep -E -- '^.*--- .*: [0-9]+/[0-9]+ passed' "$HEADLESS_LOG" | sed 's/^.*--- /--- /')
    fails=$(grep -c -E '  FAIL: ' "$HEADLESS_LOG")
    errors=$(grep -c -E 'TypeError|ReferenceError' "$HEADLESS_LOG")
    echo
    echo "$title ($((SECONDS - headless_started)) s, quickshell exit $status):"
    echo "$summary" | sed 's/^/  /'
    [ "$fails" -gt 0 ] && { echo "  $fails check(s) FAILED"; failed=1; }
    [ "$errors" -gt 0 ] && { echo "  $errors TypeError/ReferenceError line(s)"; grep -E 'TypeError|ReferenceError' "$HEADLESS_LOG" | head -n 10 | sed 's/^/    /'; failed=1; }
    if [ -n "${HEADLESS_CAPPED:-}" ]; then
        # What was running then: the selected suites that had not reported, else all the
        # selected ones (the cap can be reached after the last report), else "quickshell"
        local running="" wanted
        if [ "${1:-}" = exactly ]; then
            for wanted in "${@:2}"; do
                grep -q -F -- "--- $wanted: " <<< "$summary" || running="$running${running:+ }$wanted"
            done
            [ -n "$running" ] || running="${*:2}"
        fi
        echo "  ${running:-quickshell}: $(memory_cap_note)"
        failed=1
    elif start_failure=$(memory_cap_start_failed "$HEADLESS_LOG"); then
        echo "  quickshell could not be started under the memory cap: $start_failure"
        failed=1
    elif [ "$status" != 0 ] && memory_cap_slice_gone; then
        echo "  the run's memory budget ($MEMORY_CAP_SLICE) had ended: quickshell ran outside it (exit $status)"
        failed=1
    else
        [ "$status" = 124 ] && { echo "  quickshell timed out"; failed=1; }
        # Any other non-zero status is a failure too: a crash (139: SIGSEGV) after a partial
        # summary with no FAIL line in it must not pass
        [ "$status" != 0 ] && [ "$status" != 124 ] && { echo "  quickshell exited with status $status"; failed=1; }
    fi
    reported=$(printf '%s\n' "$summary" | grep -c -- '^--- ')
    [ "$reported" -lt "$expected" ] && { echo "  only $reported of the $expected suites $where reported"; failed=1; }
    # A suite that checked nothing cannot fail, so it does not pass either
    empty=$(printf '%s\n' "$summary" | sed -n 's/^--- \(.*\): 0\/0 passed.*$/\1/p')
    [ -n "$empty" ] && { printf '%s\n' "$empty" | sed 's/^/  /; s/$/ ran no check (0\/0)/'; failed=1; }
    # Every passed check is counted in its suite's summary: more PASS lines than the
    # summaries count were checks made after a suite had reported (an asynchronous suite
    # that went on after finish()), which nothing would see fail
    passes=$(grep -c -E '  PASS: ' "$HEADLESS_LOG")
    counted=$(printf '%s\n' "$summary" | sed -n 's/^--- .*: \([0-9][0-9]*\)\/[0-9][0-9]* passed.*$/\1/p' | awk '{ sum += $1 } END { print sum + 0 }')
    [ "$passes" -gt "$counted" ] && { echo "  $passes checks passed, the suites' summaries count $counted: a suite checked after it had reported"; failed=1; }
    # A suite that needs a process of its own (TestCase.ownProcess) with others reporting in it
    local own
    own=$(sed -n 's/^.*OWN-PROCESS: \([A-Za-z0-9]*\).*$/\1/p' "$HEADLESS_LOG" | sort -u | paste -s -d ' ')
    [ -n "$own" ] && [ "$reported" -gt 1 ] && { echo "  $own needs a process of its own, and $reported suites reported in it"; failed=1; }
    # A selection: each of its suites, and no other. A suite left out by mistake and one run
    # by mistake are both a wrong answer to "run these"
    if [ "${1:-}" = exactly ]; then
        shift
        [ "$reported" -gt "$expected" ] && { echo "  $reported suites reported, $expected were $where"; failed=1; }
        # A here-string, not printf piped into grep -q: grep ends at the first match, and
        # under pipefail a printf still writing then (it writes line by line) is killed by
        # SIGPIPE, which made a suite that had reported "not report" now and then under load
        for name in "$@"; do
            grep -q -F -- "--- $name: " <<< "$summary" || { echo "  $name did not report"; failed=1; }
        done
    fi
    # The compositor stopped at its cap or the budget under the suites: said, not left to
    # pass for a failure of theirs (looked at only when it is gone: a live one has nothing
    # to say, and its scope would be waited for)
    if [ -n "${headless_labwc_unit:-}" ] && ! kill -0 "${labwc_pid:-0}" 2> /dev/null \
        && memory_cap_hit "$headless_labwc_unit" 1; then
        echo "  the compositor (labwc): $(memory_cap_note)"
        headless_labwc_unit=""
        failed=1
    fi
    [ -n "$summary" ] || { echo "  no suite reported: quickshell did not run them"; failed=1; }
    return $failed
}
