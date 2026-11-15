#!@BASH@
# The fingerprint stand-in's second line (pam/fingerprint): fails exactly when the round
# that just ended under the same PAM helper timed out (wait-finger.sh left
# timedout.<helper pid>), so that the stack ends in PAM's Error, as pam_fprintd's time-out
# does. pam_exec gives no PATH: builtins and full paths only.
directory=@FINGER_DIR@
read -r _ _ _ parent _ < /proc/$$/stat
if [ -e "$directory/timedout.$parent" ]; then
    @COREUTILS@/rm -f "$directory/timedout.$parent"
    echo "error $parent (the round timed out)" >> "$directory/log"
    exit 1
fi
exit 0
