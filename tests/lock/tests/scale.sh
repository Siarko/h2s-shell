# The prompt on a scaled and on a small output: whole, inside the screen, and working.
#
#   WAYLAND-1 asked for a fractional scale (1.5) and for scale 3, in its `preferred` mode:
#   that mode is 1280x720 pixels (Hyprland's window in labwc as it first came up, not the
#   1920x1080 the stack sets), and Hyprland takes the nearest scale that divides it evenly —
#   1.6 (800x450 logical) and 3.2 (400x225 logical). The test logs what was taken and
#   assumes none of these numbers: the prompt woken there shows wholly inside the output
#   (what changed against the asleep screen does not touch its edges), and the password
#   typed there unlocks;
#   a small output (300x260, scale 1, right of it): the prompt narrows to fit (the card is
#   320 wide, plus a margin each side) and a press there brings it, whole.
#
# hyprctl reaches the nested Hyprland only (the private runtime dir). Hyprland 0.57 has no
# `hyprctl keyword` (its config is Lua): monitor rules go through `hyprctl eval`.

stack_start

# prompt_box <asleep> <awake>: the bounding box "left top right bottom width height" of
# what changed between two screenshots of one output (the prompt; the cursor is in it too)
prompt_box() {
    python3 -I -c "$_PPM_READER"'
width, height, first = read_ppm(sys.argv[1])
_, _, second = read_ppm(sys.argv[2])
left, top, right, bottom = width, height, -1, -1
for y in range(height):
    row = y * width * 3
    for x in range(0, width):
        offset = row + x * 3
        if max(abs(first[offset + c] - second[offset + c]) for c in range(3)) > 40:
            left, right = min(left, x), max(right, x)
            top, bottom = min(top, y), max(bottom, y)
print(left, top, right, bottom, width, height)' "$WORK/$1.ppm" "$WORK/$2.ppm"
}
# inside <asleep> <awake>: the prompt changed something, and nothing at the output's edges
inside() {
    local left top right bottom width height
    read -r left top right bottom width height <<< "$(prompt_box "$1" "$2")"
    log "prompt area in $2: x $left..$right, y $top..$bottom of ${width}x$height"
    [ "$right" -ge 0 ] && [ "$left" -gt 0 ] && [ "$top" -gt 0 ] && [ "$right" -lt $((width - 1)) ] && [ "$bottom" -lt $((height - 1)) ]
}

# monitor_rule <output> <mode> <position> <scale>
monitor_rule() {
    hyprctl eval "hl.monitor({ output = \"$1\", mode = \"$2\", position = \"$3\", scale = \"$4\" })" > /dev/null
}
# The output's scale and logical size, as Hyprland has them ("1.5 1280 720")
output_scale() {
    hyprctl -j monitors | python3 -I -c '
import json, sys
for monitor in json.load(sys.stdin):
    if monitor["name"] == sys.argv[1]:
        print(monitor["scale"], round(monitor["width"] / monitor["scale"]), round(monitor["height"] / monitor["scale"]))' "$1"
}
# scaled <scale before>: the output has another scale now. A read that gave nothing (a
# hyprctl that failed) is not a change
scaled() {
    local now
    now=$(output_scale WAYLAND-1 | cut -d' ' -f1)
    [ -n "$now" ] && [ "$now" != "$1" ]
}
# An output's size in pixels, as Hyprland has it now ("300 260"); nothing when it is not there
output_pixels() {
    hyprctl -j monitors | python3 -I -c '
import json, sys
for monitor in json.load(sys.stdin):
    if monitor["name"] == sys.argv[1]:
        print(monitor["width"], monitor["height"])' "$1"
}
# The name of the headless output beside WAYLAND-1, once it is there (false until then)
small_output() {
    local name
    name=$(hyprctl -j monitors | python3 -I -c '
import json, sys
print(" ".join(monitor["name"] for monitor in json.load(sys.stdin) if monitor["name"].startswith("HEADLESS")))')
    [ -n "$name" ] && echo "${name%% *}"
}
small_output_is() { [ "$(output_pixels "$small")" = "$1 $2" ]; }

# Hyprland takes the nearest scale that divides the mode evenly: what it took is logged
for scale in 1.5 3; do
    before=$(output_scale WAYLAND-1 | cut -d' ' -f1)
    monitor_rule WAYLAND-1 preferred 0x0 "$scale"
    wait_until 3 scaled "$before" || abort "the scale $scale was not taken"
    log "asked for scale $scale: WAYLAND-1 is now (scale, logical size) $(output_scale WAYLAND-1)"
    lock_by_ipc
    check_within "$GUARD" "scale $scale: locked" compositor_locked
    sleep 1 # fixed sleep: a negative claim: nothing wakes the prompt by itself
    check "scale $scale: the prompt sleeps" state_is prompt_awake false
    screenshot_output_ppm WAYLAND-1 "asleep-$scale"
    wake_prompt || fail "scale $scale: the prompt did not wake"
    wait_settled WAYLAND-1
    screenshot_output_ppm WAYLAND-1 "awake-$scale"
    check "scale $scale: the prompt shows whole, inside the output" inside "asleep-$scale" "awake-$scale"
    type_text "$LOCKTEST_PASSWORD"
    press_key Return
    check_within 10 "scale $scale: the password unlocks" compositor_unlocked
done

# A small output beside it
before=$(output_scale WAYLAND-1 | cut -d' ' -f1)
monitor_rule WAYLAND-1 preferred 0x0 1
wait_until 3 scaled "$before" || abort "the scale 1 was not taken back"
hyprctl output create headless > /dev/null
wait_until 5 small_output || abort "no headless output"
small=$(small_output)
read -r _ main_width main_height <<< "$(output_scale WAYLAND-1)"
monitor_rule "$small" 300x260@60 "${main_width}x0" 1
wait_until 3 small_output_is 300 260 || abort "the small output did not take 300x260 (it is $(output_pixels "$small"))"
lock_by_ipc
check_within "$GUARD" "small: locked" compositor_locked
check_within "$GUARD" "small: two surfaces" state_is surfaces 2
wait_settled "$small"
screenshot_output_ppm "$small" asleep-small
moved=0
for attempt in 1 2 3 4 5; do
    send_input "abs $((main_width + 120 + attempt * 5)) 40 $((main_width + 300)) $main_height" "move 2 2" "click left"
    wait_until 0.5 state_is prompt_screen "$small" && { moved=1; break; }
done
check "small: a press on it brings the prompt there" test "$moved" = 1
wait_settled "$small"
screenshot_output_ppm "$small" awake-small
check "small: the prompt is narrowed to fit, whole" inside asleep-small awake-small
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "small: the password typed there unlocks" compositor_unlocked
