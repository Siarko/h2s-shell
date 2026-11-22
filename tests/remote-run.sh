#!/usr/bin/env bash
# Runs a branch's tests on another machine over SSH and brings back the verdict.
#
#   H2S_REMOTE=<ssh destination> tests/remote-run.sh [<ref>] [-- <command…>]
#   H2S_REMOTE=<ssh destination> tests/remote-run.sh --attach <id>
#
#   <ref>             what to test: a branch, tag or commit (default HEAD, which must have
#                     no uncommitted changes to tracked files)
#   <command…>        what to run in it, from the tree's top (default
#                     tests/run-all.sh --keep-going)
#   --host <dest>     the SSH destination, in place of H2S_REMOTE
#   --repo <path>     the repository on the remote, in place of H2S_REMOTE_REPO (default
#                     ~/Projects/h2s-shell/sources/h2s-shell)
#   --wait-max <s>    how long to wait for the run (default H2S_REMOTE_WAIT, else 3600 s)
#   --attach <id>     wait for a run started earlier and collect it
#
# The steps: the remote is asked for the commits its repository has, and what it lacks of
# <ref> goes over as a `git bundle` (all of it when nothing is shared); it is fetched into
# the remote repository's object store under a ref of its own, and the run gets a detached
# working tree of its own beside a log, outside that repository's checkout — the remote's
# checkout and the shell running from it are never touched. The command starts detached
# with `setsid`, in a new session, so a dropped connection does not end it; SIGHUP is reset
# to its default (`env --default-signal=HUP`, never nohup), since the launcher's tests check
# it. The script then polls for the run's end every H2S_REMOTE_POLL seconds (default 15),
# brings the log back to ${XDG_CACHE_HOME:-~/.cache}/h2s-shell-tests/remote/<id>.log, prints
# the tool lines, the log's tail and the runner's summary, and removes the remote tree,
# bundle and ref. Interrupted, timed out or cut off, it says the run's id and leaves the
# run going: `--attach <id>` picks it up.
#
# The address is never written to a file, here or on the remote; ssh runs with
# BatchMode=yes, so it never asks for a password. H2S_REMOTE_SSH names another ssh (the
# self-test's stand-in). Needs git, ssh and, on the remote, git, bash, setsid and env from
# coreutils 8.31 or later — the same on NixOS and on Arch. The remote's login shell only
# runs "bash -s" and one single-quoted "bash -c" word: sh, bash, zsh and fish all do.
#
# Exit status: the remote command's; 2 when the run could not be set up or its end not
# seen (no address, the remote unreachable, a ref that does not resolve, a run lost or
# still going at the time limit); 130 when interrupted.
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
SSH=${H2S_REMOTE_SSH:-ssh}
host=${H2S_REMOTE:-}
remote_repo=${H2S_REMOTE_REPO:-'~/Projects/h2s-shell/sources/h2s-shell'}
wait_max=${H2S_REMOTE_WAIT:-3600}
poll=${H2S_REMOTE_POLL:-15}
# Polls that may fail in a row before the connection counts as lost
poll_retries=${H2S_REMOTE_RETRIES:-3}
attach=""
ref=""
command=(tests/run-all.sh --keep-going)

usage() {
    echo "usage: tests/remote-run.sh [--host <dest>] [--repo <path>] [--wait-max <s>] [<ref>] [-- <command…>]" >&2
    echo "       tests/remote-run.sh [--host <dest>] [--wait-max <s>] --attach <id>" >&2
    exit 2
}
setup_error() { echo "remote-run.sh: $*" >&2; exit 2; }

while [ $# -gt 0 ]; do
    case "$1" in
        --host) [ $# -ge 2 ] || usage; host=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; remote_repo=$2; shift 2 ;;
        --wait-max) [ $# -ge 2 ] || usage; wait_max=$2; shift 2 ;;
        --attach) [ $# -ge 2 ] || usage; attach=$2; shift 2 ;;
        --) shift; [ $# -gt 0 ] || usage; command=("$@"); break ;;
        -*) usage ;;
        *) [ -z "$ref" ] || usage; ref=$1; shift ;;
    esac
