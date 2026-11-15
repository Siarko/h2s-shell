#!/usr/bin/env bash
# Starts the shell with the icon theme from its settings, and keeps it running.
#
# Quickshell sets the icon theme once, at launch, from QS_ICON_THEME — nothing changes it
# while the shell runs. So the shell is started through here (Hyprland's autostart calls
# this script), and the settings' "Restart to apply" runs `launch.sh --restart`.
#
# The shell is supervised: this script stays, as its parent, and starts it again when it
# dies (a crash, a kill, the OOM killer) — above all a shell that dies while the screen is
# locked: the compositor keeps the session locked, and only a new shell can show a prompt
# again (it finds the lock marker and locks at once; docs/plans/lockscreen.md, section 7,
# "Restart"). See supervise() for what counts as stopping on purpose. One supervisor per
# session: it holds $XDG_RUNTIME_DIR/h2s-shell-launcher.lock (flock), and a second launcher
# waits a little for it to end, then gives up. What it does is logged, timestamped, to
# $XDG_RUNTIME_DIR/h2s-shell-launcher.log (scripts/lock-log.sh prints it).
#
#   launch.sh            start the shell, supervised (extra arguments go to qs; with -d,
#                        Quickshell's own daemon mode, the shell is not supervised: its
#                        starter exits at once. --restart is the detached, supervised start)
#   launch.sh --restart  stop the running shell (and its supervisor) and start it again,
#                        detached (supervised)
#   launch.sh ipc ARGS   `qs ipc ARGS` to this shell, e.g. `ipc call tablet set true`; a
#                        call made while the shell reloads or restarts is tried again for
#                        up to 3 s, and fails (status 1) if never taken
#   launch.sh --lock-log [--minutes N] [--no-journal]
#                        what happened to the lock screen (scripts/lock-log.sh)
#   launch.sh --list     the installed icon themes, one per line
#   launch.sh --resolve  the icon theme the shell would start with
#   launch.sh --preview THEME
#                        sample icons of a theme, "name<TAB>file" per line — the settings
#                        show them, as the running shell can only load its own theme's
#
# The setting is `appearance.iconTheme`, a global one: in the config's "globals". Empty
# or missing is "Automatic": the system's theme (gsettings) if it is installed, else the
# first theme found. Themes are looked for where the icon theme spec says: ~/.icons,
# $XDG_DATA_HOME/icons, then each $XDG_DATA_DIRS/icons. Not hicolor (every theme's
# fallback, not a look of its own) and not themes without icon directories (cursor
# themes, such as "default").

config="${XDG_CONFIG_HOME:-$HOME/.config}/h2s_shell/config.json"

# The shell's folder, wherever it is: a git checkout in ~/.config/quickshell/default, or
# a package's copy (the Nix flake installs it read-only into the store). The instance is
# addressed by this path rather than by Quickshell's config name, so every copy works.
shell_dir=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

icon_dirs() {
    echo "$HOME/.icons"
    echo "${XDG_DATA_HOME:-$HOME/.local/share}/icons"
    local IFS=:
    for dir in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do
        echo "$dir/icons"
    done
}

