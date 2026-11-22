# Dead keys compose (a regression once: the key catcher was a plain Item, which takes
# no part in composition, so a dead key arrived as a key without text and vanished — a
# password with "é" typed as ´ then e was checked wrong, and "e" alone was accepted in its
# place). Layout us(intl): the apostrophe key is dead_acute. The password has an é in it.
#
#   the uncomposed base letter (e for é) is rejected;
#   dead_acute, then e: the é reaches PAM — the right bytes (length and hash), and it
#   unlocks;
#   a dead key followed by a letter it does not combine with, then corrected with Backspace,
#   does not leave anything behind.

LOCKTEST_PASSWORD="lt-café-1"
stack_start --keymap us-intl

lock_by_ipc
check_within "$GUARD" "locked" compositor_locked
check_within "$GUARD" "armed" state_is armed true
wake_prompt || fail "the prompt did not wake"

# The base letter alone: not the password
type_text "lt-cafe-1"
press_key Return
check_within 10 "the uncomposed letter (e for é) is rejected" state_is error "Authentication failed"
check "it was checked, and wrong" test "$(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)" = "wrong "
check "what PAM got was the plain e (9 bytes)" test "$(password_details | tail -n 1)" = "$(password_detail_of "lt-cafe-1")"
check "still locked" compositor_locked

# dead_acute, e: é
type_text "lt-caf"
press_key dead_acute
type_text "e-1"
press_key Return
check_within 10 "dead_acute then e types é, and the password unlocks" compositor_unlocked
log "password checks: $(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)"
check "PAM got exactly the password's bytes (é is two in UTF-8)" \
    test "$(password_details | tail -n 1)" = "$(password_detail_of "$LOCKTEST_PASSWORD")"
log "PAM got: $(password_details | tail -n 1 | cut -d' ' -f1-2)"

# Lock again: a dead key that combines with nothing typed, then fixed
lock_by_ipc
check_within "$GUARD" "locked again" compositor_locked
check_within "$GUARD" "armed again" state_is armed true
wake_prompt || fail "the prompt did not wake"
type_text "lt-caf"
press_key dead_acute
press_key dead_acute
press_key BackSpace
press_key dead_acute
type_text "e-1"
press_key Return
check_within 10 "a dead key pressed twice (´´), corrected with Backspace, then ´e: unlocks" compositor_unlocked
log "password checks: $(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)"
check "and PAM got the password's bytes" test "$(password_details | tail -n 1)" = "$(password_detail_of "$LOCKTEST_PASSWORD")"
