# The compositor dies (here: the nested Hyprland killed with SIGKILL, as by a crash) while
# the screen is locked. Its socket file stays behind; the launcher used to take "a socket
# file exists" for "the compositor is alive" and started the shell five times against a
# dead socket — and, had a compositor come back under the same name within its pauses, a
# shell of the old session on the new compositor. Now the launcher knows the socket it
# started under (device, inode, ctime) and that libwayland-server holds `<socket>.lock`
# while it serves it: nobody holding it, the compositor is gone and the launcher stops.
#
# Only the nested Hyprland of this run is killed, after checking that the pid is the child
# of the `timeout` this test spawned it under, runs the test bed's Hyprland binary and
# carries the run's marker.

stack_start --launcher-timings "first=0.5"

lock_by_ipc
check_within "$GUARD" "locked" compositor_locked
check "the marker says locked (a shell that dies would be restarted)" marker_file_is locked

socket=$RUN/wayland-1
hyprland=""
for pid in $(run_processes); do
    case "$(readlink -f "/proc/$pid/exe" 2> /dev/null)" in *[Hh]yprland*) ;; *) continue ;; esac
    tr '\0' ' ' < "/proc/$pid/cmdline" 2> /dev/null | grep -q -- "-c $WORK/hypr/hyprland.lua" || continue
    hyprland=$pid
    break
done
[[ "$hyprland" =~ ^[0-9]+$ ]] || abort "cannot find the nested Hyprland"
parent=$(awk '{ print $4 }' "/proc/$hyprland/stat")
tr '\0' ' ' < "/proc/$parent/cmdline" 2> /dev/null | grep -q "^timeout " || abort "pid $hyprland's parent is not the test's timeout: not killing it"
[ "$(process_env "$hyprland" LOCKTEST_RUN_ID)" = "$LOCKTEST_RUN_ID" ] || abort "pid $hyprland does not carry the run's marker: not killing it"
[ "$(process_env "$hyprland" XDG_RUNTIME_DIR)" = "$RUN" ] || abort "pid $hyprland is not in the private runtime dir: not killing it"
# … and runs the test bed's Hyprland: the program on the test's PATH, or the binary a
# wrapper of that name starts (beside it, as nixpkgs wraps programs)
hyprland_binary=$(readlink -f "$(type -P Hyprland)")
[ -e "$(dirname "$hyprland_binary")/.Hyprland-wrapped" ] && hyprland_binary=$(readlink -f "$(dirname "$hyprland_binary")/.Hyprland-wrapped")
[ "$(readlink -f "/proc/$hyprland/exe")" = "$hyprland_binary" ] || abort "pid $hyprland does not run the test bed's Hyprland ($hyprland_binary): not killing it"
supervisor=$SUPERVISOR_PID
kill -KILL "$hyprland"
log "killed the nested Hyprland (pid $hyprland)"
check_within 10 "the launcher stops: the compositor is gone" grep -aq "the compositor is gone: not starting" "$WORK/shell.log"
check "it said why: nobody holds the socket's lock" grep -aq "nobody holds $socket.lock: the compositor is dead" "$WORK/shell.log"
check_within "$GUARD" "the launcher ended" test ! -e "/proc/$supervisor"
check "the socket file was left behind (what fooled the old check)" test -S "$socket"
check "no restart was attempted" test "$(shell_log_count "starting it again in")" = 0
check "no shell of this run is left" test -z "$(_find_shell_pid)"