list_themes() {
    local seen=" "
    while read -r base; do
        [ -d "$base" ] || continue
        for index in "$base"/*/index.theme; do
            [ -f "$index" ] || continue
            local name
            name=$(basename "$(dirname "$index")")
            [ "$name" = "hicolor" ] && continue
            case "$seen" in *" $name "*) continue ;; esac
            grep -q '^Directories=.' "$index" || continue
            seen="$seen$name "
            echo "$name"
        done
    done < <(icon_dirs)
}

# The icons a preview shows: places, status, actions — kinds every full theme draws
preview_icons="folder user-home text-x-generic audio-volume-high network-wireless battery-good dialog-warning dialog-information edit-delete document-save preferences-system web-browser"

# A theme and the ones it inherits, breadth first, hicolor last
theme_chain() {
    local queue="$1" chain=" "
    while [ -n "$queue" ]; do
        local theme="${queue%% *}"
        queue="${queue#"$theme"}"; queue="${queue# }"
        case "$chain" in *" $theme "*) continue ;; esac
        [ "$theme" = "hicolor" ] && continue
        chain="$chain$theme "
        while read -r base; do
            local index="$base/$theme/index.theme"
            if [ -f "$index" ]; then
                local inherits
                inherits=$(sed -n 's/^Inherits=//p' "$index" | head -n 1 | tr ',' ' ')
                queue="$queue $inherits"
                queue="${queue# }"
                break
            fi
        done < <(icon_dirs)
    done
    echo "$chain hicolor"
}

# For each preview icon, the file of the first theme in the chain that has it: scalable
# if there is one, else the size nearest 48 (larger first)
preview_theme() {
    local found=" "
    for theme in $(theme_chain "$1"); do
        local patterns=()
        for icon in $preview_icons; do
            case "$found" in *" $icon "*) continue ;; esac
            patterns+=(-o -name "$icon.svg" -o -name "$icon.png")
        done
        [ ${#patterns[@]} -eq 0 ] && break
        local dirs=()
        while read -r base; do
            [ -d "$base/$theme" ] && dirs+=("$base/$theme")
        done < <(icon_dirs)
        [ ${#dirs[@]} -eq 0 ] && continue
        local picked
        picked=$(find "${dirs[@]}" \( "${patterns[@]:1}" \) 2> /dev/null | awk '
            {
                file = $0; name = file; sub(/.*\//, "", name); sub(/\.(svg|png)$/, "", name)
                if (file ~ /scalable/) score = 0
                else if (match(file, /\/[0-9]+(x[0-9]+)?(@[0-9]x)?\//)) {
                    size = substr(file, RSTART + 1, RLENGTH - 2) + 0
                    score = size >= 48 ? size - 48 + 1 : 1000 + 48 - size
                } else score = 5000
                if (!(name in best) || score < best[name]) { best[name] = score; path[name] = file }
            }
            END { for (name in path) print name "\t" path[name] }')
        while IFS=$'\t' read -r icon file; do
            [ -n "$icon" ] || continue
            found="$found$icon "
            printf '%s\t%s\n' "$icon" "$file"
        done <<< "$picked"
    done
}

resolve_theme() {
    local wanted=""
    if command -v jq > /dev/null && [ -r "$config" ]; then
        # Config keeps "globals" as JSON text inside the file (a string property)
        wanted=$(jq -r '.globals // "{}" | (if type == "string" then fromjson else . end)
            | .["appearance.iconTheme"] // "" | strings' "$config" 2> /dev/null)
    fi
    local installed
    installed=$(list_themes)
    if [ -n "$wanted" ] && grep -qxF "$wanted" <<< "$installed"; then
        echo "$wanted"
        return
    fi
    local system=""
    command -v gsettings > /dev/null \
        && system=$(gsettings get org.gnome.desktop.interface icon-theme 2> /dev/null | tr -d "'")
    if [ -n "$system" ] && grep -qxF "$system" <<< "$installed"; then
        echo "$system"
        return
    fi
    head -n 1 <<< "$installed"
}

# The running shell's process ids — every copy of it, not only this folder's: the
# package's and a checkout's (H2S_SHELL_DIR) are both h2s-shell, and restarting one with
# the other running left two shells. A copy is told by scripts/launch.sh beside its
# shell.qml.
shell_pids() {
    qs list --all 2> /dev/null | awk '
        /^ *Process ID:/ { pid = $3 }
        /^ *Config path:/ { print pid "\t" $3 }' \
    | while IFS=$'\t' read -r pid config; do
        [ -f "$(dirname "$config")/scripts/launch.sh" ] && echo "$pid"
    done
}

# The supervisor of a shell process (supervise() below), if it has one: the parent named in
# its environment, and only if that really is its parent and runs this script
supervisor_of() {
    local pid=$1 supervisor parent
    supervisor=$({ tr '\0' '\n' < "/proc/$pid/environ"; } 2> /dev/null | sed -n 's/^H2S_SHELL_SUPERVISOR=//p')
    [[ "$supervisor" =~ ^[0-9]+$ ]] || return 1
    parent=$(process_parent "$pid") || return 1
    [ "$parent" = "$supervisor" ] || return 1
    tr '\0' ' ' < "/proc/$supervisor/cmdline" 2> /dev/null | grep -q 'scripts/launch\.sh' || return 1
    echo "$supervisor"
}

# A process's parent, from /proc (the command name may hold spaces and parentheses: the
# fields are read after the last ")")
process_parent() {
    local stat=""
    { IFS= read -r -d '' stat < "/proc/$1/stat"; } 2> /dev/null
    [ -n "$stat" ] || return 1
    stat=${stat##*) }
    set -- $stat
    echo "$2"
}

runtime_dir=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
# What the launcher says, one timestamped line per event, also when nobody reads its
# stderr (Hyprland's autostart): `scripts/lock-log.sh` prints it with the shell's log
launcher_log=$runtime_dir/h2s-shell-launcher.log
# One supervisor per session: the one running holds this lock and writes its pid in it
lock_file=$runtime_dir/h2s-shell-launcher.lock

say() {
    local line
    line="$(date '+%F %T.%3N') h2s-shell launcher[$$]: $*"
    echo "$line" >&2
    [ /dev/stderr -ef "$launcher_log" ] || echo "$line" >> "$launcher_log" 2> /dev/null
}

# The supervisor holding the lock, if any: the pid in the lock file, and only if that
# process runs this script, is the user's, and the lock is really held
recorded_supervisor() {
    local pid=""
    [ -f "$lock_file" ] && read -r pid < "$lock_file" 2> /dev/null
    [[ "$pid" =~ ^[0-9]+$ ]] && [ "$pid" != $$ ] && [ -O "/proc/$pid" ] || return 1
    tr '\0' ' ' < "/proc/$pid/cmdline" 2> /dev/null | grep -q 'scripts/launch\.sh' || return 1
    if command -v flock > /dev/null; then
        # Taken by nobody: the pid is a leftover (a supervisor killed with SIGKILL)
        flock -n -s "$lock_file" true 2> /dev/null && return 1
    fi
    echo "$pid"
}

# Asks the running shell to quit; one that does not answer (a hung instance cannot take
# the request over its socket) is terminated, then killed. The settings window is closed
# first: Quickshell tearing it down with a text field focused crashed it on the way out
# (QInputMethod::commit on the dying window), and the crash report popped up. The
# supervisor is told first to let the shell go (SIGUSR1), or it would start it again — the
# one holding the lock whether or not a shell is alive (it may be in its pause before a
# restart: told nothing, it would start a second shell beside the new one), and the
# supervisor of each shell found.
stop_shell() {
    local pids supervisor
    supervisor=$(recorded_supervisor) && kill -USR1 "$supervisor" 2> /dev/null
    pids=$(shell_pids)
    [ -n "$pids" ] || return
    for pid in $pids; do
        supervisor=$(supervisor_of "$pid") && kill -USR1 "$supervisor" 2> /dev/null
    done
    for pid in $pids; do
        qs ipc --pid "$pid" call settings close > /dev/null 2>&1
    done
    for pid in $pids; do
        qs kill --pid "$pid" > /dev/null 2>&1
    done
    for signal in "" TERM KILL; do
        [ -n "$signal" ] && kill -s "$signal" $pids 2> /dev/null
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            local alive=""
            for pid in $pids; do
                kill -0 "$pid" 2> /dev/null && alive="$alive $pid"
            done
            [ -z "$alive" ] && return
            sleep 0.2
        done
        pids=$alive
    done
}

# The modules the shell loads (docs/plans/modules.md). Input and output are two variables:
#   H2S_SHELL_MODULE_PATH   input, the developer's: colon-separated, each a module directory or
#                           a directory of modules (checkouts being worked on). Read, never
#                           written here.
#   H2S_SHELL_MODULES       output, the shell's: colon-separated canonical paths of directories
#                           holding a module.json (symlinks resolved: one directory reached by
#                           two spellings would load its singletons twice), each once, in search
#                           order — the shell takes the first module of an id and reports the
#                           others. Exported for the shell at every start; never read here: the
#                           shell and all it starts inherit it, and a --restart run from there
#                           must not take an old list (an updated module's old path, a removed
#                           module) for a developer's entries.
#   H2S_SHELL_MODULE_DATA_DIRS
#                           the data directories searched instead of $XDG_DATA_DIRS (which the
#                           shell needs as it is: icons, fonts, mime data); set and empty: none.
#                           The lock test bed points it away from the caller's system.
# Search order: 1. H2S_SHELL_MODULE_PATH's entries, 2. $XDG_DATA_HOME/h2s-shell/modules/*
# (~/.local/share), 3. each data dir's h2s-shell/modules/*. Worked out before every start of
# the shell (a module installed since is picked up by the next one), in a process of its own
# under a hard bound ($discovery_seconds s): a hung mount under a data dir must not keep the
# shell — perhaps a locked session's only prompt — from starting. Late or failed: no modules,
# logged. At most $max_modules modules and $max_modules_length bytes (a longer environment
# string fails the shell's execve with E2BIG: no shell at all); the rest is dropped, logged.
# H2S_SHELL_SAFE_MODE is the supervisor's, set per start (supervise): never inherited.
launcher_script=$(readlink -f "$0")
discovery_seconds=3
max_modules=200
max_modules_length=65536
module_roots() {
    echo "${XDG_DATA_HOME:-$HOME/.local/share}/h2s-shell/modules"
    local IFS=:
    for dir in ${H2S_SHELL_MODULE_DATA_DIRS-${XDG_DATA_DIRS:-/usr/local/share:/usr/share}}; do
        [ -n "$dir" ] && echo "$dir/h2s-shell/modules"
    done
}
# The search itself, run as `launch.sh --discover-modules` (by discover_modules): the list on
# standard output. It forks nothing per entry: module.json is looked for first, and the
# canonical path is the working directory after a `cd -P`, in this throwaway process.
find_modules() {
    local given=() candidates=() result=() entry dir path root seen=":" length=0 dropped=0
    # Test seam (H2S_LAUNCHER_TEST_TIMINGS "discoveryhang=S"): a search that takes S seconds,
    # as one stuck on a hung mount would
    [ -z "$discovery_hang_ms" ] || sleep "$(ms_to_seconds "$discovery_hang_ms")"
    IFS=: read -r -a given <<< "${H2S_SHELL_MODULE_PATH-}"
    for entry in "${given[@]}"; do
        [ -n "$entry" ] || continue
        if [ -f "$entry/module.json" ]; then
            candidates+=("$entry")
        elif [ -d "$entry" ]; then
            for dir in "$entry"/*/; do
                [ -f "${dir}module.json" ] && candidates+=("$dir")
            done
        fi
    done
    while read -r root; do
        for dir in "$root"/*/; do
            [ -f "${dir}module.json" ] && candidates+=("$dir")
        done
    done < <(module_roots)
    for entry in "${candidates[@]}"; do
        cd -P -- "$entry" 2> /dev/null || continue
        path=$PWD
        # (A path with a ":" cannot be in the list)
        case "$path" in *:*) continue ;; esac
        case "$seen" in *":$path:"*) continue ;; esac
        seen="$seen$path:"
        if [ ${#result[@]} -ge "$max_modules" ] || [ $((length + ${#path} + 1)) -gt "$max_modules_length" ]; then
            dropped=$((dropped + 1))
            continue
        fi
        length=$((length + ${#path} + 1))
        result+=("$path")
    done
    [ "$dropped" = 0 ] || say "modules: $dropped dropped (at most $max_modules modules and $max_modules_length bytes)"
    [ ${#result[@]} -eq 0 ] || say "modules: ${#result[@]} ($(IFS=:; echo "${result[*]}"))"
    (IFS=:; printf '%s' "${result[*]}")
}
# Exports H2S_SHELL_MODULES for the next start: the search, bounded. `timeout` runs it in a
# process group of its own and signals the whole group (a `sleep`, a stuck `cd` go too); -k:
# KILL a second after a TERM that did not end it. Its standard output is the list.
discover_modules() {
    local list status=0
    unset H2S_SHELL_SAFE_MODE
    if command -v timeout > /dev/null; then
        list=$(timeout -k 1 "$discovery_seconds" "$BASH" "$launcher_script" --discover-modules < /dev/null) || status=$?
    else
        list=$("$BASH" "$launcher_script" --discover-modules < /dev/null) || status=$?
    fi
    if [ "$status" = 124 ] || [ "$status" = 137 ]; then
        say "module discovery took longer than $discovery_seconds s: starting the shell without modules"
        list=""
    elif [ "$status" != 0 ]; then
        say "module discovery failed (status $status): starting the shell without modules"
        list=""
    fi
    export H2S_SHELL_MODULES="$list"
}

prepare_environment() {
    # Marks the shell as started here: without it, the shell shows a banner saying the
    # icon theme cannot apply and how to start it instead
    export H2S_SHELL_LAUNCHER=1
    local theme
    theme=$(resolve_theme)
    if [ -n "$theme" ]; then
        export QS_ICON_THEME="$theme"
    fi
}

# The lock marker the shell writes (singletons/Lockscreen.qml): "locked <key>" while it holds
# or asks for a lock of the session
died_locked() {
    local word=""
    [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -f "$XDG_RUNTIME_DIR/h2s-shell-lock" ] \
        && read -r word _ < "$XDG_RUNTIME_DIR/h2s-shell-lock" 2> /dev/null
    [ "$word" = locked ]
}

compositor_socket() {
    local display=${WAYLAND_DISPLAY:-wayland-0}
    case "$display" in /*) echo "$display" ;; *) echo "$runtime_dir/$display" ;; esac
}
socket_identity() { stat -L -c '%d:%i:%Z' "$(compositor_socket)" 2> /dev/null; }

# The compositor this launcher started under is still there. Not just "a socket file at
# that path": a compositor that crashed leaves its socket behind, and one started later
# under the same name is another session (whose own autostart starts its own shell). So:
# the socket is the one seen when this launcher started (device, inode, ctime — as the
# lock marker's key), and its compositor holds it: libwayland-server keeps an exclusive
# flock on `<socket>.lock` for as long as it serves the socket.
compositor_alive() {
    local socket
    socket=$(compositor_socket)
    [ -S "$socket" ] || return 1
    if [ -n "$compositor_identity" ] && [ "$(socket_identity)" != "$compositor_identity" ]; then
        say "the compositor's socket $socket is not the one this launcher started under (a new compositor session)"
        return 1
    fi
    if [ -e "$socket.lock" ] && command -v flock > /dev/null; then
        if flock -n -s "$socket.lock" true 2> /dev/null; then
            say "nobody holds $socket.lock: the compositor is dead (its socket was left behind)"
            return 1
        fi
    fi
    return 0
}

# What a dead shell left behind in its process group, of its own program: PAM helpers.
# Quickshell's PAM conversations run in a fork of the shell, killed only when the shell
# destroys them; after a crash a helper blocked in pam_fprintd keeps the fingerprint reader
# claimed (the next shell's fingerprint fails until it times out). The shell ran in a
# process group of its own (set -m, below), whose id is its pid and cannot be reused while
# anything is left in it; of what is left only processes running Quickshell's binary are
# killed — never a program the shell started (a terminal, a browser), nor Quickshell's
# crash reporter. The reporter is told by `__QUICKSHELL_CRASH_DUMP_FD`, which only it gets
# (src/crash/handler.cpp): a shell Quickshell relaunched in place carries the other
# `__QUICKSHELL_CRASH_*` variables in its environment, and so does every PAM helper it forks.
# It runs right after a death, before the restart (perhaps with the session locked and no
# lock client), so the walk forks nothing per process: every stat is read with bash's own
# `read`; only the few in the group cost a `readlink`, and their environment is read with
# `mapfile`.
clean_up_after() {
    local group=$1 stat pid binary fields variable crash_reporter
    local -a environment
    for stat in /proc/[0-9]*/stat; do
        pid=${stat#/proc/}
        pid=${pid%/stat}
        [ "$pid" = "$$" ] && continue
        # The whole file, up to its end (the command name may hold a newline)
        fields=""
        { IFS= read -r -d '' fields < "$stat"; } 2> /dev/null
        [ -n "$fields" ] || continue
        fields=${fields##*) }
        set -- $fields
        [ "$3" = "$group" ] || continue
        binary=$(readlink "/proc/$pid/exe" 2> /dev/null) || continue
        case "${binary##*/}" in *quickshell*) ;; *) continue ;; esac
        environment=()
        { mapfile -t -d '' environment < "/proc/$pid/environ"; } 2> /dev/null
        crash_reporter=""
        for variable in "${environment[@]}"; do
            [[ "$variable" == __QUICKSHELL_CRASH_DUMP_FD=* ]] && { crash_reporter=1; break; }
        done
        [ -n "$crash_reporter" ] && continue
        say "killing what the shell left behind: $pid ($binary)"
        kill -KILL "$pid" 2> /dev/null
    done
}

