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
# "Restart"). See supervise() for what counts as stopping on purpose.
#
#   launch.sh            start the shell, supervised (extra arguments go to qs; with -d,
#                        Quickshell's own daemon mode, the shell is not supervised: its
#                        starter exits at once. --restart is the detached, supervised start)
#   launch.sh --restart  stop the running shell and start it again, detached (supervised)
#   launch.sh ipc ARGS   `qs ipc ARGS` to this shell, e.g. `ipc call tablet set true`
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
    local stat
    stat=$(cat "/proc/$1/stat" 2> /dev/null) || return 1
    stat=${stat##*) }
    set -- $stat
    echo "$2"
}

# Asks the running shell to quit; one that does not answer (a hung instance cannot take
# the request over its socket) is terminated, then killed. The settings window is closed
# first: Quickshell tearing it down with a text field focused crashed it on the way out
# (QInputMethod::commit on the dying window), and the crash report popped up. A supervised
# shell's supervisor is told first to let it go (SIGUSR1), or it would start it again.
stop_shell() {
    local pids supervisor
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

runtime_dir=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}

say() { echo "h2s-shell launcher: $*" >&2; }

# The lock marker the shell writes (singletons/Lockscreen.qml): "locked <key>" while it holds
# or asks for a lock of the session
died_locked() {
    local word=""
    [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -f "$XDG_RUNTIME_DIR/h2s-shell-lock" ] \
        && read -r word _ < "$XDG_RUNTIME_DIR/h2s-shell-lock" 2> /dev/null
    [ "$word" = locked ]
}

# The compositor is still there to start a shell in: its socket exists (a compositor that
# exits removes it — the end of the session, when nothing is to be started again)
compositor_alive() {
    local display=${WAYLAND_DISPLAY:-wayland-0}
    case "$display" in /*) ;; *) display=$runtime_dir/$display ;; esac
    [ -S "$display" ]
}

# What a dead shell left behind in its process group, of its own program: PAM helpers.
# Quickshell's PAM conversations run in a fork of the shell, killed only when the shell
# destroys them; after a crash a helper blocked in pam_fprintd keeps the fingerprint reader
# claimed (the next shell's fingerprint fails until it times out). The shell ran in a
# process group of its own (set -m, below), whose id is its pid and cannot be reused while
# anything is left in it; of what is left only processes running Quickshell's binary are
# killed — never a program the shell started (a terminal, a browser), nor Quickshell's
# crash reporter (marked by its environment).
clean_up_after() {
    local group=$1 stat pid binary
    for stat in /proc/[0-9]*/stat; do
        pid=${stat#/proc/}
        pid=${pid%/stat}
        stat=$(cat "$stat" 2> /dev/null) || continue
        stat=${stat##*) }
        set -- $stat
        [ "$3" = "$group" ] || continue
        binary=$(readlink "/proc/$pid/exe" 2> /dev/null) || continue
        case "${binary##*/}" in *quickshell*) ;; *) continue ;; esac
        tr '\0' '\n' < "/proc/$pid/environ" 2> /dev/null | grep -q '^__QUICKSHELL_CRASH' && continue
        say "killing what the shell left behind: $pid ($binary)"
        kill -KILL "$pid" 2> /dev/null
    done
}

# Runs the shell as a child and starts it again when it dies — not when it was stopped on
# purpose. On purpose: it quit cleanly (`qs kill`, exit status 0) or by SIGTERM / SIGINT /
# SIGHUP — unless the screen was locked (the marker says so), since then only a new shell
# can give the owner a prompt; or this script was told to stop (SIGUSR1: let the shell go,
# as stop_shell does; SIGTERM/SIGINT/SIGHUP: stop it too); or the compositor is gone (the
# session ended). Anything else — a crash Quickshell's own handler gave up on (it restarts
# a crashed shell in the same process unless it crashed within 10 s of starting, then it
# exits with 255), SIGKILL, the OOM killer — starts it again after a pause: 1 s, doubling
# while it keeps dying within 30 s of starting, and never more than 5 times in 2 minutes
# (a shell that cannot start is not started forever).
supervise() {
    prepare_environment
    export H2S_SHELL_SUPERVISOR=$$
    local child="" stopping="" status started delay=1
    local recent=()
    trap 'stopping=1' USR1
    trap 'stopping=1; [ -n "$child" ] && kill -TERM "$child" 2> /dev/null' TERM INT HUP
    # Each child in a process group of its own: what it leaves behind can be found
    set -m
    while :; do
        started=$SECONDS
        qs -p "$shell_dir" "$@" &
        child=$!
        # `wait` returns early when a trapped signal arrives: wait again while it runs
        while :; do
            wait "$child"
            status=$?
            [ -z "$(jobs -pr)" ] && break
        done
        clean_up_after "$child"
        child=""
        [ -n "$stopping" ] && break
        if ! died_locked; then
            case "$status" in
                0) break ;;
                129 | 130 | 143) say "the shell was stopped (status $status)"; break ;;
            esac
        fi
        local now=$SECONDS kept=() time
        for time in "${recent[@]}"; do [ $((now - time)) -lt 120 ] && kept+=("$time"); done
        recent=("${kept[@]}" "$now")
        if [ "${#recent[@]}" -gt 5 ]; then
            say "the shell died $((${#recent[@]} - 1)) times in 2 minutes: not starting it again"
            exit 1
        fi
        if [ $((now - started)) -ge 30 ]; then delay=1; fi
        say "the shell exited (status $status)$(died_locked && echo ' while the screen was locked'): starting it again in $delay s"
        sleep "$delay" &
        wait $! 2> /dev/null
        [ $((now - started)) -lt 30 ] && delay=$((delay * 2))
        [ -n "$stopping" ] && break
        compositor_alive || { say "the compositor is gone: not starting the shell again"; break; }
    done
}

case "$1" in
    # Straight to the running shell: no icon theme to work out
    ipc) exec qs -p "$shell_dir" "$@" ;;
    --list) list_themes ;;
    --resolve) resolve_theme ;;
    --preview) preview_theme "$2" ;;
    --restart)
        stop_shell
        shift
        # A new supervisor, out of this process's session (the settings' "Restart to apply"
        # runs this from inside the shell being stopped); what it says goes to a log in the
        # runtime dir, the shell's own log is Quickshell's
        self=$(readlink -f "$0")
        if command -v setsid > /dev/null; then
            setsid "$self" "$@" < /dev/null >> "$runtime_dir/h2s-shell-launcher.log" 2>&1 &
        else
            ( trap '' HUP; exec "$self" "$@" ) < /dev/null >> "$runtime_dir/h2s-shell-launcher.log" 2>&1 &
        fi
        ;;
    *)
        # Quickshell's daemon mode: its starter exits as soon as the shell is up, so there is
        # nothing to supervise (and a supervisor would take that exit for the shell's)
        for argument in "$@"; do
            case "$argument" in
                -d | --daemonize) prepare_environment; exec qs -p "$shell_dir" "$@" ;;
            esac
        done
        supervise "$@"
        ;;
esac
