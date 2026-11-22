# shellcheck shell=bash
# A memory cap on each process the test runners start, and a memory budget for a whole run,
# so that a runaway test (a mutant that loops appending to a list, a leak) is stopped instead
# of filling the machine's memory and having the kernel's OOM killer pick among the user's
# programs. Sourced by tests/headless.sh (every Quickshell and compositor of
# tests/run-unit.sh, tests/run-modules.sh, tests/run-helper.sh, and through them
# tests/mutate.sh and tests/soak.sh), by tests/run-all.sh and tests/mutate.sh (which make
# the run's budget for the runners they start), and by the lock test bed (tests/lock/run.sh
# says what is taken, tests/lock/lib.sh caps each process of the stack).
#
# The cap is H2S_TEST_MEMORY_MAX: a size in systemd's notation (1536M, 2G, bytes without a
# suffix), each process its own; 0 means none (no budget either); anything else that is not
# a size is warned about and the default taken. The default, 1536M, leaves room above the
# most a normal run's process was measured to take (its cgroup's peak, page cache and
# Wayland buffers included): a unit shard's Quickshell with many suites built about 0.9 GB,
# a lock-bed shell under its launcher about 0.45 GB, the nested Hyprland about 0.1 GB.
#
# The budget is H2S_TEST_MEMORY_BUDGET: what all the processes of one run may take together
# (the unit shards, the mutants, the lock bed's stacks, side by side). By default the memory
# available when the run starts less a reserve for the user's programs — 8 GB or a quarter
# of the machine's memory, whichever is larger —, and never less than one cap; 0 means none.
# The runner started first makes it and hands it on (H2S_TEST_SLICE, H2S_TEST_MEMORY_MODE in
# the environment), so the runners it starts share it; one started alone makes its own. How
# many shards or mutants run at once is then bounded by the budget over the cap
# (memory_cap_jobs).
#
# How, in order of preference:
#   systemd  each process in a transient scope of the user's service manager
#            (`systemd-run --user --scope`) with MemoryMax at the cap and no swap, the scopes
#            of a run in one transient slice with MemoryMax at the budget: the kernel stops
#            the largest process of a scope that reaches its cap, or of the slice when the
#            run reaches its budget, and the scope's result says so (oom-kill); the slice's
#            own count of limits reached (memory.events.local) tells the two apart. The
#            scope's process is the command itself (systemd-run execs it): pids, process
#            groups and parents are as they would be without the cap. The manager is reached
#            through the caller's XDG_RUNTIME_DIR (DBUS_SESSION_BUS_ADDRESS when set), kept
#            here at the start (H2S_TEST_USER_RUNTIME_DIR / H2S_TEST_USER_BUS when a runner
#            hands them over to an environment that has the test's private ones); the
#            command itself gets the environment it was given. Taken only when a probe scope
#            shows the cap in its cgroup's memory.max (the memory controller delegated), and,
#            in an SSH session, only when the manager outlives it: the user lingers
#            (loginctl), or has a local session besides — else the manager may stop when the
#            connection closes and take the run's scopes with it.
#   prlimit  no service manager to reach, or none that will last (CI, a container, a remote
#            run with nobody logged in): an address-space limit (RLIMIT_AS) of four times
#            the cap, and never under 8 GB. Address space is not memory: a Quickshell
#            reserves some 3 GB of it with under 1 GB resident, the nested Hyprland some
#            2.4 GB with 0.05 GB (allocator arenas, GPU reservations), so a low cap kills
#            normal runs in this mode, and the floor keeps the default one clear of them
#            (H2S_TEST_MEMORY_AS_FLOOR sets another floor: the self-tests' small caps).
#            An allocation past it fails and the process ends (an abort, an error status).
#            No budget: shards and mutants at once are bounded by the memory available over
#            the cap.
#   none     neither works: a warning says so, and the processes run without a cap.
#
#   memory_cap_init [quiet]       chooses the way, once per process (MEMORY_CAP_MODE: systemd,
#                                 prlimit, none; MEMORY_CAP_LABEL: the cap), makes or joins the
#                                 run's budget, says it on stdout unless quiet (a warning on
#                                 stderr when no way works); exports what the runners it
#                                 starts take over
#   memory_cap_finish             the run's budget ended, when this process made it (the
#                                 runners' EXIT traps)
#   memory_cap_jobs <kB a job>    how many shards or mutants memory allows at once (at least 1)
#   memory_cap_wrap <tag>         MEMORY_CAP_PREFIX: the words to put before a command to run
#                                 it under the cap (empty without one); MEMORY_CAP_UNIT: the
#                                 scope's name (systemd), made of <tag> and a unique part
#   memory_cap_hit <unit> <status> [<log>]
#                                 after the command ended with <status>: true when it was
#                                 stopped at the cap or the budget — the scope's result
#                                 (systemd; a scope that failed is cleared from the manager
#                                 whatever its result), or an allocation failure in <log>
#                                 (prlimit); MEMORY_CAP_HIT says which: cap or budget
#   memory_cap_note               the words a runner puts after what was killed: "killed at
#                                 the memory cap (<cap>)", "killed at the run's memory budget
#                                 (<budget> …)"
#   memory_cap_start_failed <log> the line of systemd-run's that says it could not start the
#                                 scope (a bus that timed out under load), or false

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