# The pauses, in milliseconds: the first after a quick death (doubling while the shell
# keeps dying within 30 s of starting), and the slow retry of a shell that died while
# locked and keeps dying; and how long a new launcher waits for an old one to end.
# H2S_LAUNCHER_TEST_TIMINGS ("first=0.1 slow=2 lockwait=3", seconds) shortens them for the
# lock test bed — inert unless set, and like the shell's test seams it grants nothing.
# "discoveryhang=S" makes module discovery take S seconds, as on a hung mount (find_modules).
pause_first_ms=1000
pause_slow_ms=60000
lock_wait=15
discovery_hang_ms=""
seconds_to_ms() { awk -v seconds="$1" 'BEGIN { if (seconds + 0 > 0) printf "%d", seconds * 1000 }'; }
for timing in ${H2S_LAUNCHER_TEST_TIMINGS:-}; do
    value=$(seconds_to_ms "${timing#*=}")
    [ -n "$value" ] || continue
    case "$timing" in
        first=*) pause_first_ms=$value ;;
        slow=*) pause_slow_ms=$value ;;
        lockwait=*) lock_wait=$(( (value + 999) / 1000 )) ;;
        discoveryhang=*) discovery_hang_ms=$value ;;
    esac
done
ms_to_seconds() { awk -v ms="$1" 'BEGIN { printf "%.3f", ms / 1000 }' | sed 's/\.\?0*$//'; }

