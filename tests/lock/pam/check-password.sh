#!@BASH@
# Run by pam_exec with expose_authtok: the typed password arrives on standard input,
# NUL-terminated. pam_exec gives no PATH, so only builtins are used (and coreutils, by full
# path). Each run leaves a line in check.log ("right" or "wrong", never what was
# typed), so that a test can tell a rejected password from a script that never ran.
#
# Slow on request: while the file `slow` exists in this directory, each check waits for
# a file `release` (which it consumes) before answering, up to 30 s — so that a test can
# act while a verification is under way. Without `slow` it answers at once.
IFS= read -r -d '' token || true
token=${token%$'\n'}
# What arrived, to tell bytes apart (a password with é in it): its length in bytes and its
# SHA-256 — never the text. pam_exec gives no locale, so ${#token} counts bytes.
sum=$(printf '%s' "$token" | @COREUTILS@/sha256sum)
echo "length ${#token} sha256 ${sum%% *}" >> "@WORK@/pam/check-detail.log"
if [ -e "@WORK@/pam/slow" ]; then
    echo waiting >> "@WORK@/pam/check.log"
    for ((round = 0; round < 300; round++)); do
        [ -e "@WORK@/pam/release" ] && break
        @COREUTILS@/sleep 0.1
    done
    @COREUTILS@/rm -f "@WORK@/pam/release"
fi
if [ "$token" = "@PASSWORD@" ]; then
    echo right >> "@WORK@/pam/check.log"
    exit 0
fi
echo wrong >> "@WORK@/pam/check.log"
exit 1
