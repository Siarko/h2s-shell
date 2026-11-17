# The methods script itself (scripts/lock-auth-methods.sh, the run's copy), run directly —
# no compositor, no shell: what it answers and with which exit status, for each thing
# fprintd can do and for where pam_u2f keeps keys. fprintd is a stand-in behind a stand-in
# gdbus (H2S_LOCK_TOOLS), the system-wide configs a directory of this test's
# (H2S_LOCK_SYSTEM_PAM_DIR), the user's config folder a private one (XDG_CONFIG_HOME). The
# system bus address leads nowhere (lib.sh), so nothing here can reach the real fprintd.
#
# The contract (notes/plans/lockscreen.md, section 7): exit 0 is an answer, also "not
# here"; non-zero when a question could not be answered — within the shell's 5 s, with the
# lines it could answer printed first.

script=$LOCKTEST_SHELL/scripts/lock-auth-methods.sh
user=$(id -un)
tab=$'\t'
sys=$WORK/system-script
tools=$WORK/script-tools
xdg=$WORK/script-xdg
mkdir -p "$sys" "$tools" "$xdg/Yubico" "$WORK/u2f"
_write_fprintd_standin "$tools"
ln -sf gdbus-fprintd "$tools/gdbus"
echo "auth required /nowhere/pam_deny.so" > "$sys/h2s-shell-password"
echo "auth required /nowhere/pam_fprintd.so" > "$sys/h2s-shell-fingerprint"

