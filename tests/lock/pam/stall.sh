#!@BASH@
# The silent module of pam/password-stall. pam_exec gives no PATH: builtins and coreutils by
# full path. Each run notes `start <pid> marker|nomarker` in stall/log (whether the marker
# module was there at this start), so a test can count the conversations and tell which
# said the marker.
#
# stall/mode says what it does:
#   before   at a start without the marker: links the marker module in for the next start,
#            then stays silent until its PAM helper is gone (Quickshell's abort() SIGKILLs
#            the helper and leaves this script behind; it ends within 0.1 s of that) or 120 s.
#            At a start with the marker: done at once.
#   after    the first run stays silent for stall/seconds (after the marker), then is done;
#            later runs are done at once.
# Anything else (no file): done at once.
directory=@WORK@/pam/stall
marker=@WORK@/pam/marker/pam_echo.so
log=$directory/log
read -r _ _ _ parent _ < /proc/$$/stat
mode=""
[ -e "$directory/mode" ] && read -r mode < "$directory/mode"
if [ -e "$marker" ]; then
    echo "start $$ marker" >> "$log"
else
    echo "start $$ nomarker" >> "$log"
fi
parent_is_alive() {
    local current_parent
    read -r _ _ _ current_parent _ < /proc/$$/stat
    [ "$current_parent" = "$parent" ]
}
case "$mode" in
    before)
        [ -e "$marker" ] && exit 0
        @COREUTILS@/ln -sf @PAM_MODULES@/pam_echo.so "$marker"
        for ((round = 0; round < 1200; round++)); do
            if ! parent_is_alive; then
                echo "orphaned $$" >> "$log"
                exit 1
            fi
            @COREUTILS@/sleep 0.1
        done
        echo "timeout $$" >> "$log"
        ;;
    after)
        [ -e "$directory/stalled" ] && exit 0
        : > "$directory/stalled"
        seconds=3
        [ -e "$directory/seconds" ] && read -r seconds < "$directory/seconds"
        for ((round = 0; round < seconds * 10; round++)); do
            parent_is_alive || { echo "orphaned $$" >> "$log"; exit 1; }
            @COREUTILS@/sleep 0.1
        done
        echo "done $$" >> "$log"
        ;;
esac
exit 0
