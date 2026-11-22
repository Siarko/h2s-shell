# The single key catcher keeps the keys after pointer
# presses — on the field, on the Unlock button, on empty space, before and after waking —
# and the password typed by keys then unlocks.

stack_start

lock_by_ipc
check_within "$GUARD" "locked" compositor_locked
check_within "$GUARD" "armed" state_is armed true
sleep 0.5 # fixed sleep: the new lock surface ignores the pointer in its first 300 ms: the first click must count
for spot in "960 540" "960 600" "960 480" "100 100" "1800 1000"; do
    send_input "abs ${spot% *} ${spot#* } 1920 1080" "move 1 1" "click left"
    sleep 0.2 # fixed sleep: clicks apart, each a press of its own, not a double click
done
check_within "$GUARD" "the prompt is awake after the presses" state_is prompt_awake true
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "keys typed after clicking around still reach the field and unlock" compositor_unlocked
log "password checks: $(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)"
check "it was checked once, and right" test "$(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)" = "right "
