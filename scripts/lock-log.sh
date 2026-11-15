#!/usr/bin/env bash
# What happened to the lock screen, for reading after a failed attempt: the lock-related
# lines of the h2s-shell instances' logs (the running one, and any that ended within the
# window — a crash, a restart), the supervisor's log, the lock marker, and the system
# journal's lines about PAM, fprintd, polkit and sleep. Read-only: it changes nothing,
# signals nothing, and prints nothing secret (the shell never logs typed text, nor its
# length; the journal lines are PAM's and the daemons' own).
#
#   scripts/lock-log.sh                 the last 30 minutes
#   scripts/lock-log.sh --minutes 90    a longer window
#   scripts/lock-log.sh --no-journal    without the system journal
#
# Works from a text console (Ctrl+Alt+F2, log in) while the screen is locked: it needs only
# XDG_RUNTIME_DIR (a login sets it) and Quickshell's `qs`, found on PATH or beside the
# running shell's binary. The shell's own log is Quickshell's (`qs log`), kept in
# $XDG_RUNTIME_DIR/quickshell/by-id/<instance>/log.qslog until the user's runtime dir goes
# (reboot, last logout); the supervisor's is $XDG_RUNTIME_DIR/h2s-shell-launcher.log.

set -u
minutes=30
journal=1
while [ $# -gt 0 ]; do
    case "$1" in
        --minutes) minutes=$2; shift 2 ;;
        --no-journal) journal=0; shift ;;
        -h | --help) sed -n '2,17p' "$0"; exit 0 ;;
        *) echo "lock-log.sh: unknown option $1 (see --help)" >&2; exit 2 ;;
    esac
done
[[ "$minutes" =~ ^[0-9]+$ ]] || { echo "lock-log.sh: --minutes takes a number" >&2; exit 2; }

runtime_dir=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
since=$(date -d "-$minutes min" '+%F %T')
# Quickshell's lines that matter beside the lock screen's own ([Lockscreen])
pattern='\[Lockscreen\]|Reloading configuration|Configuration Loaded|Failed to load configuration|Quickshell has been restarted|crashed|Launching config|session lock|Session lock|WlSessionLock|Exiting due to IPC'

# Quickshell's processes of this user: the running shells among them
own_quickshells() {
    local exe pid
    for exe in /proc/[0-9]*/exe; do
        pid=${exe#/proc/}
        pid=${pid%/exe}
        [ -O "/proc/$pid" ] || continue
        case "$(readlink "$exe" 2> /dev/null)" in *quickshell*) echo "$pid" ;; esac
    done
}

qs=$(command -v qs 2> /dev/null)
if [ -z "$qs" ]; then
    for pid in $(own_quickshells); do
        binary=$(readlink "/proc/$pid/exe" 2> /dev/null)
        if [ -x "$(dirname "$binary")/qs" ]; then qs=$(dirname "$binary")/qs; else qs=$binary; fi
        break
    done
fi

echo "== h2s-shell lock log, since $since ($minutes minutes), at $(date '+%F %T')"
echo

echo "== Processes"
echo "launchers (supervisors):"
pgrep -af 'scripts/launch\.sh' 2> /dev/null | sed 's/^/  /' || true
[ -n "$(pgrep -f 'scripts/launch\.sh' 2> /dev/null)" ] || echo "  none: no shell is supervised (a crash while locked leaves no prompt)"
echo "the supervisor lock (h2s-shell-launcher.lock) names pid: $(cat "$runtime_dir/h2s-shell-launcher.lock" 2> /dev/null || echo "(none)")"
echo "lock marker ($runtime_dir/h2s-shell-lock): $(head -n 1 "$runtime_dir/h2s-shell-lock" 2> /dev/null || echo "(none)")"
echo

if [ -z "$qs" ]; then
    echo "== Shell logs: Quickshell's qs not found (not on PATH, no Quickshell running): cannot read them"
else
    # Instances, alive and dead, of any h2s-shell copy (a folder with scripts/launch.sh)
    instances=$("$qs" list --all --show-dead --no-color 2> /dev/null | awk '
        /^Instance / { id = $2; sub(/:$/, "", id); dead = ($0 ~ /\(dead\)/) }
        /^ *Process ID:/ { pid = $3 }
        /^ *Config path:/ { config = $3 }
        /^ *Launch time:/ { print id "\t" pid "\t" dead "\t" $3 " " $4 "\t" config }')
    found=0
    while IFS=$'\t' read -r id pid dead launched config; do
        [ -n "$id" ] || continue
        [ -f "$(dirname "$config")/scripts/launch.sh" ] || continue
        file=$runtime_dir/quickshell/by-id/$id/log.qslog
        [ -f "$file" ] || continue
        # A dead instance only if it wrote within the window
        if [ "$dead" = 1 ] && [ -z "$(find "$file" -newermt "$since" 2> /dev/null)" ]; then
            continue
        fi
        found=1
        if [ "$dead" = 1 ]; then state="ended"; else state="RUNNING, pid $pid"; fi
        echo "== Shell instance $id ($state), started $launched, $config"
        if [ "$dead" != 1 ]; then
            echo "  parent: $(ps -o pid=,args= -p "$(awk '{ print $4 }' "/proc/$pid/stat" 2> /dev/null)" 2> /dev/null | sed 's/^ *//')"
            echo "  status: $("$qs" ipc --pid "$pid" call lockscreen status 2>&1 | head -n 1)"
        fi
        "$qs" log "$file" --log-times --no-color 2> /dev/null | awk -v since="$since" -v pattern="$pattern" '
            /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] / { keep = (substr($0, 1, 19) >= since) }
            keep && $0 ~ pattern { print "  " $0 }'
        echo
    done < <(sort -t $'\t' -k4 <<< "$instances")
    [ "$found" = 1 ] || echo "== Shell logs: no h2s-shell instance ran within the window (qs list --all --show-dead)"
fi
echo

echo "== Supervisor log ($runtime_dir/h2s-shell-launcher.log)"
cat "$runtime_dir/h2s-shell-launcher.log.old" "$runtime_dir/h2s-shell-launcher.log" 2> /dev/null \
    | awk -v since="$since" 'substr($0, 1, 19) >= since { print "  " $0 }'
echo

if [ "$journal" = 1 ]; then
    echo "== System journal (PAM, fprintd, polkit, logind, sleep)"
    journalctl -b --since "$since" --no-pager -o short-precise 2>&1 \
        | grep -aE 'unix_chkpwd|pam_unix|pam_fprintd|h2s-shell|fprintd|polkit|systemd-logind|systemd-sleep|PM: (suspend|hibernation)|insufficient permissions|No journal files' \
        | sed 's/^/  /'
    echo "  (nothing above, or 'insufficient permissions': run it again with sudo for the system's lines)"
fi
