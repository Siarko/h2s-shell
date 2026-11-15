# The prompt on a scaled and on a small output: whole, inside the screen, and working.
#
#   WAYLAND-1 at a fractional scale (1.5: 1280x720 logical) and at scale 3 (640x360
#   logical): the prompt woken there shows wholly inside the output (what changed against
#   the asleep screen does not touch its edges), and the password typed there unlocks;
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
scaled() { [ "$(output_scale WAYLAND-1 | cut -d' ' -f1)" != "$1" ]; }

# Hyprland takes the nearest scale that divides the mode evenly: what it took is logged
for scale in 1.5 3; do
    before=$(output_scale WAYLAND-1 | cut -d' ' -f1)
    monitor_rule WAYLAND-1 preferred 0x0 "$scale"
    wait_until 3 scaled "$before" || abort "the scale $scale was not taken"
    log "asked for scale $scale: WAYLAND-1 is now (scale, logical size) $(output_scale WAYLAND-1)"
    lock_by_ipc
    check_within 5 "scale $scale: locked" compositor_locked
    sleep 1
    check "scale $scale: the prompt sleeps" state_is prompt_awake false
    screenshot_output_ppm WAYLAND-1 "asleep-$scale"
    wake_prompt || fail "scale $scale: the prompt did not wake"
    sleep 0.5
    screenshot_output_ppm WAYLAND-1 "awake-$scale"
    check "scale $scale: the prompt shows whole, inside the output" inside "asleep-$scale" "awake-$scale"
    type_text "$LOCKTEST_PASSWORD"
    press_key Return
    check_within 10 "scale $scale: the password unlocks" compositor_unlocked
done

# A small output beside it
monitor_rule WAYLAND-1 preferred 0x0 1
hyprctl output create headless > /dev/null
wait_until 5 test -n "$(hyprctl -j monitors | python3 -I -c 'import json,sys; print(" ".join(m["name"] for m in json.load(sys.stdin) if m["name"].startswith("HEADLESS")))')" \
    || abort "no headless output"
small=$(hyprctl -j monitors | python3 -I -c 'import json,sys; print([m["name"] for m in json.load(sys.stdin) if m["name"].startswith("HEADLESS")][0])')
read -r _ main_width main_height <<< "$(output_scale WAYLAND-1)"
monitor_rule "$small" 300x260@60 "${main_width}x0" 1
wait_until 3 test "$(hyprctl -j monitors | python3 -I -c 'import json,sys,os; print([m["width"] for m in json.load(sys.stdin) if m["name"] == sys.argv[1]][0])' "$small")" = 300 \
    || abort "the small output did not take 300x260"
lock_by_ipc
check_within 5 "small: locked" compositor_locked
check_within 5 "small: two surfaces" state_is surfaces 2
sleep 1
screenshot_output_ppm "$small" asleep-small
moved=0
for attempt in 1 2 3 4 5; do
    send_input "abs $((main_width + 120 + attempt * 5)) 40 $((main_width + 300)) $main_height" "move 2 2" "click left"
    wait_until 0.5 state_is prompt_screen "$small" && { moved=1; break; }
done
check "small: a press on it brings the prompt there" test "$moved" = 1
sleep 0.5
screenshot_output_ppm "$small" awake-small
check "small: the prompt is narrowed to fit, whole" inside asleep-small awake-small
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "small: the password typed there unlocks" compositor_unlocked