# A size in bytes as a short label (29G, 400M)
memory_cap_label() {
    local bytes=$1
    if [ $((bytes % (1024 * 1024 * 1024))) = 0 ] || [ "$bytes" -ge $((10 * 1024 * 1024 * 1024)) ]; then
        echo "$((bytes / 1024 / 1024 / 1024))G"
    else
        echo "$((bytes / 1024 / 1024))M"
    fi
}

memory_cap_meminfo() { awk -v key="$1:" '$1 == key { print $2 * 1024 }' /proc/meminfo 2> /dev/null; }

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
memory_cap_systemctl() { "${MEMORY_CAP_MANAGER_ENV[@]}" systemctl --user "$@"; }

# Whether the user's service manager outlives this session: outside SSH it is the session's
# own; in SSH only when the user lingers or has a local session besides this one
memory_cap_manager_lasts() {
    local uid sessions session
    [ -z "${SSH_CONNECTION:-}${SSH_TTY:-}${SSH_CLIENT:-}" ] && return 0
    type -P loginctl > /dev/null || return 1
    uid=$(id -u)
    [ "$(loginctl show-user "$uid" -p Linger --value 2> /dev/null)" = yes ] && return 0
    sessions=$(loginctl show-user "$uid" -p Sessions --value 2> /dev/null)
    for session in $sessions; do
        [ "$session" = "${XDG_SESSION_ID:-}" ] && continue
        [ "$(loginctl show-session "$session" -p Remote --value 2> /dev/null)" = no ] || continue
        case "$(loginctl show-session "$session" -p State --value 2> /dev/null)" in
            active | online) return 0 ;;
        esac
    done
    return 1
}

