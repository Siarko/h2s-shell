#!@BASH@
# Run by pam_exec with expose_authtok: the typed password arrives on standard input,
# NUL-terminated. pam_exec gives no PATH, so only builtins are used. Each run leaves a
# line in check.log ("right" or "wrong", never what was typed), so that a test can tell
# a rejected password from a script that never ran.
IFS= read -r -d '' token || true
token=${token%$'\n'}
if [ "$token" = "@PASSWORD@" ]; then
    echo right >> "@WORK@/pam/check.log"
    exit 0
fi
echo wrong >> "@WORK@/pam/check.log"
exit 1
