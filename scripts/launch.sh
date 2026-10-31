#!/bin/bash
# Starts the shell with the icon theme from its settings.
#
# Quickshell sets the icon theme once, at launch, from QS_ICON_THEME — nothing changes it
# while the shell runs. So the shell is started through here (Hyprland's autostart calls
# this script), and the settings' "Restart to apply" runs `launch.sh --restart`.
#
#   launch.sh            start the shell (extra arguments go to qs)
#   launch.sh --restart  stop the running shell and start it again, detached
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

# The running shell's process ids
shell_pids() {
    qs list -c default 2> /dev/null | sed -n 's/^ *Process ID: *//p'
}

# Asks the running shell to quit; one that does not answer (a hung instance cannot take
# the request over its socket) is terminated, then killed
stop_shell() {
    local pids
    pids=$(shell_pids)
    [ -n "$pids" ] || return
    qs kill -c default > /dev/null 2>&1
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

start() {
    # Marks the shell as started here: without it, the shell shows a banner saying the
    # icon theme cannot apply and how to start it instead
    export H2S_SHELL_LAUNCHER=1
    local theme
    theme=$(resolve_theme)
    if [ -n "$theme" ]; then
        export QS_ICON_THEME="$theme"
    fi
    exec qs -c default "$@"
}

case "$1" in
    --list) list_themes ;;
    --resolve) resolve_theme ;;
    --preview) preview_theme "$2" ;;
    --restart)
        stop_shell
        shift
        start -d "$@"
        ;;
    *) start "$@" ;;
esac
