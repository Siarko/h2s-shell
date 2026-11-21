# Two outputs, end to end (the rules decide; this checks that the views deliver it):
#
#   the prompt wakes on the output where the pointer moves, and shows there only — both
#   outputs' screenshots say so, and the state;
#   keyboard focus follows the pointer between lock surfaces (Hyprland): a key typed with
#   the pointer on the other output wakes the prompt THERE when it sleeps — and, with the
#   prompt awake elsewhere, is forwarded to it: the password typed on one output unlocks
#   the prompt shown on the other;
#   a press on the other output moves the prompt there, with an empty field (what was half
#   typed is not sent), and after the cross-fade only that output shows it.
#   the cursor shows while the prompt is awake and is hidden while it sleeps.
#
# The layout: WAYLAND-1 at 0,0, the added headless output right of it; the virtual
# pointer's absolute extent is the whole layout.

stack_start

hyprctl output create headless > /dev/null
second() {
    hyprctl -j monitors | python3 -I -c '
import json, sys
names = [monitor["name"] for monitor in json.load(sys.stdin) if monitor["name"].startswith("HEADLESS")]
print(names[0] if names else "")'
}
wait_until 5 test -n "$(second)" || abort "no second output"
B=$(second)
A=WAYLAND-1
# The layout's size, for the pointer's absolute extent: A at 0,0, B right of it
read -r width_a width_b layout_height <<< "$(hyprctl -j monitors | python3 -I -c '
import json, sys
monitors = {monitor["name"]: monitor for monitor in json.load(sys.stdin)}
a, b = monitors["WAYLAND-1"], monitors[sys.argv[1]]
print(a["width"], b["width"], max(a["height"], b["height"]))' "$B")"
layout_width=$((width_a + width_b))
on_a() { send_input "abs $((300 + $1)) 300 $layout_width $layout_height" "move 3 3"; }
on_b() { send_input "abs $((width_a + 300 + $1)) 300 $layout_width $layout_height" "move 3 3"; }

# shows_prompt <output> <shot>: that output's screenshot differs from its asleep one in
# the prompt's area (the card's text: heading, placeholder, button)
shows_prompt() { [ "$(prompt_region_changes "asleep-$1" "$2")" -gt 500 ]; }
shows_no_prompt() { ! shows_prompt "$@"; }
# shot <name>: both outputs, as <name>-A / <name>-B
shot() { screenshot_output_ppm "$A" "$1-A"; screenshot_output_ppm "$B" "$1-B"; }

lock_by_ipc
check_within "$GUARD" "locked" compositor_locked
check_within "$GUARD" "confirmed" state_is secure true
check_within "$GUARD" "a surface on each output" state_is surfaces 2
sleep 1 # fixed sleep: a negative claim: nothing wakes the prompt by itself
check "the prompt sleeps" state_is prompt_awake false
screenshot_output_ppm "$A" asleep-A
screenshot_output_ppm "$B" asleep-B

# ---- The prompt wakes where the pointer moves, and only there ----
woke=0
for attempt in 1 2 3 4 5; do
    on_b $((attempt * 10))
    wait_until 0.5 state_is prompt_screen "$B" && { woke=1; break; }
done
check "the pointer moving on $B wakes the prompt there" test "$woke" = 1
wait_settled # the fade
shot awake-on-b
check "screenshots: $B shows the prompt" shows_prompt B awake-on-b-B
check "screenshots: $A does not" shows_no_prompt A awake-on-b-A

# ---- Keyboard focus follows the pointer; keys reach the prompt wherever it is ----
on_a 10
on_a 20
sleep 0.3 # fixed sleep: a negative claim: motion on the other output does not move the prompt
check "motion on $A leaves the prompt on $B" state_is prompt_screen "$B"
check_within 15 "the prompt goes to sleep" state_is prompt_awake false
press_key Tab
check_within "$GUARD" "a key with the pointer on $A wakes the prompt on $A: the keyboard is there" state_is prompt_screen "$A"
on_b 30
on_b 40
sleep 0.3 # fixed sleep: a negative claim: motion on the other output does not move the prompt
check "motion on $B leaves the prompt on $A" state_is prompt_screen "$A"
wait_settled
shot awake-on-a
check "screenshots: $A shows the prompt" shows_prompt A awake-on-a-A
check "screenshots: $B does not" shows_no_prompt B awake-on-a-B
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password typed on $B unlocks the prompt shown on $A" compositor_unlocked
check "checked once, right" test "$(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)" = "right "

