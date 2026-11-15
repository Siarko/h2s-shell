# A middle click pastes the primary selection into a Qt text input — and the lock surface
# has two: the hidden key catcher (it was a 1×1 TextInput at the surface's top-left pixel)
# and the prompt's field. Whatever was last selected on the desktop must never land in the
# password. The surface's MouseArea keeps every button but the left from what is under it,
# and the catcher lies outside the surface (LockSurface.qml).
#
# The primary selection is set inside the nested compositor (wl-copy --primary, through
# its data-control protocol) while the lock is in force; then middle clicks at the top-left
# pixel, across the prompt (the field among it) and elsewhere; then the password is typed:
# PAM must get exactly the password, nothing pasted before it.

stack_start
lock_by_ipc
check_within 5 "locked" compositor_locked
check_within 5 "armed" state_is armed true

pasted="lt-PASTED-from-the-desktop"
wl-copy --primary "$pasted" 2> "$WORK/wl-copy.log"
sleep 0.5
check "the primary selection holds the text (the test bed can set it while locked)" \
    test "$(timeout 5 wl-paste --primary --no-newline 2> /dev/null)" = "$pasted"

wake_prompt || fail "the prompt did not wake"
# The top-left pixel (where the catcher was), then down the middle of the screen through
# the prompt (the field, the Unlock button), then a corner
for spot in "0 0" "1 1" $(for y in $(seq 380 12 700); do echo "960_$y"; done) "1900 1060"; do
    spot=${spot/_/ }
    send_input "abs ${spot% *} ${spot#* } 1920 1080" "click middle"
done
send_input "abs 0 0 1920 1080" "click middle"
sleep 0.5
check "the prompt is still awake" state_is prompt_awake true
check "nothing was submitted by the clicks" test ! -s "$WORK/pam/check.log"

type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password alone unlocks: nothing was pasted into the field" compositor_unlocked
check "PAM got exactly the password" test "$(password_details | tail -n 1)" = "$(password_detail_of "$LOCKTEST_PASSWORD")"
