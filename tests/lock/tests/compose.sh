# A Compose sequence reaches the password: the US layout with a Compose key on the right
# Alt (us-compose), the password with an é in it typed as Compose, ', e — composed by Qt
# from the locale's Compose table (the test bed fixes LANG=en_US.UTF-8). The Compose key
# alone types nothing.

LOCKTEST_PASSWORD="lt-café-1"
stack_start --keymap us-compose

lock_by_ipc
check_within 5 "locked" compositor_locked
check_within 5 "armed" state_is armed true
wake_prompt || fail "the prompt did not wake"

type_text "lt-caf"
press_key Multi_key
type_text "'e"
type_text "-1"
press_key Return
check_within 10 "Compose ' e types é, and the password unlocks" compositor_unlocked
log "password checks: $(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)"
check "PAM got exactly the password's bytes" test "$(password_details | tail -n 1)" = "$(password_detail_of "$LOCKTEST_PASSWORD")"

# A sequence abandoned half way: Compose, ' and then Backspace. Qt's compose (xkb) cancels
# the sequence — nothing of it is typed — and the Backspace still deletes as usual (the f
# before it, observed), so the f is typed again before the whole sequence
lock_by_ipc
check_within 5 "locked again" compositor_locked
check_within 5 "armed again" state_is armed true
wake_prompt || fail "the prompt did not wake"
type_text "lt-caf"
press_key Multi_key
type_text "'"
press_key BackSpace
type_text "f"
press_key Multi_key
type_text "'e-1"
press_key Return
check_within 10 "a sequence cancelled by Backspace leaves nothing behind; the whole one after it unlocks" compositor_unlocked
log "password checks: $(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)"
check "and PAM got the password's bytes" test "$(password_details | tail -n 1)" = "$(password_detail_of "$LOCKTEST_PASSWORD")"