# The slice of a run whose runner has ended without stopping it (killed): stopped, so that
# they do not pile up. Its runner's pid is in its name
memory_cap_stop_stale_slices() {
    local slice pid
    for slice in $(memory_cap_systemctl list-units --plain --no-legend --all 'h2s_test_*.slice' 2> /dev/null | awk '{ print $1 }'); do
        pid=${slice#h2s_test_}
        pid=${pid%%_*}
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        kill -0 "$pid" 2> /dev/null && continue
        memory_cap_systemctl stop "$slice" > /dev/null 2>&1
    done
}

# memory_cap_make_slice <budget bytes>: MEMORY_CAP_SLICE, a transient slice with that MemoryMax
memory_cap_make_slice() {
    local slice="h2s_test_$$_$RANDOM.slice"
    type -P busctl > /dev/null || return 1
    memory_cap_stop_stale_slices
    "${MEMORY_CAP_MANAGER_ENV[@]}" busctl --user call org.freedesktop.systemd1 /org/freedesktop/systemd1 \
        org.freedesktop.systemd1.Manager StartTransientUnit 'ssa(sv)a(sa(sv))' "$slice" fail \
        2 MemoryMax t "$1" MemorySwapMax t 0 0 > /dev/null 2>&1 || return 1
    [ "$(memory_cap_systemctl show -p ActiveState --value "$slice" 2> /dev/null)" = active ] \
        || { memory_cap_systemctl stop "$slice" > /dev/null 2>&1; return 1; }
    MEMORY_CAP_SLICE=$slice
    MEMORY_CAP_OWNER=1
}

memory_cap_slice_ooms() {
    local key value
    [ -n "${MEMORY_CAP_SLICE_EVENTS:-}" ] || { echo 0; return; }
    while read -r key value; do
        [ "$key" = oom ] && { echo "$value"; return; }
    done < "$MEMORY_CAP_SLICE_EVENTS" 2> /dev/null
    echo 0
}

memory_cap_init() {
    local quiet=${1:-} probe value default_budget reserve
    [ -z "${MEMORY_CAP_READY:-}" ] || return 0
    MEMORY_CAP_READY=1
    MEMORY_CAP_MODE=none MEMORY_CAP_BYTES="" MEMORY_CAP_SERIAL=0 MEMORY_CAP_EXPAND=()
    MEMORY_CAP_SLICE="" MEMORY_CAP_OWNER="" MEMORY_CAP_SLICE_EVENTS="" MEMORY_CAP_HIT=""
    MEMORY_CAP_BUDGET_LABEL="" MEMORY_CAP_BUDGET_BYTES=""
    declare -gA MEMORY_CAP_BASE=()
    if [ -n "${H2S_TEST_USER_RUNTIME_DIR:-}" ]; then
        MEMORY_CAP_USER_RUNTIME_DIR=$H2S_TEST_USER_RUNTIME_DIR MEMORY_CAP_USER_BUS=${H2S_TEST_USER_BUS:-}
    else
        MEMORY_CAP_USER_RUNTIME_DIR=${XDG_RUNTIME_DIR:-} MEMORY_CAP_USER_BUS=${DBUS_SESSION_BUS_ADDRESS:-}
    fi
    memory_cap_manager_env
    [[ "$(systemd-run --help 2> /dev/null)" == *--expand-environment* ]] && MEMORY_CAP_EXPAND=(--expand-environment=no)

    MEMORY_CAP_LABEL=${H2S_TEST_MEMORY_MAX:-1536M}
    if [ "$MEMORY_CAP_LABEL" = 0 ]; then
        [ -n "$quiet" ] || echo "memory cap: none (H2S_TEST_MEMORY_MAX=0)"
        export H2S_TEST_MEMORY_MAX=0 H2S_TEST_MEMORY_MODE=none
        return 0
    fi
    MEMORY_CAP_BYTES=$(memory_cap_bytes "$MEMORY_CAP_LABEL") && [ "$MEMORY_CAP_BYTES" -gt 0 ] || {
        echo "warning: H2S_TEST_MEMORY_MAX is '$MEMORY_CAP_LABEL', not a size (1536M, 2G; 0 for none): the default 1536M is taken" >&2
        MEMORY_CAP_LABEL=1536M MEMORY_CAP_BYTES=$(memory_cap_bytes 1536M)
    }

    # A runner started by another: the way and the budget it chose, the budget's slice still
    # there (one left over from a run that has ended is not joined)
    case "${H2S_TEST_MEMORY_MODE:-}" in
        systemd)
            if [ -z "${H2S_TEST_SLICE:-}" ] \
                || [ "$(memory_cap_systemctl show -p ActiveState --value "$H2S_TEST_SLICE" 2> /dev/null)" = active ]; then
                MEMORY_CAP_MODE=systemd MEMORY_CAP_SLICE=${H2S_TEST_SLICE:-}
                MEMORY_CAP_BUDGET_LABEL=${H2S_TEST_MEMORY_BUDGET:-}
                [ "$MEMORY_CAP_BUDGET_LABEL" != 0 ] || MEMORY_CAP_BUDGET_LABEL=""
            fi
            ;;
        prlimit | none) MEMORY_CAP_MODE=$H2S_TEST_MEMORY_MODE ;;
    esac

    if [ -z "${H2S_TEST_MEMORY_MODE:-}" ] || { [ "$H2S_TEST_MEMORY_MODE" = systemd ] && [ "$MEMORY_CAP_MODE" = none ]; }; then
        # The budget: given, else the memory available less the reserve, at least one cap
        value=${H2S_TEST_MEMORY_BUDGET:-}
        if [ "$value" != 0 ]; then
            if [ -n "$value" ] && MEMORY_CAP_BUDGET_BYTES=$(memory_cap_bytes "$value") && [ "$MEMORY_CAP_BUDGET_BYTES" -gt 0 ]; then
                :
            else
                [ -z "$value" ] || echo "warning: H2S_TEST_MEMORY_BUDGET is '$value', not a size (24G; 0 for none): the default is taken" >&2
                reserve=$(( $(memory_cap_meminfo MemTotal) / 4 ))
                [ "$reserve" -ge $((8 * 1024 * 1024 * 1024)) ] || reserve=$((8 * 1024 * 1024 * 1024))
                default_budget=$(( $(memory_cap_meminfo MemAvailable) - reserve ))
                [ "$default_budget" -ge "$MEMORY_CAP_BYTES" ] || default_budget=$MEMORY_CAP_BYTES
                MEMORY_CAP_BUDGET_BYTES=$default_budget
            fi
            MEMORY_CAP_BUDGET_LABEL=$(memory_cap_label "$MEMORY_CAP_BUDGET_BYTES")
        fi
        if [ -n "$MEMORY_CAP_USER_RUNTIME_DIR" ] && type -P systemd-run > /dev/null && type -P systemctl > /dev/null \
            && memory_cap_manager_lasts; then
            [ -z "$MEMORY_CAP_BUDGET_BYTES" ] || memory_cap_make_slice "$MEMORY_CAP_BUDGET_BYTES" \
                || { echo "warning: the run's memory budget could not be made (busctl, a transient slice): each process keeps its cap, the run has no budget" >&2; MEMORY_CAP_BUDGET_LABEL=""; }
            # The cap must show in the scope's own cgroup: a manager that cannot hand out the
            # memory controller accepts MemoryMax and enforces nothing
            probe=$("${MEMORY_CAP_MANAGER_ENV[@]}" systemd-run --user --scope --quiet "${MEMORY_CAP_EXPAND[@]}" \
                ${MEMORY_CAP_SLICE:+"--slice=$MEMORY_CAP_SLICE"} -p MemoryMax="$MEMORY_CAP_BYTES" -p MemorySwapMax=0 \
                -p OOMPolicy=stop -- \
                sh -c 'read -r max < "/sys/fs/cgroup$(cut -d: -f3- /proc/self/cgroup)/memory.max" && echo "$max"' 2> /dev/null < /dev/null)
            if [ "$probe" = "$MEMORY_CAP_BYTES" ]; then
                MEMORY_CAP_MODE=systemd
            else
                memory_cap_finish
                MEMORY_CAP_SLICE="" MEMORY_CAP_BUDGET_LABEL=""
            fi
        fi
        if [ "$MEMORY_CAP_MODE" = none ] && type -P prlimit > /dev/null \
            && prlimit --as="$(memory_cap_address_space)" -- true 2> /dev/null; then
            MEMORY_CAP_MODE=prlimit MEMORY_CAP_BUDGET_LABEL=""
        fi
    fi
    if [ -n "$MEMORY_CAP_SLICE" ]; then
        value=$(memory_cap_systemctl show -p ControlGroup --value "$MEMORY_CAP_SLICE" 2> /dev/null)
        [ -z "$value" ] || MEMORY_CAP_SLICE_EVENTS=/sys/fs/cgroup$value/memory.events.local
    fi
    export H2S_TEST_MEMORY_MAX=$MEMORY_CAP_LABEL H2S_TEST_MEMORY_MODE=$MEMORY_CAP_MODE \
        H2S_TEST_SLICE=$MEMORY_CAP_SLICE H2S_TEST_MEMORY_BUDGET=${MEMORY_CAP_BUDGET_LABEL:-0} \
        H2S_TEST_USER_RUNTIME_DIR=$MEMORY_CAP_USER_RUNTIME_DIR H2S_TEST_USER_BUS=$MEMORY_CAP_USER_BUS
    case "$MEMORY_CAP_MODE" in
        systemd) [ -n "$quiet" ] || echo "memory cap: $MEMORY_CAP_LABEL per process, ${MEMORY_CAP_BUDGET_LABEL:-no budget} for the whole run, in scopes of the user's service manager (H2S_TEST_MEMORY_MAX, H2S_TEST_MEMORY_BUDGET; 0 for none)" ;;
        prlimit) [ -n "$quiet" ] || echo "memory cap: $MEMORY_CAP_LABEL per process, as an address-space limit of $(memory_cap_label "$(memory_cap_address_space)"), no budget for the whole run (prlimit: the user's service manager cannot be reached, or may stop before the run ends; H2S_TEST_MEMORY_MAX, 0 for none)" ;;
        none) echo "warning: no memory cap: neither the user's service manager (systemd-run --user, with the memory controller) nor prlimit can be used here; a test that runs away can fill the machine's memory" >&2 ;;
    esac
}