# Becomes the session's one supervisor: takes the lock, waiting (bounded) for a launcher
# that is ending — `--restart` starts this one while the old one lets its shell go — and
# gives up when another keeps it (a second autostart, a second terminal). Without flock
# (it is util-linux's, in every base system) it goes on unguarded.
become_supervisor() {
    if ! command -v flock > /dev/null; then
        say "flock is not installed: cannot make sure no other launcher supervises a shell"
        return 0
    fi
    if ! exec {lock_fd}>> "$lock_file"; then
        say "cannot open $lock_file: going on without the one-supervisor guard"
        return 0
    fi
    if ! flock -n "$lock_fd"; then
        local holder
        holder=$(recorded_supervisor) || holder="?"
        say "another launcher (pid $holder) supervises the shell: waiting up to $lock_wait s for it to end"
        if ! flock -w "$lock_wait" "$lock_fd"; then
            holder=$(recorded_supervisor) || holder="?"
            say "launcher $holder still supervises the shell of this session: not starting a second one" \
                "(h2s-shell --restart replaces it)"
            exit 1
        fi
    fi
    echo $$ > "$lock_file"
}

# Waits until the shell process ends — not when it only stops (SIGSTOP while debugging,
# SIGTTIN/SIGTTOU from a terminal): with job control on, a plain `wait` returns at a stop,
# and the stopped shell was taken for a dead one, killed and replaced. `wait -f` (bash 5.1)
# waits for the end; a trapped signal still interrupts it, and the loop waits again while
# the process exists. Older bash: a stopped child is polled.
wait_for_shell() {
    while :; do
        if [ "$wait_ends" = 1 ]; then wait -f "$child"; else wait "$child"; fi
        status=$?
        # bash already reaped it and kept no record (seen with bash 5.3: "wait_for: No record
        # of process", while `kill -0` still found the pid for a while — a busy loop that
        # never restarted the shell). It has ended; its status is lost: taken for a crash
        # (restarted — the safe side for a lock screen)
        if [ "$status" = 127 ]; then
            say "the shell's exit status was lost (bash kept no record of it): taken for a crash"
            status=255
            return 0
        fi
        kill -0 "$child" 2> /dev/null || return 0
        [ "$wait_ends" = 1 ] || sleep 1
    done
}

