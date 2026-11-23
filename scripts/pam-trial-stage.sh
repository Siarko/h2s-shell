#!/usr/bin/env bash
# The PAM trial's staging directory (singletons/io/PamTrial.qml): a private copy of a
# candidate PAM service and of the files it includes, which one PAM conversation then runs
# as the user. Which files, their texts and the directory's name are PamTrialRules'
# decision; this only writes and removes.
#
#   pam-trial-stage.sh stage <parent> <directory> <name> <text> [<name> <text> ...]
#       makes <directory> (mode 0700) with each file (mode 0600, the text exactly as
#       given) and prints "staged TAB <directory>"; a directory that is already there is
#       an error, never reused
#   pam-trial-stage.sh remove <parent> <directory>
#       removes <directory>; one already gone is no error
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

# check_places <parent> <directory>: both as described above, the parent there and ours
check_places() {
    local parent=$1 directory=$2
    [[ "$parent" =~ ^(/[^/]+)+$ ]] || fail "not a plain absolute path: $parent"
    case "/$parent/" in
        */./* | */../*) fail "a . or .. in the parent: $parent" ;;
    esac
    [ "$directory" = "$parent/${directory##*/}" ] || fail "not directly in $parent: $directory"
    [[ "${directory##*/}" =~ ^h2s-pam-trial\.[A-Za-z0-9]{8}$ ]] || fail "not a staging directory's name: $directory"
    [ -d "$parent" ] && [ ! -L "$parent" ] && [ -O "$parent" ] || fail "the parent is not a directory of this user's: $parent"
}

case "${1:-}" in
    stage)
        [ $# -ge 5 ] || fail "usage: stage <parent> <directory> <name> <text> [<name> <text> ...]"
        parent=$2 directory=$3
        shift 3
        check_places "$parent" "$directory"
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
        [ -e "$directory" ] || [ -L "$directory" ] || exit 0
        [ -d "$directory" ] && [ ! -L "$directory" ] && [ -O "$directory" ] || fail "not a staging directory of this user's: $directory"
        rm -rf -- "$directory" || fail "cannot remove $directory"
        ;;
    *)
        fail "usage: stage <parent> <directory> <name> <text> ... | remove <parent> <directory>"
        ;;
esac
