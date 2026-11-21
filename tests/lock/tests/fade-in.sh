# Nothing of the desktop shows through the lock: the lock surface is transparent and its
# scrim fades in (Theme "fade", 150 ms with the built-in theme), and the compositor must not
# show what is behind it. A stand-in desktop window (solid magenta, input/ltwindow.py) fills
# the output; the lock is requested and the screen photographed back to back from then on
# (compared afterwards: comparing is slow).
#
#   from the compositor's confirmation on (`secure`: ext-session-lock's `locked`, after
#   which the protocol forbids showing anything but the lock surfaces), no pixel of the
#   window shows, not even dimmed — every shot STARTED after a poll had seen `secure`
#   counts; at least three of them must;
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
now_us() { echo "${EPOCHREALTIME//[.,]/}"; }

window_shows() { screenshot_ppm desktop > /dev/null && [ "$(magenta_pixels desktop)" -gt 10000 ]; }
wait_until "$GUARD" window_shows
before=$(magenta_pixels desktop)
log "stand-in window pixels before the lock (every 7th sampled): $before"
[ "$before" -gt 10000 ] || abort "the stand-in window does not show before the lock"

# When the shell has the compositor's confirmation for sure: the END of the first poll
# that saw `secure` (it may have come at any moment during that poll; a shot started after
# the answer is after it — later than the confirmation by a poll's length at most)
rm -f "$WORK/secure-at"
(
    while :; do
        if [ "$(state_field secure 2> /dev/null)" = true ]; then
            polled=$(now_us)
            echo "$polled" > "$WORK/secure-at.tmp"
            mv "$WORK/secure-at.tmp" "$WORK/secure-at"
            break
        fi
    done
) &
poller=$!

shell_ipc lockscreen lock > /dev/null
requested=$(now_us)
for shot in $(seq 1 20); do
    started_at[$shot]=$(now_us)
    screenshot_ppm "fade-$shot"
done
check_within "$GUARD" "locked" compositor_locked
check_within "$GUARD" "confirmed" state_is secure true
wait_until 5 test -e "$WORK/secure-at" || fail "the poll never saw the confirmation"
kill "$poller" 2> /dev/null
wait "$poller" 2> /dev/null
secure_at=$(cat "$WORK/secure-at" 2> /dev/null || echo 0)
log "the confirmation seen by $(( (secure_at - requested) / 1000 )) ms after the lock request"

late=0 counted=0
for shot in $(seq 1 20); do
    count=$(magenta_pixels "fade-$shot")
    offset=$(( (started_at[$shot] - requested) / 1000 ))
    if [ "$secure_at" -gt 0 ] && [ "${started_at[$shot]}" -ge "$secure_at" ]; then
        counted=$((counted + 1))
        [ "$count" != 0 ] && late=1
        log "shot $shot, started ${offset} ms after the request (after the confirmation): stand-in window pixels $count"
    else
        log "shot $shot, started ${offset} ms after the request (before the confirmation was seen): stand-in window pixels $count"
    fi
done
check "from the compositor's confirmation on, nothing of the desktop shows" test "$late" = 0
check "at least three shots were taken after the confirmation ($counted)" test "$counted" -ge 3
