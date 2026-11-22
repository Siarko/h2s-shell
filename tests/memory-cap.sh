# shellcheck shell=bash
# A memory cap on the processes the test runners start, so that a runaway test (a mutant
# that loops appending to a list, a leak) is stopped at the cap instead of filling the
# machine's memory and having the kernel's OOM killer pick among the user's programs.
# Sourced by tests/headless.sh (every Quickshell of tests/run-unit.sh, tests/run-modules.sh,
# tests/run-helper.sh, and through them tests/mutate.sh and tests/soak.sh) and by the lock
# test bed (tests/lock/run.sh says what is taken, tests/lock/lib.sh caps each process of the
# stack).
#
# The cap is H2S_TEST_MEMORY_MAX: a size in systemd's notation (1536M, 2G, bytes without a
# suffix), each process its own; 0 means none. The default, 1536M, leaves room above the
# most a normal run's process was measured to take (its cgroup's peak, page cache and
# Wayland buffers included): a unit shard's Quickshell with many suites built about 0.9 GB,
# a lock-bed shell under its launcher about 0.45 GB, the nested Hyprland about 0.1 GB.
#
# How, in order of preference:
#   systemd  a transient scope of the user's service manager (`systemd-run --user --scope`)
#            with MemoryMax at the cap and no swap: the kernel stops the scope's processes
#            when together they reach it, and the scope's result says so (oom-kill). The
#            scope's process is the command itself (systemd-run execs it): pids, process
#            groups and parents are as they would be without the cap. The manager is reached
#            through the caller's XDG_RUNTIME_DIR (DBUS_SESSION_BUS_ADDRESS when set), kept
#            here at the start (H2S_TEST_USER_RUNTIME_DIR / H2S_TEST_USER_BUS when a runner
#            hands them over to an environment that has the test's private ones); the
#            command itself gets the environment it was given. Taken only when a probe scope
#            shows the cap in its cgroup's memory.max (the memory controller delegated).
#   prlimit  no service manager to reach (CI, a container, a system without a user manager):
#            an address-space limit (RLIMIT_AS) of four times the cap — a Quickshell's
#            address space is about three times what it has resident —, so an allocation
#            past it fails and the process ends (an abort, a crash).
#   none     neither works: a warning says so, and the processes run without a cap.
#
#   memory_cap_init [quiet]       chooses the way, once (MEMORY_CAP_MODE: systemd, prlimit,
#                                 none; MEMORY_CAP_LABEL: the cap as given); says it on
#                                 stdout unless quiet, a warning on stderr when no way works
#   memory_cap_wrap <tag>         MEMORY_CAP_PREFIX: the words to put before a command to run
#                                 it under the cap (empty without one); MEMORY_CAP_UNIT: the
#                                 scope's name (systemd), made of <tag> and a unique part
#   memory_cap_hit <unit> <status> [<log>]
#                                 after the command ended with <status>: true when it was
#                                 stopped at the cap — the scope's result (systemd; a failed
#                                 scope is then cleared from the manager), or an allocation
#                                 failure in <log> (prlimit: the process ends as its own
#                                 code handles that — an abort, an error status)
#   memory_cap_note               "killed at the memory cap (<cap>)" — the words a runner puts
#                                 after what was killed

memory_cap_bytes() {
    local value=$1 number unit
    [[ "$value" =~ ^([0-9]+)([KMGT]?)$ ]] || return 1
    number=${BASH_REMATCH[1]} unit=${BASH_REMATCH[2]}
    case "$unit" in
        K) echo $((number * 1024)) ;;
        M) echo $((number * 1024 * 1024)) ;;
        G) echo $((number * 1024 * 1024 * 1024)) ;;
        T) echo $((number * 1024 * 1024 * 1024 * 1024)) ;;
        *) echo "$number" ;;
    esac
}

# The words that reach the user's service manager: its runtime dir and bus as the caller had
# them, whatever the environment of the command will be
memory_cap_manager_env() {
    MEMORY_CAP_MANAGER_ENV=(env "XDG_RUNTIME_DIR=$MEMORY_CAP_USER_RUNTIME_DIR")
    if [ -n "$MEMORY_CAP_USER_BUS" ]; then
        MEMORY_CAP_MANAGER_ENV+=("DBUS_SESSION_BUS_ADDRESS=$MEMORY_CAP_USER_BUS")
    else
        MEMORY_CAP_MANAGER_ENV+=(-u DBUS_SESSION_BUS_ADDRESS)
    fi
}

