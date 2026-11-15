# A password beyond ASCII, end to end, typed with AltGr (us(intl): AltGr+s ß, AltGr+5 €,
# AltGr+p ö, AltGr+e é): each character of it reaches PAM as its UTF-8 bytes — checked by
# their length and hash (pam/check-detail.log; never the text) — and it unlocks. The same
# letters without AltGr are a different password.

LOCKTEST_PASSWORD="lt-ßö€é-7"
stack_start --keymap us-intl

lock_by_ipc
check_within 5 "locked" compositor_locked
check_within 5 "armed" state_is armed true
wake_prompt || fail "the prompt did not wake"

type_text "lt-sp5e-7"
press_key Return
check_within 10 "the same keys without AltGr are rejected" state_is error "Authentication failed"

type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the AltGr password unlocks" compositor_unlocked
log "password checks: $(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)"
check "checked twice: wrong, then right" test "$(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)" = "wrong right "
expected=$(password_detail_of "$LOCKTEST_PASSWORD")
check "PAM got the password's UTF-8 bytes (${expected%% sha256*})" test "$(password_details | tail -n 1)" = "$expected"