# Runs the shell as a child and starts it again when it dies — not when it was stopped on
# purpose. On purpose: it quit cleanly (`qs kill`, exit status 0) or by SIGTERM / SIGINT /
# SIGHUP — unless the screen was locked (the marker says so), since then only a new shell
# can give the owner a prompt; or this script was told to stop (SIGUSR1: let the shell go,
# as stop_shell does; SIGTERM/SIGINT: stop it too); or the compositor is gone (the session
# ended, or crashed). SIGHUP (the terminal it was started from closed) is not a request to
# stop: the shell runs on, supervised. Anything else — a crash Quickshell's own handler
# gave up on (it restarts a crashed shell in the same process unless it crashed within 10 s
# of starting, then it exits with 255), SIGKILL, the OOM killer — starts it again after a
# pause: 1 s, doubling while it keeps dying within 30 s of starting. More than 5 restarts
# in 2 minutes: given up — unless the screen was locked when it died and the compositor is
# still there, since giving up then leaves the owner at the compositor's dead-lock screen
# for good: tried again every minute, until one runs (a later fix, a setting switched on).
supervise() {
    prepare_environment
    export H2S_SHELL_SUPERVISOR=$$
    local child="" stopping="" status=0 started delay_ms=$pause_first_ms slow="" lock_fd=""
    local recent=() wait_ends=0
    # Deaths within 30 s of starting, in a row: from two on, the next start is in safe mode
    local quick_deaths=0
    [ "${BASH_VERSINFO[0]}" -gt 5 ] || { [ "${BASH_VERSINFO[0]}" -eq 5 ] && [ "${BASH_VERSINFO[1]}" -ge 1 ]; } && wait_ends=1
    [ -f "$launcher_log" ] && [ "$(stat -c %s "$launcher_log" 2> /dev/null || echo 0)" -gt 524288 ] \
        && mv -f "$launcher_log" "$launcher_log.old" 2> /dev/null
    become_supervisor
    # (Without the lock, a descriptor of no consequence: the redirections below close it)
    [ -n "$lock_fd" ] || exec {lock_fd}< /dev/null
    compositor_identity=$(socket_identity)
    say "supervising the shell in $shell_dir (compositor socket $(compositor_socket)${compositor_identity:+, $compositor_identity})"
    trap 'stopping=1; say "told to let the shell go (SIGUSR1)"' USR1
    trap 'stopping=1; say "told to stop (SIGTERM/SIGINT): stopping the shell"; [ -n "$child" ] && kill -TERM "$child" 2> /dev/null' TERM INT
    trap 'say "SIGHUP (the terminal it was started from closed?): the shell runs on, supervised"' HUP
    # Each child in a process group of its own: what it leaves behind can be found
    set -m
    while :; do
        # (Bounded, closing the lock's descriptor: a search the bound could not kill must not
        # keep the next launcher out)
        discover_modules {lock_fd}>&-
        # Told to stop while the search ran (a --restart's stop_shell: its new launcher waits
        # for this one to end, and a shell started now would be one it never sees)
        [ -n "$stopping" ] && break
        # Crash-loop safe mode (docs/plans/modules.md): a shell that died quickly twice in a
        # row is started without modules — a module that crashes it at start would otherwise
        # keep the session without a bar, or locked without a prompt. A start that lives past
        # the quick-death window ends it (quick_deaths is counted below).
        if [ "$quick_deaths" -ge 2 ]; then
            export H2S_SHELL_SAFE_MODE=1
            say "the shell died within 30 s of starting $quick_deaths times in a row: starting it in safe mode (no modules)"
        fi
        started=$SECONDS
        # Not the lock's descriptor (a shell outliving this launcher would keep the next one
        # out), nor a terminal's input (a background job reading it is stopped)
        qs --log-times -p "$shell_dir" "$@" < /dev/null {lock_fd}>&- &
        child=$!
        say "started the shell: pid $child"
        wait_for_shell
        clean_up_after "$child"
        child=""
        [ -n "$stopping" ] && break
        if ! died_locked; then
            case "$status" in
                0) say "the shell quit (status 0)"; break ;;
                129 | 130 | 143) say "the shell was stopped (status $status)"; break ;;
            esac
        fi
        compositor_alive || { say "the shell exited (status $status); the compositor is gone: not starting it again"; break; }
        local now=$SECONDS kept=() time
        if [ $((now - started)) -ge 30 ]; then
            delay_ms=$pause_first_ms
            slow=""
            recent=()
        fi
        # What this counter can see: how long the PROCESS it started lived. Not how long the
        # image that died ran: Quickshell relaunches a crashed shell in place (same pid, unseen
        # here), so a process that lived long may have died seconds after such a relaunch.
        # Quickshell's own rule says when: a crash within 10 s of its (re)start is not
        # relaunched but exits 255 — so 255 after a long life is a quick death of a relaunched
        # image, counted (as is a lost status, taken for 255: the safe side). Any other end
        # after 30 s ends the run of quick deaths. The real crash-loop guard is the shell's own
        # count (docs/plans/modules.md, section 4).
        if [ $((now - started)) -lt 30 ] || [ "$status" = 255 ]; then
            quick_deaths=$((quick_deaths + 1))
        else
            quick_deaths=0
        fi
        for time in "${recent[@]}"; do [ $((now - time)) -lt 120 ] && kept+=("$time"); done
        recent=("${kept[@]}" "$now")
        # The slow retries were for a locked screen; that over (a shell came up and was
        # unlocked), deaths are counted afresh
        if [ -n "$slow" ] && ! died_locked; then
            slow=""
            recent=("$now")
            delay_ms=$pause_first_ms
        fi
        if [ -z "$slow" ] && [ "${#recent[@]}" -gt 5 ]; then
            if died_locked; then
                slow=1
                say "the shell died $((${#recent[@]} - 1)) times in 2 minutes while the screen was locked: trying again every $(ms_to_seconds "$pause_slow_ms") s"
            else
                say "the shell died $((${#recent[@]} - 1)) times in 2 minutes: not starting it again"
                exit 1
            fi
        fi
        [ -n "$slow" ] && delay_ms=$pause_slow_ms
        say "the shell exited (status $status)$(died_locked && echo ' while the screen was locked'): starting it again in $(ms_to_seconds "$delay_ms") s"
        sleep "$(ms_to_seconds "$delay_ms")" {lock_fd}>&- &
        wait $! 2> /dev/null
        kill $! 2> /dev/null
        [ -z "$slow" ] && [ $((now - started)) -lt 30 ] && delay_ms=$((delay_ms * 2))
        [ -n "$stopping" ] && break
        compositor_alive || { say "the compositor is gone: not starting the shell again"; break; }
    done
    say "supervisor ends"
}

