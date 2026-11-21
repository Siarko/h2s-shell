#!/usr/bin/env bash
# After a deploy (notes/workflow.md, "Deploying"): a read-only check of the running shell
# against the real Tailscale daemon. It asks the shell, over its IPC, only two read calls —
# `modules list` and `tailscale state` — and reads the shell's log; it never calls a
# `tailscale` command, never an IPC call that changes anything (connect, refresh, a setting),
# and signals nothing.
#
#   tests/device/deploy-check.sh                       the shell started by `h2s-shell`
#   H2S_SHELL_DIR=<live checkout> tests/device/deploy-check.sh
#   tests/device/deploy-check.sh --repeats 5 --minutes 10
#
# What it checks:
#   modules    the module host answers, not in safe mode or test mode; the tailscale module
#              is loaded, enabled, and lists no errors (its warnings and deprecations noted)
#   tailscale  the module's state: not in test mode, the tailscale program found and
#              trusted, the daemon running and read (not stale), a backend state, no failed
#              action left, nothing under way; the counts of devices, exit nodes and
#              warnings are printed
#   log        no line of the running shell's log (Quickshell's, `qs log`) appears more than
#              --repeats times (default 5) in the last --minutes minutes (default 10),
#              timestamps aside: the same line again and again is a loop or a retry
#              without a backoff
#
# The IPC goes through `h2s-shell ipc call` (H2S_SHELL_DIR, when set, is passed on), or
# without an `h2s-shell` command through "$H2S_SHELL_DIR/scripts/launch.sh ipc call". The log
# read is that of the instance the IPC reaches: of the shell in H2S_SHELL_DIR, else of the
# packaged one beside the `h2s-shell` command (<prefix>/share/h2s-shell), the one Quickshell
# picks for `qs -p <that directory>` (`qs list -p`: same display; the oldest, as `qs ipc`
# takes) — never another copy's (a test bed's, a working tree's). Read with the `qs` on PATH
# or beside the running Quickshell. Needs bash, coreutils (timeout), awk and a python3, taken
# as the test runners take their tools (tests/lock/resolve.sh, need "python"): the pinned
# tests/lock/tools.nix build's where there is a `nix` command, else the one on PATH
# (H2S_TEST_TOOLS=nix or =system chooses).
#
# Exit status: 0 when every check passed, 1 when one failed, 2 when it could not be set up
# (no launcher, no qs, no python3, a wrong option).
set -uo pipefail

repeats=5
minutes=10
while [ $# -gt 0 ]; do
    case "$1" in
        --repeats) repeats=${2:-}; shift 2 || shift ;;
        --minutes) minutes=${2:-}; shift 2 || shift ;;
        -h | --help) sed -n '2,31p' "$0"; exit 0 ;;
        *) echo "deploy-check.sh: unknown option $1 (see --help)" >&2; exit 2 ;;
    esac
done
[[ "$repeats" =~ ^[0-9]+$ ]] || { echo "deploy-check.sh: --repeats takes a number" >&2; exit 2; }
[[ "$minutes" =~ ^[1-9][0-9]*$ ]] || { echo "deploy-check.sh: --minutes takes a number above 0" >&2; exit 2; }

command -v awk > /dev/null || { echo "deploy-check.sh: awk not found on PATH (it scans the log)" >&2; exit 2; }
# python3 (and timeout), from the runners' one source of tools
setup_error() { echo "deploy-check.sh: $*" >&2; exit 2; }
LOCKTEST_DIR=$(cd "$(dirname "$(readlink -f "$0")")/../lock" && pwd) || setup_error "cannot find tests/lock"
LOCKTEST_NEED=python
temp_base=${TMPDIR:-/tmp}
# shellcheck disable=SC2034  # read by resolve.sh
PROBE_TIMEOUT=5 probe=""
# shellcheck source=../lock/resolve.sh
source "$LOCKTEST_DIR/resolve.sh"

shell_dir=${H2S_SHELL_DIR:-}
if command -v h2s-shell > /dev/null; then
    launcher=(h2s-shell)
elif [ -n "$shell_dir" ] && [ -x "$shell_dir/scripts/launch.sh" ]; then
    launcher=("$shell_dir/scripts/launch.sh")
else
    echo "deploy-check.sh: no h2s-shell command on PATH and no H2S_SHELL_DIR with scripts/launch.sh: cannot reach the shell" >&2
    exit 2
fi