memory_cap_address_space() {
    local limit=$((MEMORY_CAP_BYTES * 4)) floor
    floor=$(memory_cap_bytes "${H2S_TEST_MEMORY_AS_FLOOR:-8G}") || floor=$((8 * 1024 * 1024 * 1024))
    [ "$limit" -ge "$floor" ] || limit=$floor
    echo "$limit"
}

memory_cap_finish() {
    [ -n "${MEMORY_CAP_OWNER:-}" ] && [ -n "${MEMORY_CAP_SLICE:-}" ] || return 0
    memory_cap_systemctl stop "$MEMORY_CAP_SLICE" > /dev/null 2>&1
    MEMORY_CAP_OWNER=""
}

memory_cap_jobs() {
    local per_job_bytes=$(($1 * 1024)) jobs available
    if [ "${MEMORY_CAP_MODE:-none}" = systemd ] && [ -n "${MEMORY_CAP_BUDGET_LABEL:-}" ] \
        && [ "$MEMORY_CAP_BUDGET_LABEL" != 0 ]; then
        jobs=$(( $(memory_cap_bytes "$MEMORY_CAP_BUDGET_LABEL") / MEMORY_CAP_BYTES ))
    else
        available=$(memory_cap_meminfo MemAvailable)
        [[ "$available" =~ ^[0-9]+$ ]] || { echo 16; return; }
        [ -z "${MEMORY_CAP_BYTES:-}" ] || per_job_bytes=$MEMORY_CAP_BYTES
        jobs=$((available / per_job_bytes))
    fi
    [ "$jobs" -ge 1 ] || jobs=1
    echo "$jobs"
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
            MEMORY_CAP_BASE[$MEMORY_CAP_UNIT]=$(memory_cap_slice_ooms)
            # The command gets back the runtime dir and bus it was given (or none), and not
            # the INVOCATION_ID systemd-run sets for the scope
            local -a restore=(env -u INVOCATION_ID)
            if [ -n "${XDG_RUNTIME_DIR+set}" ]; then restore+=("XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"); else restore+=(-u XDG_RUNTIME_DIR); fi
            if [ -n "${DBUS_SESSION_BUS_ADDRESS+set}" ]; then restore+=("DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS"); else restore+=(-u DBUS_SESSION_BUS_ADDRESS); fi
            MEMORY_CAP_PREFIX=("${MEMORY_CAP_MANAGER_ENV[@]}" systemd-run --user --scope --quiet "${MEMORY_CAP_EXPAND[@]}"
                "--unit=$MEMORY_CAP_UNIT" ${MEMORY_CAP_SLICE:+"--slice=$MEMORY_CAP_SLICE"}
                -p MemoryMax="$MEMORY_CAP_BYTES" -p MemorySwapMax=0 -p OOMPolicy=stop --
                "${restore[@]}")
            ;;
        prlimit)
            MEMORY_CAP_PREFIX=(prlimit "--as=$(memory_cap_address_space)" --)
            ;;
    esac
}