# `qs ipc` to this shell, with one thing added: Quickshell answers "Not ready to accept
# queries yet." while it reloads (two generations alive for a moment, src/io/ipccomm.cpp)
# and exits 0 all the same — the owner's Super+L was silently lost. Such a request, and one
# made while no shell runs (the supervisor restarting it), is tried again for up to 3 s;
# still not taken, it fails (status 1).
ipc_with_retry() {
    case "$1" in
        call | prop) ;;
        *) exec qs -p "$shell_dir" ipc "$@" ;;
    esac
    local errors output status attempt
    errors=$(mktemp "${TMPDIR:-/tmp}/h2s-shell-ipc.XXXXXX") || exec qs -p "$shell_dir" ipc "$@"
    for attempt in $(seq 1 30); do
        output=$(qs -p "$shell_dir" ipc "$@" 2> "$errors")
        status=$?
        # (Quickshell prints these on its standard output or error, depending on the case)
        { printf '%s\n' "$output"; cat "$errors"; } | grep -qE 'Not ready to accept queries yet|No running instances' || break
        [ "$attempt" = 30 ] && { status=1; break; }
        sleep 0.1
    done
    [ -n "$output" ] && printf '%s\n' "$output"
    cat "$errors" >&2
    rm -f "$errors"
    return "$status"
}