done
[ -n "$host" ] || setup_error "no remote: set H2S_REMOTE to an ssh destination (or pass --host)"
[[ "$wait_max" =~ ^[0-9]+$ ]] || setup_error "--wait-max takes seconds, not '$wait_max'"
[[ "$poll" =~ ^[0-9]+([.][0-9]+)?$ ]] || setup_error "H2S_REMOTE_POLL takes seconds, not '$poll'"
if [ -n "$attach" ]; then
    [ -z "$ref" ] || usage
    # Exactly the form made below (date, time, commit, a random number)
    [[ "$attach" =~ ^[0-9]{8}-[0-9]{6}-[0-9a-f]{10}-[0-9a-f]{4}$ ]] || setup_error "'$attach' is not a run id"
fi

# The remote half. Every call sends this script on ssh's standard input with one action;
# the run's files live in ${XDG_CACHE_HOME:-~/.cache}/h2s-shell-tests/remote-run/<id>.
# shellcheck disable=SC2016  # expanded on the remote
remote_script='
set -uo pipefail
action=$1
shift
runs=${XDG_CACHE_HOME:-$HOME/.cache}/h2s-shell-tests/remote-run
# The id is the form the local half makes, checked again here before any path is built of it
id_form="^[0-9]{8}-[0-9]{6}-[0-9a-f]{10}-[0-9a-f]{4}\$"
check_id() { [[ "$1" =~ $id_form ]] || { echo "\"$1\" is not a run id" >&2; exit 3; }; }
# The repository a run was started in, as start wrote it, else the one given
run_repo() { if [ -f "$runs/$1/repo" ]; then cat "$runs/$1/repo"; else expand "$2"; fi; }
expand() { case "$1" in "~") echo "$HOME" ;; "~/"*) echo "$HOME/${1#"~/"}" ;; *) echo "$1" ;; esac; }
case "$action" in
probe)
    # probe <repo> <commit>: "have" when the commit is there, then the commits the
    # branches and tags point at; status 3 when the repository is not there
    repo=$(expand "$1")
    command -v git > /dev/null || { echo "git is not installed on the remote" >&2; exit 3; }
    git -C "$repo" rev-parse --git-dir > /dev/null 2>&1 \
        || { echo "no git repository at $1 on the remote (H2S_REMOTE_REPO names another)" >&2; exit 3; }
    for tool in setsid env; do
        command -v "$tool" > /dev/null || { echo "$tool is not installed on the remote (it starts the run detached)" >&2; exit 3; }
    done
    if git -C "$repo" cat-file -e "$2^{commit}" 2> /dev/null; then echo have; fi
    git -C "$repo" for-each-ref --format="%(objectname)" refs/heads refs/tags | sort -u
    ;;
start)
    # start <repo> <id> <commit> <command…>
    check_id "$2"
    repo=$(expand "$1") id=$2 commit=$3
    shift 3
    dir=$runs/$id
    mkdir -p "$dir" || exit 3
    [ ! -e "$dir/run.pid" ] || { echo "run $id was started already" >&2; exit 3; }
    # Where it runs, for clean (an --attach knows only the id)
    repo=$(cd "$repo" 2> /dev/null && pwd) || { echo "no repository at $1" >&2; exit 3; }
    printf "%s" "$repo" > "$dir/repo"
    if [ -f "$dir/bundle" ]; then
        git -C "$repo" fetch --quiet "$dir/bundle" "refs/remote-run/$id:refs/remote-run/$id" \
            || { echo "the bundle could not be fetched into $1" >&2; exit 3; }
    fi
    # The tree is named after the id, so its entry in the repository is worktrees/<id>
    git -C "$repo" worktree add --quiet --detach "$dir/$id" "$commit" \
        || { echo "no working tree for $commit could be made" >&2; exit 3; }
    git -C "$repo" update-ref -d "refs/remote-run/$id" 2> /dev/null
    rm -f "$dir/bundle"
    head=$(git -C "$dir/$id" rev-parse HEAD)
    [ "$head" = "$commit" ] || { echo "the remote tree is at $head, not $commit" >&2; exit 3; }
    printf "%q " "$@" > "$dir/command"
    # A new session, so the hang-up of this connection does not reach the run; SIGHUP back
    # to its default for the launcher tests. $$ in the inner shell is the session leader.
    cd "$dir" || exit 3
    setsid -f env --default-signal=HUP bash -c "
        echo \$\$ > run.pid.tmp && mv run.pid.tmp run.pid
        (cd $id && eval \"\$(cat ../command)\") > run.log 2>&1 < /dev/null
        echo \$? > status.tmp && mv status.tmp status" < /dev/null > /dev/null 2>&1 \
        || { echo "the run could not be started (setsid)" >&2; exit 3; }
    for _ in $(seq 50); do [ -f "$dir/run.pid" ] && break; sleep 0.1; done
    [ -f "$dir/run.pid" ] || { echo "the run did not start" >&2; exit 3; }
    echo started
    ;;
poll)
    # poll <id>: "done <status>", "running", "lost" (ended without a status) or "unknown"
    check_id "$1"
    dir=$runs/$1
    if [ -f "$dir/status" ]; then echo "done $(cat "$dir/status")"
    elif [ ! -f "$dir/run.pid" ]; then echo unknown
    elif kill -0 "$(cat "$dir/run.pid")" 2> /dev/null; then echo running
    elif [ -f "$dir/status" ]; then echo "done $(cat "$dir/status")"
    else echo lost
    fi
    ;;
