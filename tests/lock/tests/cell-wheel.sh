# A bar cell under real wheel events: notches sent by a virtual pointer through the
# compositor, so the signs are Wayland's and Qt's as they come, not the ones a test made up.
# Wayland's horizontal axis is positive to the right, Qt's angleDelta.x positive to the
# left; the cell must report a wheel tilted right as scrollRight. The same for the vertical
# axis (positive down in Wayland): scrollDown. Not about the lock screen.

stack_start

cell_rect() { shell_ipc shelltest cellRect clock; }
cell_shown() { python3 -I -c 'import json,sys; r=json.loads(sys.argv[1]); sys.exit(0 if r.get("width",0) > 0 and r.get("height",0) > 0 else 1)' "$(cell_rect)"; }
wait_until "$GUARD" cell_shown || abort "the clock's cell is not in the bar"
rect=$(cell_rect)
log "the clock's cell: $rect"
cell_x=$(python3 -I -c 'import json,sys; r=json.loads(sys.argv[1]); print(r["x"] + r["width"] // 2)' "$rect")
cell_y=$(python3 -I -c 'import json,sys; r=json.loads(sys.argv[1]); print(r["y"] + r["height"] // 2)' "$rect")
move_pointer "$cell_x" "$cell_y"
check "the cell's interactions are watched" test -z "$(shell_ipc shelltest watchInteractions clock)"

# scrolls_are <names…>: the cell's interactions since it was watched, hover left out (the
# pointer coming over the cell is one, at a time of its own), in order
scrolls_are() {
    shell_ipc shelltest interactionsSeen | python3 -I -c '
import json, sys
seen = [name for name in json.load(sys.stdin) if name != "hover"]
sys.exit(0 if seen == sys.argv[1:] else 1)' "$@"
}

send_input "scroll horizontal 1"
check_within "$GUARD" "a wheel notch to the right is scrollRight" scrolls_are scrollRight
send_input "scroll horizontal -1"
check_within "$GUARD" "one to the left is scrollLeft" scrolls_are scrollRight scrollLeft
send_input "scroll vertical 1"
check_within "$GUARD" "one down is scrollDown" scrolls_are scrollRight scrollLeft scrollDown
send_input "scroll vertical -1"
check_within "$GUARD" "one up is scrollUp" scrolls_are scrollRight scrollLeft scrollDown scrollUp
