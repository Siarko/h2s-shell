# The lock screen's screen-off without power control (the shell started without Hyprland's
# instance: no backend can cut a monitor's power): after its time the lock surface goes plain
# black instead, and input brings the lock screen back. The output itself stays on.

stack_start --no-hyprland-ipc --settings '{"lockscreen.lockedScreenOffTimeout": 5}'

# idle_is <section> <field> <value>: the shell's `idle state` says so
idle_is() {
    [ "$(shell_ipc idle state | python3 -I -c 'import json, sys; print(json.dumps(json.load(sys.stdin)[sys.argv[1]][sys.argv[2]]))' "$1" "$2")" = "$3" ]
}
lock_black_is() { idle_is state lockBlack "$1"; }

check_within "$GUARD" "no power control here" idle_is config canPowerOff false
lock_by_ipc
check_within "$GUARD" "locked" compositor_locked
check "the lock screen not black at first" lock_black_is false
check_timed 10 "5 s without input at the lock screen: the lock surface goes black" lock_black_is true
move_pointer 700 400
move_pointer 720 410
check_within "$GUARD" "input: the lock screen shows again" lock_black_is false
check "… still locked" compositor_locked