collect)
    check_id "$1"
    cat "$runs/$1/run.log" 2> /dev/null
    ;;
clean)
    # clean <repo> <id>
    check_id "$2"
    repo=$(run_repo "$2" "$1") dir=$runs/$2
    if [ -d "$dir/$2" ] && ! git -C "$repo" worktree remove --force "$dir/$2" 2> /dev/null; then
        # Only the entry of this run: other worktrees of the repository are not ours to prune
        rm -rf "${dir:?}/$2"
        common=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2> /dev/null) \
            && rm -rf "${common:?}/worktrees/$2"
    fi
    git -C "$repo" update-ref -d "refs/remote-run/$2" 2> /dev/null
    rm -rf "$dir"
    ;;
esac
'

# remote <action> <argument…>: runs the remote half; ssh's own failure is status 255. The
# arguments go on standard input with the script, quoted for the remote bash, so the remote
# login shell only ever sees the plain words "bash -s".
remote() {
    "$SSH" -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=4 \
        "$host" "bash -s" <<< "set -- $(printf '%q ' "$@")
$remote_script"
}
# receive <file>: copies the bundle into the run's directory (a plain command: standard
# input carries the file, not the script; the id is digits, letters and dashes). One
# single-quoted word for bash, which every login shell passes on as it is.
receive() {
    "$SSH" -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=4 \
        "$host" "bash -c 'd=\${XDG_CACHE_HOME:-\$HOME/.cache}/h2s-shell-tests/remote-run/$id && mkdir -p \"\$d\" && cat > \"\$d/bundle\"'" < "$1"
}

reattach_hint() { echo "remote-run.sh: the run goes on remotely; collect it with: tests/remote-run.sh --attach $id" >&2; }

work=$(mktemp -d "${TMPDIR:-/tmp}/remote-run.XXXXXX") || setup_error "cannot create a temp dir"
local_ref=""
cleanup() {
    [ -z "$local_ref" ] || git -C "$REPO" update-ref -d "$local_ref" 2> /dev/null
    rm -rf "$work"
}
trap cleanup EXIT

if [ -n "$attach" ]; then
    id=$attach
    echo "remote-run.sh: attaching to run $id"
