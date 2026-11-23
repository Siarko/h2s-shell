#!/usr/bin/env bash
# The PAM trial's staging directory (singletons/io/PamTrial.qml): a private copy of a
# candidate PAM service and of the files it includes, which one PAM conversation then runs
# as the user. Which files, and their texts, are PamTrialRules' decision; this only writes.
#
#   pam-trial-stage.sh stage <parent> <name> <text> [<name> <text> ...]
#       makes <parent>/h2s-pam-trial.XXXXXXXX (mode 0700) with each file (mode 0600, the
#       text exactly as given) and prints "staged TAB <directory>"
#   pam-trial-stage.sh remove <directory>
#       removes such a directory, and only such: named so, directly in an absolute parent,
#       a directory (not a link) of this user's; one already gone is no error
#
# The parent must be an absolute directory of this user's (the runtime directory). A name
# is what libpam takes as a service name: no "/", no leading dot. Nothing runs as root;
# nothing outside the directory it made is written.
set -u
export LC_ALL=C
umask 077

prefix=h2s-pam-trial.

fail() {
    echo "pam-trial-stage: $*" >&2
    exit 1
}

valid_name() {
    [[ "$1" =~ ^[A-Za-z0-9_][A-Za-z0-9._@+-]*$ ]] && [ "${#1}" -le 255 ]
}

case "${1:-}" in
    stage)
        [ $# -ge 4 ] || fail "usage: stage <parent> <name> <text> [<name> <text> ...]"
        parent=$2
        shift 2
        [[ "$parent" == /* ]] || fail "the parent is not an absolute path"
        [ -d "$parent" ] && [ -O "$parent" ] || fail "the parent is not a directory of this user's"
        [ $(($# % 2)) -eq 0 ] || fail "names and texts do not pair up"
        files=("$@")
        for ((i = 0; i < ${#files[@]}; i += 2)); do
            valid_name "${files[i]}" || fail "not a file name: ${files[i]}"
            for ((j = 0; j < i; j += 2)); do
                [ "${files[j]}" != "${files[i]}" ] || fail "a name given twice: ${files[i]}"
            done
        done
        directory=$(mktemp -d "${parent%/}/${prefix}XXXXXXXX") || fail "cannot make the directory"
        for ((i = 0; i < ${#files[@]}; i += 2)); do
            if ! printf '%s' "${files[i + 1]}" > "$directory/${files[i]}"; then
                rm -rf -- "$directory"
                fail "cannot write ${files[i]}"
            fi
        done
        printf 'staged\t%s\n' "$directory"
        ;;
    remove)
        [ $# -eq 2 ] || fail "usage: remove <directory>"
        directory=$2
        [[ "$directory" == /* ]] || fail "not an absolute path"
        [[ "$(basename -- "$directory")" =~ ^h2s-pam-trial\.[A-Za-z0-9]{8}$ ]] || fail "not a staging directory: $directory"
        [ -e "$directory" ] || [ -L "$directory" ] || exit 0
        [ -d "$directory" ] && [ ! -L "$directory" ] && [ -O "$directory" ] || fail "not a staging directory of this user's: $directory"
        rm -rf -- "$directory" || fail "cannot remove $directory"
        ;;
    *)
        fail "usage: stage <parent> <name> <text> ... | remove <directory>"
        ;;
esac