case "$1" in
    # Internal: the module search, run by discover_modules under its bound
    --discover-modules) find_modules; exit 0 ;;
    # Straight to the running shell: no icon theme to work out
    ipc) shift; ipc_with_retry "$@"; exit $? ;;
    # The lock screen's log, for reading after a failed attempt (the wrapper's PATH has qs)
    --lock-log) shift; exec "$shell_dir/scripts/lock-log.sh" "$@" ;;
    --list) list_themes ;;
    --resolve) resolve_theme ;;
    --preview) preview_theme "$2" ;;
    --restart)
        stop_shell
        shift
        # A new supervisor, out of this process's session (the settings' "Restart to apply"
        # runs this from inside the shell being stopped). It waits for the old one to end
        # (the lock); what it says goes to the launcher's log, the shell's own log is
        # Quickshell's (`qs log`, scripts/lock-log.sh)
        self=$(readlink -f "$0")
        if command -v setsid > /dev/null; then
            setsid "$self" "$@" < /dev/null > /dev/null 2>&1 &
        else
            ( trap '' HUP; exec "$self" "$@" ) < /dev/null > /dev/null 2>&1 &
        fi
        ;;
    *)
        # Quickshell's daemon mode: its starter exits as soon as the shell is up, so there is
        # nothing to supervise (and a supervisor would take that exit for the shell's)
        for argument in "$@"; do
            case "$argument" in
                -d | --daemonize) prepare_environment; discover_modules; exec qs -p "$shell_dir" "$@" ;;
            esac
        done
        supervise "$@"
        ;;
esac