memory_cap_init() {
    local quiet=${1:-} probe expected
    MEMORY_CAP_LABEL=${H2S_TEST_MEMORY_MAX:-1536M}
    MEMORY_CAP_MODE=none
    MEMORY_CAP_BYTES=""
    MEMORY_CAP_SERIAL=0
    MEMORY_CAP_EXPAND=()
    if [ -n "${H2S_TEST_USER_RUNTIME_DIR:-}" ]; then
        MEMORY_CAP_USER_RUNTIME_DIR=$H2S_TEST_USER_RUNTIME_DIR MEMORY_CAP_USER_BUS=${H2S_TEST_USER_BUS:-}
    else
        MEMORY_CAP_USER_RUNTIME_DIR=${XDG_RUNTIME_DIR:-} MEMORY_CAP_USER_BUS=${DBUS_SESSION_BUS_ADDRESS:-}
    fi
    if [ "$MEMORY_CAP_LABEL" = 0 ]; then
        [ -n "$quiet" ] || echo "memory cap: none (H2S_TEST_MEMORY_MAX=0)"
        return 0
    fi
    MEMORY_CAP_BYTES=$(memory_cap_bytes "$MEMORY_CAP_LABEL") && [ "$MEMORY_CAP_BYTES" -gt 0 ] || {
        echo "warning: H2S_TEST_MEMORY_MAX is '$MEMORY_CAP_LABEL', not a size (1536M, 2G, 0 for none): the tests run without a memory cap" >&2
        MEMORY_CAP_LABEL=0 MEMORY_CAP_BYTES=""
        return 0
    }
    if [ -n "$MEMORY_CAP_USER_RUNTIME_DIR" ] && type -P systemd-run > /dev/null && type -P systemctl > /dev/null; then
        memory_cap_manager_env
        # systemd-run 254 and later expand ${…} in the command unless told not to; earlier
        # ones neither expand nor know the option
        [[ "$(systemd-run --help 2> /dev/null)" == *--expand-environment* ]] && MEMORY_CAP_EXPAND=(--expand-environment=no)
        # The cap must show in the scope's own cgroup: a manager that cannot hand out the
        # memory controller accepts MemoryMax and enforces nothing
        probe=$("${MEMORY_CAP_MANAGER_ENV[@]}" systemd-run --user --scope --quiet "${MEMORY_CAP_EXPAND[@]}" \
            -p MemoryMax="$MEMORY_CAP_BYTES" -p MemorySwapMax=0 -- \
            sh -c 'read -r max < "/sys/fs/cgroup$(cut -d: -f3- /proc/self/cgroup)/memory.max" && echo "$max"' 2> /dev/null < /dev/null)
        expected=$MEMORY_CAP_BYTES
        [ "$probe" = "$expected" ] && MEMORY_CAP_MODE=systemd
    fi
    if [ "$MEMORY_CAP_MODE" = none ] && type -P prlimit > /dev/null \
        && prlimit --as=$((MEMORY_CAP_BYTES * 4)) -- true 2> /dev/null; then
        MEMORY_CAP_MODE=prlimit
    fi
    case "$MEMORY_CAP_MODE" in
        systemd) [ -n "$quiet" ] || echo "memory cap: $MEMORY_CAP_LABEL per process, in a scope of the user's service manager (H2S_TEST_MEMORY_MAX; 0 for none)" ;;
        prlimit) [ -n "$quiet" ] || echo "memory cap: $MEMORY_CAP_LABEL per process, as an address-space limit of four times that (prlimit: the user's service manager cannot be reached; H2S_TEST_MEMORY_MAX, 0 for none)" ;;
        none) echo "warning: no memory cap: neither the user's service manager (systemd-run --user, with the memory controller) nor prlimit can be used here; a test that runs away can fill the machine's memory" >&2 ;;
    esac
}

memory_cap_wrap() {
    local tag=$1
    MEMORY_CAP_PREFIX=()
    MEMORY_CAP_UNIT=""
    case "${MEMORY_CAP_MODE:-none}" in
        systemd)
            MEMORY_CAP_SERIAL=$((MEMORY_CAP_SERIAL + 1))
            # Unique among this user's units: the tag, this bash's pid, a count, a random part
            MEMORY_CAP_UNIT="h2s-test-${tag//[^A-Za-z0-9_-]/_}-$$-$MEMORY_CAP_SERIAL-$RANDOM.scope"
            # The command gets back the runtime dir and bus it was given (or none), and not
            # the INVOCATION_ID systemd-run sets for the scope
            local -a restore=(env -u INVOCATION_ID)
            if [ -n "${XDG_RUNTIME_DIR+set}" ]; then restore+=("XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"); else restore+=(-u XDG_RUNTIME_DIR); fi
            if [ -n "${DBUS_SESSION_BUS_ADDRESS+set}" ]; then restore+=("DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS"); else restore+=(-u DBUS_SESSION_BUS_ADDRESS); fi
            MEMORY_CAP_PREFIX=("${MEMORY_CAP_MANAGER_ENV[@]}" systemd-run --user --scope --quiet "${MEMORY_CAP_EXPAND[@]}"
                "--unit=$MEMORY_CAP_UNIT" -p MemoryMax="$MEMORY_CAP_BYTES" -p MemorySwapMax=0 -p OOMPolicy=stop --
                "${restore[@]}")
            ;;
        prlimit)
            MEMORY_CAP_PREFIX=(prlimit --as=$((MEMORY_CAP_BYTES * 4)) --)
            ;;
    esac
}

memory_cap_hit() {
    local unit=$1 status=$2 log=${3:-} result
    [ "$status" != 0 ] || return 1
    case "${MEMORY_CAP_MODE:-none}" in
        systemd)
            [ -n "$unit" ] || return 1
            result=$("${MEMORY_CAP_MANAGER_ENV[@]}" systemctl --user show -p Result --value "$unit" 2> /dev/null)
            # A scope that failed stays listed until cleared; one that ended well is gone
            [ -z "$result" ] || [ "$result" = success ] \
                || "${MEMORY_CAP_MANAGER_ENV[@]}" systemctl --user reset-failed "$unit" > /dev/null 2>&1
            [ "$result" = oom-kill ]
            ;;
        prlimit)
            [ -n "$log" ] && grep -q -a -E "bad_alloc|[Oo]ut of memory|[Cc]annot allocate" "$log" 2> /dev/null
            ;;
        *) return 1 ;;
    esac
}

memory_cap_note() {
    if [ "${MEMORY_CAP_MODE:-none}" = prlimit ]; then
        echo "killed at the memory cap ($MEMORY_CAP_LABEL, an address-space limit of $((MEMORY_CAP_BYTES * 4 / 1048576))M)"
    else
        echo "killed at the memory cap ($MEMORY_CAP_LABEL)"
    fi
}