runtime_dir=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
qs=$(command -v qs 2> /dev/null)
if [ -z "$qs" ]; then
    for exe in /proc/[0-9]*/exe; do
        pid=${exe#/proc/}
        pid=${pid%/exe}
        [ -O "/proc/$pid" ] || continue
        binary=$(readlink "$exe" 2> /dev/null) || continue
        case "$binary" in *quickshell*) ;; *) continue ;; esac
        if [ -x "$(dirname "$binary")/qs" ]; then qs=$(dirname "$binary")/qs; else qs=$binary; fi
        break
    done
fi
[ -n "$qs" ] || { echo "deploy-check.sh: Quickshell's qs not found (not on PATH, no Quickshell running): cannot read the shell's log" >&2; exit 2; }

# The shell directory the IPC reaches: the launcher runs "${H2S_SHELL_DIR:-<its own>}/scripts/launch.sh",
# which talks to `qs -p <that directory>`
if [ -n "$shell_dir" ]; then
    reached_dir=$shell_dir
else
    reached_dir=$(dirname "$(readlink -f "$(command -v h2s-shell)")")/../share/h2s-shell
fi
if [ ! -f "$reached_dir/shell.qml" ]; then
    echo "deploy-check.sh: cannot tell which shell the IPC reaches (no $reached_dir/shell.qml): set H2S_SHELL_DIR to the shell's directory" >&2
    exit 2
fi
reached_dir=$(cd "$reached_dir" && pwd -P)

failures=0
pass() { echo "  PASS  $1"; }
fail() { echo "  FAIL  $1"; failures=$((failures + 1)); }

work=$(mktemp -d "${TMPDIR:-/tmp}/deploy-check.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT

# The only IPC calls this script makes: reads. Anything else is refused here, not sent.
ipc_read() {
    case "$1 $2" in
        "modules list" | "tailscale state") ;;
        *) echo "deploy-check.sh: refusing IPC call '$1 $2': not a read this check makes" >&2; return 2 ;;
    esac
    timeout 15 "${launcher[@]}" ipc call "$1" "$2" < /dev/null
}

echo "deploy-check: via ${launcher[*]}${shell_dir:+ (H2S_SHELL_DIR=$shell_dir)}; log lines more than $repeats times in $minutes minutes fail"

# ---- The module host and the module, the module's state ----------------------------------
ipc_read modules list > "$work/modules.json" 2> "$work/modules.err"
modules_status=$?
ipc_read tailscale state > "$work/state.json" 2> "$work/state.err"
state_status=$?

# Each line printed: "PASS|FAIL|NOTE|INFO<TAB>text". Texts from the shell are made printable
# and cut, never interpreted.
"$LOCKTEST_PYTHON" -I - "$work" "$modules_status" "$state_status" > "$work/verdicts" << 'EOF' \
    || { echo "deploy-check.sh: reading the IPC's answers failed" >&2; exit 2; }
import json, sys
work, modules_status, state_status = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])

def plain(value, limit=200):
    text = "".join(ch if ch.isprintable() else " " for ch in str(value))
    return text if len(text) <= limit else text[:limit] + "…"

def say(kind, text):
    print(kind + "\t" + text)

def read(name, status):
    raw = open(f"{work}/{name}.json", encoding="utf-8", errors="replace").read()
    err = open(f"{work}/{name}.err", encoding="utf-8", errors="replace").read().strip()
    if status != 0:
        return None, f"the call failed (status {status}): {plain(err or raw or 'no output')}"
    try:
        value = json.loads(raw)
    except ValueError:
        return None, f"not JSON: {plain(raw.strip() or err or 'no output')}"
    if not isinstance(value, dict):
        return None, f"not a JSON object: {plain(raw.strip())}"
    return value, ""

modules, problem = read("modules", modules_status)
if modules is None:
    say("FAIL", "modules: `modules list` " + problem)
else:
    trouble = []
    if modules.get("hostError"):
        trouble.append("host error: " + plain(modules["hostError"]))
    if modules.get("safeMode") is not False:
        trouble.append("safe mode" + (": " + plain(modules.get("safeModeReason")) if modules.get("safeModeReason") else ""))
    if modules.get("testMode") is not False:
        trouble.append("in test mode")
    if trouble:
        say("FAIL", "modules: the host: " + "; ".join(trouble))
    else:
        say("PASS", "modules: the host answers, not in safe mode or test mode")
    entries = [entry for entry in modules.get("modules") or [] if isinstance(entry, dict) and entry.get("id") == "tailscale"]
    if not entries:
        say("FAIL", "modules: no module \"tailscale\" listed")
    for entry in entries:
        trouble = []
        if entry.get("state") != "loaded":
            trouble.append("state " + plain(entry.get("state")))
        if entry.get("enabled") is not True:
            trouble.append("not enabled")
        for error in entry.get("errors") or []:
            trouble.append("error: " + plain(error))
        where = plain(entry.get("version", "")) + ", " + plain(entry.get("directory", ""))
        if trouble:
            say("FAIL", f"modules: tailscale ({where}): " + "; ".join(trouble))
        else:
            say("PASS", f"modules: tailscale loaded and enabled, no errors ({where})")
        for kind in ("warnings", "deprecations"):
            for line in entry.get(kind) or []:
                say("NOTE", f"modules: tailscale {kind[:-1]}: " + plain(line))