else
    if [ -z "$ref" ]; then
        ref=HEAD
        [ -z "$(git -C "$REPO" status --porcelain --untracked-files=no)" ] \
            || setup_error "uncommitted changes in the checkout: commit them, or name a ref"
    fi
    commit=$(git -C "$REPO" rev-parse --verify --quiet "$ref^{commit}") || setup_error "'$ref' is no commit here"
    id=$(date +%Y%m%d-%H%M%S)-${commit:0:10}-$(printf %04x $((RANDOM % 65536)))

    # What the remote has
    remote probe "$remote_repo" "$commit" > "$work/probe" 2> "$work/probe.err"
    status=$?
    if [ "$status" = 255 ]; then
        setup_error "cannot reach the remote: $(grep -v '^[[:space:]]*$' "$work/probe.err" | tail -n 1)"
    elif [ "$status" != 0 ]; then
        setup_error "the remote cannot run it: $(grep -v '^[[:space:]]*$' "$work/probe.err" | tail -n 1)"
    fi
    if [ "$(head -n 1 "$work/probe")" = have ]; then
        echo "remote-run.sh: the remote has $commit already; no bundle"
    else
        # The bundle: what the remote lacks — every commit it has that is known here is a
        # boundary; with none, the whole history
        local_ref=refs/remote-run/$id
        git -C "$REPO" update-ref "$local_ref" "$commit" || setup_error "cannot make the ref $local_ref here"
        echo "$local_ref" > "$work/revs"
        boundaries=0
        while read -r known; do
            [[ "$known" =~ ^[0-9a-f]{40,64}$ ]] || continue
            if git -C "$REPO" cat-file -e "$known^{commit}" 2> /dev/null; then
                echo "^$known" >> "$work/revs"
                boundaries=$((boundaries + 1))
            fi
        done < "$work/probe"
        git -C "$REPO" bundle create --quiet "$work/bundle" --stdin < "$work/revs" 2> "$work/bundle.err" \
            || setup_error "git bundle failed: $(tail -n 1 "$work/bundle.err")"
        git -C "$REPO" update-ref -d "$local_ref"
        local_ref=""
        if [ "$boundaries" = 0 ]; then kind="full history"; else kind="$boundaries known commits left out"; fi
        echo "remote-run.sh: bundle of $ref ($commit), $(du -h "$work/bundle" | cut -f 1), $kind"
        receive "$work/bundle" 2> "$work/copy.err" \
            || { remote clean "$remote_repo" "$id" > /dev/null 2>&1
                 setup_error "the bundle could not be copied: $(tail -n 1 "$work/copy.err")"; }
    fi

    remote start "$remote_repo" "$id" "$commit" "${command[@]}" > "$work/start" 2> "$work/start.err"
    if [ "$(cat "$work/start")" != started ]; then
        reason=$(grep -v '^[[:space:]]*$' "$work/start.err" | tail -n 1)
        remote clean "$remote_repo" "$id" > /dev/null 2>&1
        setup_error "the run could not be started on the remote: ${reason:-no answer}"
    fi
    echo "remote-run.sh: run $id started: ${command[*]} at $commit"
fi

# Interrupted while waiting: the run goes on
trap 'echo; reattach_hint; exit 130' INT TERM

started=$SECONDS
failures=0
answer=""
while :; do
    answer=$(remote poll "$id" 2> "$work/poll.err")
    if [ $? = 0 ] && [ -n "$answer" ]; then
        failures=0
        case "$answer" in
            done*|lost|unknown) break ;;
        esac
    else
        failures=$((failures + 1))
        if [ "$failures" -gt "$poll_retries" ]; then
            echo "remote-run.sh: the connection is lost: $(grep -v '^[[:space:]]*$' "$work/poll.err" | tail -n 1)" >&2
            reattach_hint
            exit 2
        fi
    fi
    if [ $((SECONDS - started)) -ge "$wait_max" ]; then
        echo "remote-run.sh: still running after ${wait_max} s" >&2
        reattach_hint
        exit 2
    fi
    sleep "$poll"
done
trap - INT TERM

if [ "$answer" = unknown ]; then
    setup_error "no run $id on the remote (collected already, or never started)"
fi

cache=${XDG_CACHE_HOME:-$HOME/.cache}/h2s-shell-tests/remote
mkdir -p "$cache" || setup_error "cannot create $cache"
log=$cache/$id.log
remote collect "$id" > "$log" 2> "$work/collect.err" || {
    echo "remote-run.sh: the log could not be brought back: $(tail -n 1 "$work/collect.err")" >&2
    reattach_hint
    exit 2
}

echo
echo "==== remote log: $log"
grep -E '^(tools|quickshell|launcher|lock bed launcher|memory cap):|^warning: (no memory cap|the run.s memory budget)' "$log" | awk '!seen[$0]++'
summary_line=$(grep -n '^All (' "$log" | tail -n 1 | cut -d: -f 1)
if [ -n "$summary_line" ]; then
    # The tail before the summary, then the summary itself
    from=$((summary_line > 20 ? summary_line - 20 : 1))
    sed -n "${from},$((summary_line - 1))p" "$log"
    sed -n "${summary_line},\$p" "$log"
else
    tail -n 30 "$log"
fi
remote clean "$remote_repo" "$id" > /dev/null 2>&1 \
    || echo "remote-run.sh: the remote run's files could not be removed (run $id)" >&2

if [ "$answer" = lost ]; then
    setup_error "run $id ended on the remote without a status (killed?)"
fi
status=${answer#done }
[[ "$status" =~ ^[0-9]+$ ]] || setup_error "run $id left an unreadable status '$status'"
echo "remote-run.sh: run $id ended with status $status"
exit "$status"
