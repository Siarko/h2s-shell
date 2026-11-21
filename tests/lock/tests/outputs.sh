# Outputs come and go while locked (a monitor unplugged, a laptop's screen over a suspend):
# each lock surface is an instance of its own, and the prompt follows them. Two rounds:
#
#   added, then removed: the prompt is on the added output when it goes, and moves, awake,
#   to the one left; the password typed there unlocks.
#   removed, then re-added: the output showing the prompt is removed (the prompt moves to
#   the other one) and an output of that kind is added again; a press on the new one
#   brings the prompt there, and the password typed there unlocks.
#
# hyprctl talks to the nested Hyprland only (the private runtime dir).

stack_start

headless_output() {
    hyprctl -j monitors | python3 -I -c '
import json, sys
names = [monitor["name"] for monitor in json.load(sys.stdin) if monitor["name"].startswith("HEADLESS")]
print(names[0] if names else "")'
}
# point_at <x> <y> <layout width> <layout height>: an absolute pointer position over the
# whole layout (Hyprland maps the virtual pointer's extent onto it)
point_at() { send_input "abs $1 $2 $3 $4" "move 5 5"; }

# ---- Added, then removed ----
lock_by_ipc
check_within "$GUARD" "round 1: locked" compositor_locked
check_within "$GUARD" "round 1: confirmed" state_is secure true
check "round 1: one surface" state_is surfaces 1

hyprctl output create headless > /dev/null
check_within "$GUARD" "round 1: an added output gets a surface of its own" state_is surfaces 2
added=$(headless_output)
log "added output: $added; surfaces: $(state_field surface_screens)"
woke=0
for attempt in 1 2 3 4 5; do
    point_at $((2800 + attempt * 10)) 500 3840 1080
    wait_until 0.5 state_is prompt_screen "$added" && { woke=1; break; }
done
check "round 1: the pointer on the added output wakes the prompt there" test "$woke" = 1
type_text "half"

hyprctl output remove "$added" > /dev/null
check_within "$GUARD" "round 1: the removed output's surface goes" state_is surfaces 1
check_within "$GUARD" "round 1: the prompt moves, awake, to the output left" state_is prompt_screen WAYLAND-1
check "round 1: and starts with an empty field (a new epoch)" test "$(state_field field_epoch)" -ge 1
check "round 1: still locked" compositor_locked

type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "round 1: the password typed afterwards unlocks" compositor_unlocked
log "password checks: $(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)"
check "round 1: what was half typed on the removed output was not sent with it" \
    test "$(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)" = "right "

# ---- Removed, then re-added ----
hyprctl output create headless > /dev/null
wait_until 5 test -n "$(headless_output)" || abort "no second output for round 2"
lock_by_ipc
check_within "$GUARD" "round 2: locked" compositor_locked
check_within "$GUARD" "round 2: two surfaces" state_is surfaces 2
woke=0
for attempt in 1 2 3 4 5; do
    point_at $((200 + attempt * 10)) 500 3840 1080
    wait_until 0.5 state_is prompt_screen WAYLAND-1 && { woke=1; break; }
done
check "round 2: the prompt wakes on WAYLAND-1" test "$woke" = 1
before=$(state_field prompt_surface)

hyprctl output remove WAYLAND-1 > /dev/null
check_within "$GUARD" "round 2: the prompt's output removed, its surface goes" state_is surfaces 1
check_within "$GUARD" "round 2: the prompt moves to the other output" state_is prompt_screen "$(headless_output)"

hyprctl output create wayland > /dev/null
check_within "$GUARD" "round 2: the re-added output gets a new surface" state_is surfaces 2
readded=$(state_field surface_screens | tr ',' '\n' | grep '^WAYLAND' | head -n 1)
log "re-added output: $readded; surfaces: $(state_field surface_screens)"
# The layout is now the headless output (1920 wide) at 0, the re-added one right of it
# (1280x720): press on it
moved=0
for attempt in 1 2 3 4 5; do
    send_input "abs $((2400 + attempt * 10)) 300 3200 1080" "move 5 5" "click left"
    wait_until 0.5 state_is prompt_screen "$readded" && { moved=1; break; }
done
check "round 2: a press on the re-added output brings the prompt there" test "$moved" = 1
check "round 2: on a new instance, not the removed one's" test "$(state_field prompt_surface)" != "$before"
check "round 2: still locked" compositor_locked

type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "round 2: the password typed on the re-added output unlocks" compositor_unlocked
check "round 2: the shell says unlocked" shell_status_is unlocked