memory_cap_hit() {
    local unit=$1 status=$2 log=${3:-} result state
    MEMORY_CAP_HIT=""
    [ "$status" != 0 ] || return 1
    case "${MEMORY_CAP_MODE:-none}" in
        systemd)
            [ -n "$unit" ] || return 1
            # The scope's end is the manager's to record: it may still be stopping the rest
            # of the scope when the command's status is known
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                state=$(memory_cap_systemctl show -p ActiveState --value "$unit" 2> /dev/null)
                case "$state" in active | activating | deactivating) sleep 0.1 ;; *) break ;; esac
            done
            result=$(memory_cap_systemctl show -p Result --value "$unit" 2> /dev/null)
            # A scope that failed stays listed until cleared; one that ended well is gone
            [ "$state" != failed ] || memory_cap_systemctl reset-failed "$unit" > /dev/null 2>&1
            [ "$result" = oom-kill ] || return 1
            MEMORY_CAP_HIT=cap
            [ "$(memory_cap_slice_ooms)" -gt "${MEMORY_CAP_BASE[$unit]:-0}" ] && MEMORY_CAP_HIT=budget
            return 0
            ;;
        prlimit)
            [ -n "$log" ] && grep -q -a -E "bad_alloc|[Oo]ut of memory|[Cc]annot allocate" "$log" 2> /dev/null \
                && MEMORY_CAP_HIT=cap
            ;;
        *) return 1 ;;
    esac
}

memory_cap_note() {
    if [ "${MEMORY_CAP_HIT:-}" = budget ]; then
        echo "killed at the run's memory budget ($MEMORY_CAP_BUDGET_LABEL, all its processes together)"
    elif [ "${MEMORY_CAP_MODE:-none}" = prlimit ]; then
        echo "killed at the memory cap ($MEMORY_CAP_LABEL, an address-space limit of $(memory_cap_label "$(memory_cap_address_space)"))"
    else
        echo "killed at the memory cap ($MEMORY_CAP_LABEL)"
    fi
}

memory_cap_start_failed() {
    [ "${MEMORY_CAP_MODE:-none}" = systemd ] && [ -r "${1:-}" ] || return 1
    grep -a -m 1 -E '^Failed to (start transient scope unit|connect to )' "$1" 2> /dev/null
}
