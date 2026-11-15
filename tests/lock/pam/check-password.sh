#!@BASH@
# Run by pam_exec with expose_authtok: the typed password arrives on standard input,
# NUL-terminated. pam_exec gives no PATH, so only builtins are used.
IFS= read -r -d '' token || true
token=${token%$'\n'}
[ "$token" = "@PASSWORD@" ]
