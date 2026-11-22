# Power control there (Hyprland), but the monitor list empty: the shell's hyprctl is a
# stand-in that answers `-j monitors` with no monitor and passes everything else on. Nothing
# may be lost to that: the config falls back to the screens, with the screensaver (no "off"),
# and the lock screen's screen-off still blacks the lock surface.

real_hyprctl=$(command -v hyprctl) || abort "no hyprctl"
mkdir -p "$WORK/hyprctl-bin"
printf '#!%s
[ "$1 $2" = "-j monitors" ] && { echo "[]"; exit 0; }
exec %q "$@"
' "$(command -v bash)" "$real_hyprctl" > "$WORK/hyprctl-bin/hyprctl"
chmod +x "$WORK/hyprctl-bin/hyprctl"
stack_start --shell-path "$WORK/hyprctl-bin" --settings '{"lockscreen.screensaverEnabled": true,
    "lockscreen.screensaverTimeout": 5, "lockscreen.blanking": "off", "lockscreen.lockedScreenOffTimeout": 5}'

# idle_is <section> <field> <value>: the shell's `idle state` says so
idle_is() {
    [ "$(shell_ipc idle state | python3 -I -c 'import json, sys; print(json.dumps(json.load(sys.stdin)[sys.argv[1]][sys.argv[2]]))' "$1" "$2")" = "$3" ]
}
screens_listed() {
    shell_ipc idle state | python3 -I -c 'import json, sys; sys.exit(0 if json.load(sys.stdin)["config"]["monitors"] else 1)'
}

check_within "$GUARD" "no monitor read: no power control" idle_is config canPowerOff false
check "… the screens instead" screens_listed
check_timed 10 "5 s without input: the screensaver shows (\"Turn off\" falls back to it)" state_is screensaver true
move_pointer 700 400
move_pointer 720 410
check_within "$GUARD" "input: it goes" state_is screensaver false
lock_by_ipc
check_within "$GUARD" "locked" compositor_locked
check_timed 10 "5 s without input at the lock screen: the lock surface goes black" idle_is state lockBlack true