state, problem = read("state", state_status)
if state is None:
    say("FAIL", "tailscale: `tailscale state` " + problem)
else:
    trouble = []
    if state.get("testMode") is not False:
        trouble.append("the module is in test mode")
    if state.get("cli") != "present":
        trouble.append("the tailscale program: " + plain(state.get("cli")))
    if state.get("daemon") != "running":
        trouble.append("the daemon: " + plain(state.get("daemon")))
    if state.get("ready") is not True:
        trouble.append("the daemon's state not read yet")
    if state.get("stale") is not False:
        trouble.append("the last read timed out (stale)")
    if not state.get("backendState"):
        trouble.append("no backend state")
    if state.get("failure"):
        trouble.append("a failed action: " + plain(state["failure"]))
    if state.get("busy") is not False:
        trouble.append("an operation under way: " + plain(state.get("operation")))
    if trouble:
        say("FAIL", "tailscale: " + "; ".join(trouble))
    else:
        say("PASS", "tailscale: the daemon running and read, no failure, nothing under way")
    shown = lambda value: plain(value if isinstance(value, str) else json.dumps(value), 40)
    facts = ", ".join(f"{key} {shown(state.get(key))}" for key in
                      ("phase", "state", "backendState", "devices", "exitNodes", "warnings", "streamUp", "reads"))
    say("INFO", "tailscale: " + facts)
EOF
while IFS=$'\t' read -r kind text; do
    case "$kind" in
        PASS) pass "$text" ;;
        FAIL) fail "$text" ;;
        *) printf '  %-4s  %s\n' "$kind" "$text" ;;
    esac
done < "$work/verdicts"

# ---- The running shell's log ---------------------------------------------------------------
# The instance the IPC reached: of those Quickshell lists for that directory, the oldest
"$qs" list -p "$reached_dir" --no-color > "$work/instances" 2> /dev/null
logs=()
reached=$(awk '
    /^Instance / { id = $2; sub(/:$/, "", id) }
    /^ *Launch time:/ { print $3 " " $4 "\t" id }' "$work/instances" | sort | head -n 1 | cut -f2)
[ -n "$reached" ] && logs+=("$reached")
if [ "${#logs[@]}" = 0 ]; then
    fail "log: no running instance of $reached_dir (qs list -p)"
fi
since=$(date -d "-$minutes min" '+%F %T')
for id in "${logs[@]}"; do
    file=$runtime_dir/quickshell/by-id/$id/log.qslog
    if ! timeout 30 "$qs" log "$file" --log-times --no-color > "$work/log" 2> "$work/log.err"; then
        fail "log: instance $id: qs log could not read $file: $(head -c 200 "$work/log.err" | tr -c '[:print:]' ' ')"
        continue
    fi
    # Lines within the window, the timestamp taken off; continuation lines (no timestamp)
    # are left out. Printed: "<count><TAB><line>" for each line above the limit, most first.
    report=$(awk -v since="$since" -v limit="$repeats" '
        /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]/ {
            if (substr($0, 1, 19) < since) next
            read++
            text = $0
            sub(/^[0-9-]+ [0-9:.]+ +/, "", text)
            gsub(/[[:cntrl:]]/, " ", text)
            text = substr(text, 1, 300)
            count[text]++
        }
        END {
            print "read\t" read + 0
            for (text in count) if (count[text] > limit) print count[text] "\t" text
        }' "$work/log" | sort -t $'\t' -k1,1nr)
    read_count=$(grep -m1 '^read'$'\t' <<< "$report" | cut -f2)
    repeated=$(grep -v '^read'$'\t' <<< "$report")
    if [ -z "$repeated" ]; then
        pass "log: instance $id: no line more than $repeats times in the last $minutes minutes ($read_count lines)"
    else
        while IFS=$'\t' read -r count text; do
            fail "log: instance $id: ${count}× in the last $minutes minutes: $text"
        done <<< "$repeated"
    fi
done

if [ "$failures" = 0 ]; then
    echo "deploy-check: PASSED"
    exit 0
fi
echo "deploy-check: FAILED ($failures)"
exit 1
