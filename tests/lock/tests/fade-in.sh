# Nothing of the desktop shows through the lock: the lock surface is transparent and its
# scrim fades in (Theme "fade", 150 ms with the built-in theme), and the compositor must not
# show what is behind it. A stand-in desktop window (solid magenta, input/ltwindow.py) fills
# the output; the lock is requested and the screen photographed back to back from then on
# (compared afterwards: comparing is slow).
#
#   from 300 ms after the request on (the compositor's confirmation, then the fade), no
#   pixel of the window shows, not even dimmed;
#   what shows before that is logged (Hyprland draws nothing of the desktop once the lock
#   is in force, so the fade is from black, not from the desktop).

stack_start --window

# magenta_pixels <name>: pixels of the stand-in window in a screenshot — magenta at any
# brightness (dimmed by a scrim that is not yet opaque, too)
magenta_pixels() {
    python3 -I -c "$_PPM_READER"'
width, height, pixels = read_ppm(sys.argv[1])
count = 0
for offset in range(0, width * height * 3, 3 * 7):
    red, green, blue = pixels[offset], pixels[offset + 1], pixels[offset + 2]
    if red > 24 and blue > 24 and green * 3 < red and green * 3 < blue:
        count += 1
print(count)' "$WORK/$1.ppm"
}

sleep 1
screenshot_ppm desktop
before=$(magenta_pixels desktop)
log "stand-in window pixels before the lock (every 7th sampled): $before"
[ "$before" -gt 10000 ] || abort "the stand-in window does not show before the lock"

shell_ipc lockscreen lock > /dev/null
requested=${EPOCHREALTIME//[.,]/}
for shot in $(seq 1 15); do
    screenshot_ppm "fade-$shot"
    offsets[$shot]=$(( (${EPOCHREALTIME//[.,]/} - requested) / 1000 ))
done
check_within 5 "locked" compositor_locked
check_within 5 "confirmed" state_is secure true

late=0
for shot in $(seq 1 15); do
    count=$(magenta_pixels "fade-$shot")
    log "${offsets[$shot]} ms after the lock request: stand-in window pixels $count"
    if [ "${offsets[$shot]}" -ge 300 ] && [ "$count" != 0 ]; then late=1; fi
done
check "from 300 ms after the request on, nothing of the desktop shows" test "$late" = 0
check "the last shot was taken past 300 ms" test "${offsets[15]}" -ge 300
