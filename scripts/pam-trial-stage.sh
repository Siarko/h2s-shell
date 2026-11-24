#!/usr/bin/env bash
# The PAM trial's staging directory (singletons/io/PamTrial.qml): a private copy of a
# candidate PAM service and of the files it includes, which one PAM conversation then runs
# as the user. Which files, their texts and the directory's name are PamTrialRules'
# decision; this only writes and removes.
#
#   pam-trial-stage.sh stage <parent> <directory> <owner> <name> <text> [<name> <text> ...]
#       makes <directory> (mode 0700) with each file (mode 0600, the text exactly as
#       given) and prints "staged TAB <directory>"; a directory that is already there is
#       an error, never reused. <owner> is the pid of the shell the trial is for: its pid
#       and start time (field 22 of /proc/<pid>/stat, which a reused pid does not share)
#       are written first, as "<pid> <start>" in <directory>/.owner (a name no PAM
#       service can have)
#   pam-trial-stage.sh remove <parent> <directory>
#       removes <directory>; one already gone is no error
#   pam-trial-stage.sh sweep <parent>
#       removes, as `remove` does, each staging directory in <parent> whose .owner names a
#       process no longer running (no such pid, or one started at another time), printing
#       "removed TAB <directory>" for each: one a shell left behind (killed mid-trial). One
#       without a readable .owner (being staged, or not the shell's) is left alone, as is
#       one of a running shell — another instance's, or a test run's
#
# <parent> is an absolute directory of this user's (the runtime directory), written plainly:
# no "." or ".." part, no "//", no trailing "/". <directory> is exactly
# <parent>/h2s-pam-trial.XXXXXXXX (eight letters or digits), and is removed only as a
# directory of this user's, never through a link. A name is what libpam takes as a service
# name: no "/", no leading dot. A text holds no control character but line breaks and tabs.
# Nothing runs as root; nothing outside <directory> is written.
set -u
export LC_ALL=C
umask 077

fail() {
    echo "pam-trial-stage: $*" >&2
    exit 1
}

valid_name() {
    [[ "$1" =~ ^[A-Za-z0-9_][A-Za-z0-9._@+-]*$ ]] && [ "${#1}" -le 255 ]
}

# check_parent <parent>: as described above, there and ours
check_parent() {
    local parent=$1
    [[ "$parent" =~ ^(/[^/]+)+$ ]] || fail "not a plain absolute path: $parent"
    case "/$parent/" in
        */./* | */../*) fail "a . or .. in the parent: $parent" ;;
    esac
    [ -d "$parent" ] && [ ! -L "$parent" ] && [ -O "$parent" ] || fail "the parent is not a directory of this user's: $parent"
}

# check_places <parent> <directory>: both as described above
check_places() {
    local parent=$1 directory=$2
    check_parent "$parent"
    [ "$directory" = "$parent/${directory##*/}" ] || fail "not directly in $parent: $directory"
    [[ "${directory##*/}" =~ ^h2s-pam-trial\.[A-Za-z0-9]{8}$ ]] || fail "not a staging directory's name: $directory"
}

# start_of <pid>: the process's start time (field 22 of its stat), or fails when it is not
# running. The command name (field 2) is in parentheses and may hold spaces: read after it.
start_of() {
    local stat
    [[ "$1" =~ ^[1-9][0-9]{0,9}$ ]] || return 1
    stat=$(cat "/proc/$1/stat" 2> /dev/null) || return 1
    stat=${stat##*) }
    # shellcheck disable=SC2086  # split into its fields on purpose
    set -- $stat
    [ $# -ge 20 ] && [[ "${20}" =~ ^[0-9]{1,20}$ ]] || return 1
    printf '%s' "${20}"
}

# remove_directory <parent> <directory>: `remove`, both checked already
remove_directory() {
    local directory=$2
    [ -e "$directory" ] || [ -L "$directory" ] || return 0
    [ -d "$directory" ] && [ ! -L "$directory" ] && [ -O "$directory" ] || fail "not a staging directory of this user's: $directory"
    rm -rf -- "$directory" || fail "cannot remove $directory"
}

case "${1:-}" in
    stage)
        [ $# -ge 6 ] || fail "usage: stage <parent> <directory> <owner> <name> <text> [<name> <text> ...]"
        parent=$2 directory=$3 owner=$4
        shift 4
        check_places "$parent" "$directory"
        start=$(start_of "$owner") || fail "the owner is not a running process: $owner"
        [ $(($# % 2)) -eq 0 ] || fail "names and texts do not pair up"
        files=("$@")
        for ((i = 0; i < ${#files[@]}; i += 2)); do
            valid_name "${files[i]}" || fail "not a file name: ${files[i]}"
            for ((j = 0; j < i; j += 2)); do
                [ "${files[j]}" != "${files[i]}" ] || fail "a name given twice: ${files[i]}"
            done
            case "${files[i + 1]}" in
                *[$'\001'-$'\010'$'\013'-$'\037'$'\177']*) fail "a control character in ${files[i]}" ;;
            esac
        done
        mkdir -m 700 -- "$directory" || fail "cannot make $directory"
        # Until the directory is reported, it goes with this script, however it ends (but KILL)
        trap 'rm -rf -- "$directory"' EXIT
        trap 'exit 1' TERM INT HUP
        printf '%s %s\n' "$owner" "$start" > "$directory/.owner" || fail "cannot write the owner"
        for ((i = 0; i < ${#files[@]}; i += 2)); do
            printf '%s' "${files[i + 1]}" > "$directory/${files[i]}" || fail "cannot write ${files[i]}"
        done
        printf 'staged\t%s\n' "$directory" || fail "cannot report $directory"
        trap - EXIT
        ;;
    remove)
        [ $# -eq 3 ] || fail "usage: remove <parent> <directory>"
        parent=$2 directory=$3
        check_places "$parent" "$directory"
        remove_directory "$parent" "$directory"
        ;;
    sweep)
        [ $# -eq 2 ] || fail "usage: sweep <parent>"
        parent=$2
        check_parent "$parent"
        for directory in "$parent"/h2s-pam-trial.*; do
            [[ "${directory##*/}" =~ ^h2s-pam-trial\.[A-Za-z0-9]{8}$ ]] || continue
            [ -d "$directory" ] && [ ! -L "$directory" ] && [ -O "$directory" ] || continue
            record="$directory/.owner"
            [ -f "$record" ] && [ ! -L "$record" ] || continue
            line=$(head -c 64 -- "$record" 2> /dev/null) || continue
            [[ "$line" =~ ^([1-9][0-9]{0,9})\ ([0-9]{1,20})$ ]] || continue
            pid=${BASH_REMATCH[1]} recorded=${BASH_REMATCH[2]}
            if current=$(start_of "$pid") && [ "$current" = "$recorded" ]; then
                continue
            fi
            remove_directory "$parent" "$directory"
            printf 'removed\t%s\n' "$directory"
        done
        ;;
    *)
        fail "usage: stage <parent> <directory> <owner> <name> <text> ... | remove <parent> <directory> | sweep <parent>"
        ;;
esac
