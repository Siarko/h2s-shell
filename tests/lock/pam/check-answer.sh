#!@BASH@
# The second check of the "password-question" stack: the answer to its question arrives
# on standard input (pam_stress stored it as the auth token), NUL-terminated. Each run
# leaves "answer-right" or "answer-wrong" in check.log, never what was typed.
IFS= read -r -d '' token || true
token=${token%$'\n'}
if [ "$token" = "@ANSWER@" ]; then
    echo answer-right >> "@WORK@/pam/check.log"
    exit 0
fi
echo answer-wrong >> "@WORK@/pam/check.log"
exit 1
