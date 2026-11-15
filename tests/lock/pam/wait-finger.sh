#!@BASH@
# The fingerprint stand-in: one run of this script is one "finger on the reader" round.
# pam_exec gives no PATH, so everything outside bash's builtins is called by full path.
#
# It announces itself with the file waiting.<pid> and waits for result.<pid> (written by
# the test: "ok" or anything else), which it consumes. A trigger is thus addressed to one
# conversation and used once.
#
# Why not one shared trigger file: Quickshell's PamContext.abort() kills its PAM helper
# with SIGKILL, without pam_end, and pam_exec's child — this script — survives as an
# orphan. An orphan polling a shared file would eat the next trigger meant for the live
# conversation. So besides the per-run file, the script watches its parent (the PAM
# helper) and gives up as soon as it is re-parented: an aborted round ends within 0.1 s
# and can never answer for a later one. The parent is checked to be Quickshell's PAM
# helper when the script starts (a helper killed before that would leave the script
# with a subreaper as its parent from the first look), and again right before an answer
# is taken.
directory=@FINGER_DIR@
log=$directory/log
waiting=$directory/waiting.$$
result=$directory/result.$$
read -r _ _ _ parent _ < /proc/$$/stat
parent_binary=$(@COREUTILS@/readlink -f "/proc/$parent/exe" 2> /dev/null)
if [ "$parent_binary" != "@QS_BINARY@" ]; then
    echo "orphaned $$ (parent $parent is not a Quickshell PAM helper: ${parent_binary:-gone})" >> "$log"
    exit 1
fi
echo "start $$ parent $parent" >> "$log"
: > "$waiting"
trap '@COREUTILS@/rm -f "$waiting"' EXIT
parent_is_alive() {
    local current_parent
    read -r _ _ _ current_parent _ < /proc/$$/stat
    [ "$current_parent" = "$parent" ]
}
for ((round = 0; round < 1200; round++)); do
    if ! parent_is_alive; then
        echo "orphaned $$ (parent $parent gone)" >> "$log"
        exit 1
    fi
    if [ -e "$result" ]; then
        read -r answer < "$result"
        @COREUTILS@/rm -f "$result"
        echo "result $$ $answer" >> "$log"
        [ "$answer" = ok ]
        exit
    fi
    @COREUTILS@/sleep 0.1
done
echo "timeout $$" >> "$log"
exit 1