# run_script: runs it once; OUTPUT, STATUS, ELAPSED (ms), the stderr in $WORK/script.err
run_script() {
    local started=${EPOCHREALTIME//[.,]/}
    OUTPUT=$(env -u H2S_LOCK_AUTH_METHODS H2S_LOCK_TOOLS="$tools" H2S_LOCK_SYSTEM_PAM_DIR="$sys" \
        XDG_CONFIG_HOME="$xdg" timeout 20 "$script" 2> "$WORK/script.err")
    STATUS=$?
    ELAPSED=$(( (${EPOCHREALTIME//[.,]/} - started) / 1000 ))
    log "mode $(cat "$WORK/fprintd/mode"): status $STATUS in $ELAPSED ms: $(printf '%s' "$OUTPUT" | tr '\t\n' ' |') $(head -c 300 "$WORK/script.err" | tr '\n' ' ')"
}
has_line() { grep -qxF -- "$1" <<< "$OUTPUT"; }
lacks_method() { ! grep -q "^$1$tab" <<< "$OUTPUT"; }
status_is() { [ "$STATUS" = "$1" ]; }
status_nonzero() { [ "$STATUS" != 0 ]; }
within() { [ "$ELAPSED" -lt "$1" ]; }
quiet() { [ ! -s "$WORK/script.err" ]; }
says() { grep -q -- "$1" "$WORK/script.err"; }
password_line="password$tab$sys${tab}h2s-shell-password"
fingerprint_line="fingerprint$tab$sys${tab}h2s-shell-fingerprint"

# ---- fingerprint -------------------------------------------------------------------
fprintd_mode enrolled
run_script
check "enrolled: fingerprint offered" has_line "$fingerprint_line"
check "enrolled: the password line" has_line "$password_line"
check "enrolled: exit 0" status_is 0
check "enrolled: nothing on stderr" quiet
check "fprintd is asked for the caller (an empty user name), never a named user" \
    grep -q "call ListEnrolledFingers user='' " "$WORK/fprintd/log"
no_named_user() { ! grep 'ListEnrolledFingers' "$WORK/fprintd/log" | grep -qv "user='' "; }
check "no call names a user" no_named_user

fprintd_mode second
run_script
check "a finger on the second reader: offered" has_line "$fingerprint_line"
check "a finger on the second reader: exit 0" status_is 0

for mode in none nodevice absent; do
    fprintd_mode "$mode"
    run_script
    check "$mode: fingerprint not offered" lacks_method fingerprint
    check "$mode: the password line" has_line "$password_line"
    check "$mode: exit 0 (an answer: not here)" status_is 0
    check "$mode: nothing on stderr" quiet
done

for mode in denied nobus malformed-devices malformed-fingers; do
    fprintd_mode "$mode"
    run_script
    check "$mode: fingerprint not offered" lacks_method fingerprint
    check "$mode: the password line still printed" has_line "$password_line"
    check "$mode: exit non-zero (the question was not answered)" status_nonzero
    check "$mode: says why" says "cannot tell whether a finger is enrolled"
done

fprintd_mode hang
run_script
check "hang: fingerprint not offered" lacks_method fingerprint
check "hang: the password line still printed" has_line "$password_line"
check "hang: exit non-zero" status_nonzero
check "hang: done within the shell's 5 s detection time" within 5000
check "hang: says it timed out" says "timeout"
sleeper=$(sed -n 's/^    hang) exec \([^ ]*\) 120 ;;$/\1/p' "$tools/gdbus-fprintd")
no_sleeper() { [ -n "$sleeper" ] && ! test_pgrep -fx "$sleeper 120" > /dev/null; }
check "hang: the stuck call does not linger" no_sleeper

# gdbus's stderr is not its reply: a GLib warning on a call that succeeded changes nothing
fprintd_mode warning
run_script
check "warning on gdbus's stderr, good reply: fingerprint offered" has_line "$fingerprint_line"
check "warning on gdbus's stderr, good reply: exit 0" status_is 0

# gdbus's own time-out (its --timeout ran out) is a time-out, said so
fprintd_mode gdbus-timeout
run_script
check "gdbus-timeout: fingerprint not offered" lacks_method fingerprint
check "gdbus-timeout: exit non-zero" status_nonzero
check "gdbus-timeout: says it timed out" says "GetDevices: timeout"

# A reader that vanishes between GetDevices and ListEnrolledFingers: a failure
fprintd_mode vanished
run_script
check "vanished: fingerprint not offered" lacks_method fingerprint
check "vanished: exit non-zero (asked again later)" status_nonzero
check "vanished: says why" says "ListEnrolledFingers (/net/reactivated/Fprint/Device/0): error org.freedesktop.DBus.Error.UnknownObject"

# An error of several lines is one line of reason (the shell logs each stderr line)
fprintd_mode multiline
run_script
check "multiline: exit non-zero" status_nonzero
check "multiline: the reason is one line" test "$(grep -c . "$WORK/script.err")" = 1

empty_tools=$WORK/no-tools
mkdir -p "$empty_tools"
fprintd_mode enrolled
OUTPUT=$(env -u H2S_LOCK_AUTH_METHODS H2S_LOCK_TOOLS="$empty_tools" H2S_LOCK_SYSTEM_PAM_DIR="$sys" \
    XDG_CONFIG_HOME="$xdg" timeout 20 "$script" 2> "$WORK/script.err")
STATUS=$?
check "no gdbus: exit non-zero" status_nonzero
check "no gdbus: the password line printed" has_line "$password_line"

# The shipped fingerprint config cannot load pam_fprintd on NixOS: without a system-wide
# one the method is not offered there, and fprintd is not even asked
if [ -e /etc/NIXOS ]; then
    mv "$sys/h2s-shell-fingerprint" "$sys/h2s-shell-fingerprint.off"
    calls_before=$(grep -c . "$WORK/fprintd/log")
    run_script
    check "NixOS without a system-wide fingerprint config: not offered" lacks_method fingerprint
    check "NixOS without a system-wide fingerprint config: fprintd not asked" \
        test "$(grep -c . "$WORK/fprintd/log")" = "$calls_before"
    check "NixOS without a system-wide fingerprint config: exit 0" status_is 0
    mv "$sys/h2s-shell-fingerprint.off" "$sys/h2s-shell-fingerprint"
fi

# ---- password ------------------------------------------------------------------------
mv "$sys/h2s-shell-password" "$sys/h2s-shell-password.off"
run_script
if [ -e /etc/NIXOS ]; then
    check "no system-wide password config on NixOS: login (as the shell's fallback)" \
        has_line "password$tab$sys${tab}login"
else
    check "no system-wide password config: the shipped one" \
        has_line "password$tab$LOCKTEST_SHELL/pam${tab}password"
fi
mv "$sys/h2s-shell-password.off" "$sys/h2s-shell-password"

# ---- u2f -----------------------------------------------------------------------------
fprintd_mode absent
u2f_line="u2f$tab$sys${tab}h2s-shell-u2f"
keys=$xdg/Yubico/u2f_keys

echo "auth required /nowhere/pam_u2f.so cue" > "$sys/h2s-shell-u2f"
printf '%s:khandle,pubkey,es256,+presence\n' "$user" > "$keys"
run_script
check "u2f: a key in \$XDG_CONFIG_HOME/Yubico/u2f_keys: offered" has_line "$u2f_line"
check "u2f: exit 0" status_is 0

: > "$keys"
run_script
check "u2f: an empty u2f_keys: not offered" lacks_method u2f
printf 'somebody-else:khandle,pubkey,es256,+presence\n' > "$keys"
run_script
check "u2f: keys of another user only: not offered" lacks_method u2f
check "u2f: not offered is an answer (exit 0)" status_is 0

printf '%s:khandle,pubkey,es256,+presence\n' "$user" > "$keys"
chmod 000 "$keys"
run_script
check "u2f: a file the user cannot read: not offered" lacks_method u2f
chmod 600 "$keys"
rm -f "$keys"

printf 'somebody-else:a,b\n%s:khandle,pubkey,es256,+presence\n' "$user" > "$WORK/u2f/mappings"
echo "auth sufficient /nowhere/pam_u2f.so authfile=$WORK/u2f/mappings cue" > "$sys/h2s-shell-u2f"
run_script
check "u2f: the user in a central authfile=: offered (no u2f_keys needed)" has_line "$u2f_line"
printf 'somebody-else:a,b\n' > "$WORK/u2f/mappings"
run_script
check "u2f: a central authfile= without the user: not offered" lacks_method u2f

printf '%s:khandle,pubkey,es256,+presence\n' "$user" > "$WORK/u2f/$user.keys"
echo "auth required /nowhere/pam_u2f.so authfile=$WORK/u2f/%u.keys expand cue" > "$sys/h2s-shell-u2f"
run_script
check "u2f: authfile= with %u and expand: offered" has_line "$u2f_line"
echo "auth required /nowhere/pam_u2f.so authfile=$WORK/u2f/%u.keys cue" > "$sys/h2s-shell-u2f"
run_script
check "u2f: %u without expand is taken literally: not offered" lacks_method u2f

echo "auth required /nowhere/pam_unix.so" > "$sys/h2s-shell-u2f"
printf '%s:khandle,pubkey,es256,+presence\n' "$user" > "$keys"
run_script
check "u2f: a config without pam_u2f: not offered" lacks_method u2f

# The config's words are not patterns: `authfile=…/k*` names a file called "k*", not
# whatever the shell would match against the current directory
mkdir -p "$WORK/glob-cwd/authfile=$WORK/u2f"
: > "$WORK/glob-cwd/authfile=$WORK/u2f/k-matched"
printf '%s:khandle,pubkey,es256,+presence\n' "$user" > "$WORK/u2f/k*"
echo "auth required /nowhere/pam_u2f.so authfile=$WORK/u2f/k* cue" > "$sys/h2s-shell-u2f"
OUTPUT=$(cd "$WORK/glob-cwd" && env -u H2S_LOCK_AUTH_METHODS H2S_LOCK_TOOLS="$tools" H2S_LOCK_SYSTEM_PAM_DIR="$sys" \
    XDG_CONFIG_HOME="$xdg" timeout 20 "$script" 2> "$WORK/script.err")
check "u2f: authfile= with a * is taken literally, not expanded against the current directory" has_line "$u2f_line"
rm -f "$WORK/u2f/k*"

# The user name is matched literally: a name with a dot is no pattern
mkdir -p "$WORK/fake-id"
printf '#!%s\necho "a.b"\n' "$(command -v bash)" > "$WORK/fake-id/id"
chmod +x "$WORK/fake-id/id"
echo "auth required /nowhere/pam_u2f.so cue" > "$sys/h2s-shell-u2f"
printf 'axb:khandle,pubkey,es256,+presence\n' > "$keys"
OUTPUT=$(env -u H2S_LOCK_AUTH_METHODS PATH="$WORK/fake-id:$PATH" H2S_LOCK_TOOLS="$tools" H2S_LOCK_SYSTEM_PAM_DIR="$sys" \
    XDG_CONFIG_HOME="$xdg" timeout 20 "$script" 2> "$WORK/script.err")
check "u2f: user a.b, keys only for axb: not offered (the name is no pattern)" lacks_method u2f
printf 'a.b:khandle,pubkey,es256,+presence\n' > "$keys"
OUTPUT=$(env -u H2S_LOCK_AUTH_METHODS PATH="$WORK/fake-id:$PATH" H2S_LOCK_TOOLS="$tools" H2S_LOCK_SYSTEM_PAM_DIR="$sys" \
    XDG_CONFIG_HOME="$xdg" timeout 20 "$script" 2> "$WORK/script.err")
check "u2f: user a.b with a key: offered" has_line "$u2f_line"
printf '%s:khandle,pubkey,es256,+presence\n' "$user" > "$keys"

if [ -e /etc/NIXOS ]; then
    rm -f "$sys/h2s-shell-u2f"
    run_script
    check "u2f: NixOS without a system-wide u2f config: not offered, keys or not" lacks_method u2f
fi
check "u2f checks: the fingerprint question stayed 'not here'" status_is 0