# ---- A press on the other output moves the prompt there, empty ----
lock_by_ipc
check_within "$GUARD" "locked again" compositor_locked
check_within "$GUARD" "two surfaces again" state_is surfaces 2
wait_settled
screenshot_output_ppm "$A" asleep-A
screenshot_output_ppm "$B" asleep-B
woke=0
for attempt in 1 2 3 4 5; do
    on_a $((attempt * 10))
    wait_until 0.5 state_is prompt_screen "$A" && { woke=1; break; }
done
check "the prompt wakes on $A" test "$woke" = 1
type_text "half-typed"
epoch=$(state_field field_epoch)
send_input "abs $((width_a + 500)) 200 $layout_width $layout_height" "move 3 3"
# Through the cross-fade (150 ms with the built-in theme): screenshots back to back from
# the press on (looked at afterwards: comparing is slow), then never two prompts once it
# is over
send_input "click left"
pressed=${EPOCHREALTIME//[.,]/}
for sample in 1 2 3 4 5 6 7 8; do
    shot fade-$sample
    offsets[$sample]=$(( (${EPOCHREALTIME//[.,]/} - pressed) / 1000 ))
done
check_within "$GUARD" "a press on $B moves the prompt there" state_is prompt_screen "$B"
check "with a new field (the epoch moved)" test "$(state_field field_epoch)" -gt "$epoch"
both_after=0
for sample in 1 2 3 4 5 6 7 8; do
    log "cross-fade, ${offsets[$sample]} ms after the press: prompt pixels on $A $(prompt_region_changes asleep-A "fade-$sample-A"), on $B $(prompt_region_changes asleep-B "fade-$sample-B")"
    if [ "${offsets[$sample]}" -ge 400 ] && shows_prompt A "fade-$sample-A"; then both_after=1; fi
done
check "from 400 ms after the press on, $A no longer shows the prompt" test "$both_after" = 0
check "and $B does" shows_prompt B fade-8-B
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password typed after the move unlocks" compositor_unlocked
check "what was half typed on $A was not sent with it" \
    test "$(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)" = "right right "

# ---- The cursor: shown while the prompt is awake, hidden while it sleeps ----
# On B: the headless output draws the cursor into its picture (WAYLAND-1, nested in labwc,
# hands it to the parent compositor, so screenshots of it never show one)
lock_by_ipc
check_within "$GUARD" "locked a third time" compositor_locked
check_within "$GUARD" "two surfaces" state_is surfaces 2
woke=0
for attempt in 1 2 3 4 5; do
    on_b $((100 + attempt))
    wait_until 0.5 state_is prompt_screen "$B" && { woke=1; break; }
done
check "the prompt wakes on $B" test "$woke" = 1
wait_settled "$B"
screenshot_output_ppm "$B" cursor-awake
check_within 15 "the prompt goes to sleep, the pointer resting" state_is prompt_awake false
wait_settled "$B"
screenshot_output_ppm "$B" cursor-asleep
# The pointer rests at 403..408,303 of B (on_b, then the 3-pixel move), far from the card
cursor_changes=$(python3 -I -c "$_PPM_READER"'
width, height, first = read_ppm(sys.argv[1])
_, _, second = read_ppm(sys.argv[2])
count = 0
for y in range(295, 345):
    for x in range(395, 445):
        offset = (y * width + x) * 3
        if max(abs(first[offset + c] - second[offset + c]) for c in range(3)) > 40:
            count += 1
print(count)' "$WORK/cursor-awake.ppm" "$WORK/cursor-asleep.ppm")
log "pixels changed where the pointer rests, awake to asleep: $cursor_changes"
check "the cursor shows while the prompt is awake and is hidden when it sleeps" test "$cursor_changes" -gt 20
