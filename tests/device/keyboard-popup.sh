#!/usr/bin/env bash
# On a touch device with an on-screen keyboard (the Framework 12, oskbd): taps the running
# shell's calendar popup with a virtual finger and checks each step — the keyboard shows
# for a text field and hides after, tapping the keyboard keeps the popup, a tap outside
# closes it. See tests/device/README.md.
#
#   tests/device/keyboard-popup.sh            the shell started by `h2s-shell`
#   H2S_SHELL_DIR=~/src/h2s-shell tests/device/keyboard-popup.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1}
export HYPRLAND_INSTANCE_SIGNATURE=${HYPRLAND_INSTANCE_SIGNATURE:-$(ls -t "$XDG_RUNTIME_DIR/hypr" | head -1)}

ipc() { h2s-shell ipc call shelltest "$@"; }
python_env='with import <nixpkgs> {}; python3.withPackages (p: [ p.evdev ])'
tap() { nix shell --impure --expr "$python_env" -c python3 "$here/touchtap.py" "$@" 2>&1 | grep -v "^building"; }
centre() { echo "$1" | sed -E 's/.*"x":([0-9-]+),"y":([0-9-]+),"width":([0-9]+),"height":([0-9]+).*/\1 \2 \3 \4/' \
    | awk '{ printf "%d %d", $1 + $3 / 2, $2 + $4 / 2 }'; }
corner() { echo "$1" | sed -E 's/.*"x":([0-9-]+),"y":([0-9-]+).*/\1 \2/' | awk '{ printf "%d %d", $1 + 6, $2 + 6 }'; }
keyboard_up() { hyprctl layers -j | grep -q '"namespace": "osk"'; }
keyboard_down() { ! keyboard_up; }
state() { ipc popupState; }

failures=0
check() {  # check <description> <command…>
    local description=$1; shift
    if "$@"; then echo "  PASS: $description"; else echo "  FAIL: $description"; failures=$((failures + 1)); fi
}
field() { state | grep -q "\"$1\":$2"; }

# An empty workspace with a neutral window: oskbd shows only while some window has the
# focus, and a terminal keeps it up on its own (oskbd's rules)
previous=$(hyprctl activeworkspace -j | grep -m1 '"id"' | tr -dc '0-9')
hyprctl dispatch 'hl.dsp.focus({ workspace = 9 })' >/dev/null
hyprctl dispatch 'hl.dsp.exec_cmd("nix shell nixpkgs#wev -c wev > /dev/null 2>&1")' >/dev/null
sleep 3

echo "=== calendar popup, by touch"
read -r x y < <(centre "$(ipc cellRect clock)")
tap "tap $x $y"; sleep 1
check "a tap on the clock opens the calendar" field open true
check "opened by touch" field touchOpened true
check "no keyboard yet" keyboard_down

read -r x y < <(centre "$(ipc popupItemRect calendarAdd)")
tap "tap $x $y"; sleep 1
read -r x y < <(centre "$(ipc popupItemRect eventTitle)")
title="$x $y"
tap "tap $title"; sleep 1.5
check "a tap on the title field takes the keyboard" field typing true
check "the on-screen keyboard shows" keyboard_up

read -r x y < <(corner "$(ipc popupItemRect popupBody)")
tap "tap $x $y"; sleep 1.5
check "a tap off the field lets the keyboard go" field typing false
check "the on-screen keyboard hides" keyboard_down

tap "tap $title"; sleep 1.5
check "the field again: the keyboard shows" keyboard_up
tap "tap 300 900"; sleep 1
check "a tap on the keyboard keeps the popup" field open true
check "and the field" field typing true

tap "tap 40 500"; sleep 1.5
check "a tap outside closes the popup" field open false

pkill -x wev
hyprctl dispatch "hl.dsp.focus({ workspace = $previous })" >/dev/null
echo "--- $failures failed"
exit $((failures > 0))
