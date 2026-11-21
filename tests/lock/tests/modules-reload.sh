# A reload while a command with a time limit runs (singletons/io/CommandRunner.qml). The
# shell's child is then coreutils' `timeout`, with the command under it; the old
# generation's runner is gone, so nothing of the shell will end that command later. Both
# must be gone with the generation that started them.
#
# The command here is the module host's file check, made to hang as in modules-hung: a
# `head` that sleeps, on the check's PATH only, under a 40 s deadline. After a reload in
# the same process the old check's `timeout` and its `sh` are gone well before either
# would end by itself, and the new generation runs a check of its own.
#
# What this does not show: which of the two ways ended the command — the runner's own
# KILL to the process group when it is destroyed, or the command dying with `timeout`
# (`setpriv --pdeathsig KILL`). The second alone is tested in tests/CommandRunnerTest.qml,
# where `timeout` is killed from outside.

standins=$WORK/hung-check
mkdir -p "$standins" || abort "cannot make $standins"
cat > "$standins/head" << 'SCRIPT'
#!/bin/sh
# A read that does not answer: longer than this test, then gives up
sleep 40 # fixed sleep: a stand-in that never answers
exit 1
SCRIPT
chmod +x "$standins/head"
good=$(cd "$LOCKTEST_SHELL/tests/fixtures/modules/good" && pwd -P) || abort "no good fixture in the copy"

stack_start --reload-seam --modules "$good" --shell-env H2S_SHELL_TEST_MODULE_CHECK_PATH="$standins" \
    --shell-env H2S_SHELL_TEST_MODULE_CHECK_MS=40000

# The file check's processes, by a sentence only its script holds: "<pid> <program>" each —
# `timeout`, whose arguments hold the script too, and the `sh` that runs it. The program is
# the first word of the command line without its directory: the process's name is not
# "timeout" where coreutils is one program for all its tools
check_processes() {
    local pid program
    for pid in $(test_pgrep -f "leaves the module directory through a link"); do
        program=$({ tr '\0' '\n' < "/proc/$pid/cmdline" | head -n 1; } 2> /dev/null)
        echo "$pid ${program##*/}"
    done
}
parent_of() { awk '{ print $4 }' "/proc/$1/stat" 2> /dev/null; }
# The newest `timeout` of a check, and the `sh` that is its child (the script's own
# subshells have the same arguments)
check_wrapper() { check_processes | awk '$2 == "timeout" { print $1 }' | sort -n | tail -n 1; }
check_command() {
    local wrapper pid
    wrapper=$(check_wrapper)
    [ -n "$wrapper" ] || return 1
    for pid in $(check_processes | awk '$2 != "timeout" { print $1 }'); do
        [ "$(parent_of "$pid")" = "$wrapper" ] && { echo "$pid"; return 0; }
    done
    return 1
}
check_runs() { [ -n "$(check_command)" ]; }
gone() { ! kill -0 "$1" 2> /dev/null; }
another_check_runs() { local pid; pid=$(check_command); [ -n "$pid" ] && [ "$pid" != "$1" ]; }

# end_and_check <what> <how the old generation ends>
end_and_check() {
    local what=$1 wrapper command
    shift
    check_within 15 "$what: the file check runs inside timeout" check_runs
    wrapper=$(check_wrapper)
    command=$(check_command)
    log "$what: timeout $wrapper, the check's sh $command"
    check "$what: the check's sh is timeout's child" test -n "$command"
    "$@"
    check_within 10 "$what: the old check's timeout is gone" gone "$wrapper"
    check_within 10 "$what: … and its sh with it (not left running without a limit)" gone "$command"
    check_within 15 "$what: the new shell runs a check of its own" another_check_runs "$command"
}

reload_in_place() {
    local reloads
    reloads=$(shell_log_count "Reloading configuration")
    shell_ipc locktest reload false > /dev/null
    check_within 10 "the shell reloaded" lines_more_than "$reloads" "Reloading configuration" "$WORK/shell.log"
    check "… in the same process" test "$(_find_shell_pid)" = "$SHELL_PID"
}

end_and_check "a reload" reload_in_place
check "no protocol error" no_protocol_errors
