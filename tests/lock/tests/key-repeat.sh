# A held key repeats, as it should, through the key catcher — and the repeats are still
# reported as such (the rules ignore a held Escape's repeats, escape.sh):
#   a held Backspace deletes more than one character (the field is emptied, then the
#   password typed alone unlocks);
#   a held character types more than once (the password ending in a held "2" is wrong);
#   Escape held on a sleeping prompt wakes it, and its repeats do not hide it again (nor
#   unlock: Escape never does).

stack_start

lock_by_ipc
check_within "$GUARD" "locked" compositor_locked
check_within "$GUARD" "armed" state_is armed true
sleep 0.5 # fixed sleep: a negative claim: nothing wakes the prompt by itself
check "the prompt sleeps" state_is prompt_awake false

# Escape held: the first press wakes, the repeats count for nothing
hold_key Escape 1.5
check_within "$GUARD" "a held Escape wakes the prompt" state_is prompt_awake true
sleep 0.5 # fixed sleep: a negative claim: the repeats do not put it back to sleep
check "it stays awake: its repeats are reported as repeats, and ignored" state_is prompt_awake true
check "still locked" compositor_locked

# A held character repeats: the password with its last character held is not the password
type_text "${LOCKTEST_PASSWORD%?}"
hold_key "${LOCKTEST_PASSWORD: -1}" 1.5
press_key Return
check_within 10 "a held character typed more than once: rejected" state_is error "Authentication failed"
check "checked once, wrong" test "$(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)" = "wrong "
check "what PAM got was longer than the password" \
    test "$(password_details | tail -n 1 | cut -d' ' -f2)" -gt "${#LOCKTEST_PASSWORD}"

# A held Backspace deletes everything typed before it
type_text "xxxxxxxx"
hold_key BackSpace 2
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "after a held Backspace emptied the field, the password unlocks" compositor_unlocked
log "password checks: $(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)"
check "checked twice: wrong, right" test "$(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)" = "wrong right "
