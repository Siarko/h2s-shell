#!/usr/bin/env bash
# Checks tests/remote-run.sh against a stand-in ssh that runs the remote half locally, in a
# temp directory that plays the remote's home (no network is reached). A temp repository
# holds a copy of the script and a stand-in test command; a clone of it, a few commits
# behind, is the remote's repository. The cases: a pass and a failure status, each
# brought back with the log and the summary, the remote checkout left as it was and no
# remote tree, bundle or ref left; a bundle of the whole history for a remote that shares
# none; the run seeing SIGHUP at its default; a dropped connection and a run still going at
# the time limit, each picked up with --attach; an unreachable remote and a missing
# repository (status 2 with the reason); and that the address appears in no file the
# script writes, here or on the "remote".
#
#   tests/remote-run-selftest.sh
#
# Needs bash, git, coreutils and util-linux's setsid, the same on NixOS and on Arch. It
# takes no lock: nothing of it is shared with another run.
#
# Exit status: 0 when every check passed, 1 when one failed, 2 when it could not be set up.
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/remote-run-self.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT
failures=0
for tool in git setsid bash; do
    type -P "$tool" > /dev/null || { echo "remote-run-selftest.sh: $tool not found on PATH (the script calls it)" >&2; exit 2; }
done

check() {
    local description=$1
    shift
    if "$@"; then echo "  PASS $description"; else echo "  FAIL $description"; failures=$((failures + 1)); fi
}

address=tester@secret-host.example
remote_home=$work/remote-home
# Where remote-run.sh looks for the repository on the remote when not told (~ is remote_home)
default_repo=$remote_home/Projects/h2s-shell/sources/h2s-shell
mkdir -p "$remote_home/src" "$work/control" "$work/local-cache" "$work/tmp"

# ---- The stand-in ssh: options, the destination, then the command, run by bash in the
# remote's home; control files make it unreachable, or drop the polls
cat > "$work/ssh" << EOF
#!$(type -P bash)
while [ \$# -gt 0 ]; do
    case "\$1" in -o) shift 2 ;; -*) shift ;; *) break ;; esac
done
destination=\$1
shift
if [ -e "$work/control/unreachable" ]; then
    echo "ssh: connect to host \${destination#*@} port 22: Connection refused" >&2
    exit 255
fi
cd "$remote_home" || exit 255
if [ "\$*" = "bash -s" ]; then
    # The action is the first line of the script it is sent
    input=\$(cat)
    if [ -e "$work/control/drop-polls" ] && [[ "\$input" == "set -- poll "* ]]; then
        echo "client_loop: send disconnect: Broken pipe" >&2
        exit 255
    fi
    exec env -u XDG_CACHE_HOME HOME="$remote_home" bash -c "\$*" <<< "\$input"
fi
exec env -u XDG_CACHE_HOME HOME="$remote_home" bash -c "\$*"
EOF
chmod +x "$work/ssh"

# ---- The local repository: the script, and a test command that prints a runner's lines,
# waits for a file when asked, and ends with the status it is given
local_repo=$work/local
mkdir -p "$local_repo/tests"
cp "$REPO/tests/remote-run.sh" "$local_repo/tests/"
cat > "$local_repo/tests/fake.sh" << 'EOF'
#!/usr/bin/env bash
# fake.sh <status> [<file to wait for> [<argument to echo>]]
echo "tools: system (PATH, not pinned) — labwc 0"
echo "hup ignored: $(( 0x$(awk '/^SigIgn/ {print $2}' /proc/$$/status) & 1 ))"
echo "commit: $(git rev-parse HEAD)"
echo "session: $(awk '{print $6}' /proc/$$/stat)"
echo "argument: ${3:-}"
# A deadline, so that a check gone wrong does not leave it running
if [ -n "${2:-}" ]; then
    for _ in $(seq 600); do [ -e "$2" ] && break; sleep 0.1; done
    [ -e "$2" ] || { echo "fake: gave up waiting"; exit 99; }
fi
echo "All (1 s):"
echo "  PASS     fake part"
echo "fake: status $1"
exit "$1"
EOF
chmod +x "$local_repo/tests/fake.sh"
(
    cd "$local_repo" && git init --quiet -b master && git config user.email t@t && git config user.name t \
        && git add -A && git commit --quiet -m one \
        && git clone --quiet "$local_repo" "$default_repo" \
        && git clone --quiet "$local_repo" "$remote_home/src/h2s shell" \
        && git -C "$default_repo" worktree add --quiet --detach "$remote_home/owner-tree" \
        && rm -rf "$remote_home/owner-tree" \
        && echo two > two && git add two && git commit --quiet -m two \
        && git checkout --quiet -b feature && echo three > three && git add three && git commit --quiet -m three
) || { echo "remote-run-selftest.sh: the test repositories could not be made" >&2; exit 2; }
remote_head=$(git -C "$default_repo" rev-parse HEAD)
feature=$(git -C "$local_repo" rev-parse feature)

# run [<argument>…]: the script against the stand-in; OUTPUT, STATUS
run() {
    OUTPUT=$(cd "$local_repo" && H2S_REMOTE=$address H2S_REMOTE_SSH=$work/ssh H2S_REMOTE_POLL=0.2 \
        H2S_REMOTE_RETRIES=2 XDG_CACHE_HOME=$work/local-cache TMPDIR=$work/tmp \
        timeout 60 tests/remote-run.sh "$@" 2>&1)
    STATUS=$?
}
has() { grep -qF -- "$1" <<< "$OUTPUT"; }
run_id() { sed -n 's/^remote-run.sh: run \([^ ]*\) started.*/\1/p' <<< "$OUTPUT"; }
# remote_clean [<repository>]: as it was, but for objects; the owner's stale worktree kept
remote_clean() {
    local repo=${1:-$default_repo}
    [ "$(git -C "$repo" rev-parse HEAD)" = "$remote_head" ] \
        && [ -z "$(git -C "$repo" status --porcelain)" ] \
        && ! git -C "$repo" worktree list | grep -q h2s-shell-tests \
        && { [ "$repo" != "$default_repo" ] || git -C "$repo" worktree list | grep -q owner-tree; } \
        && [ -z "$(git -C "$repo" for-each-ref refs/remote-run)" ] \
        && [ -z "$(ls -A "$remote_home/.cache/h2s-shell-tests/remote-run" 2> /dev/null)" ] \
        && [ -z "$(git -C "$local_repo" for-each-ref refs/remote-run)" ]
}

echo "a pass"
# The stand-in starts with SIGHUP ignored, as under nohup: the run must see it at default
trap '' HUP
run feature -- tests/fake.sh 0
trap - HUP
check "status 0" [ "$STATUS" = 0 ]
check "a bundle of what the remote lacks" has "known commits left out"
check "the run is at the branch's commit" has "commit: $feature"
check "the tool line and the summary come back" bash -c 'grep -q "^tools: system" <<< "$1" && grep -q "^All (1 s):" <<< "$1" && grep -q "PASS     fake part" <<< "$1"' _ "$OUTPUT"
check "SIGHUP is at its default in the run" has "hup ignored: 0"
check "the run is in a session of its own" bash -c 'session=$(sed -n "s/^session: //p" <<< "$1"); [ -n "$session" ] && [ "$session" != "$(awk "{print \$6}" /proc/$$/stat)" ]' _ "$OUTPUT"
id=$(run_id)
check "the log is kept here" grep -q "fake: status 0" "$work/local-cache/h2s-shell-tests/remote/$id.log"
check "the remote checkout untouched, its run's tree, bundle and refs removed" remote_clean

echo "a failure status"
run feature -- tests/fake.sh 3
check "status 3, the remote command's" [ "$STATUS" = 3 ]
check "the summary comes back" has "fake: status 3"
check "nothing left on the remote" remote_clean

echo "the remote has the commit already"
run master -- tests/fake.sh 0
check "status 0" [ "$STATUS" = 0 ]
check "no bundle sent" has "no bundle"

echo "a remote that shares no history"
mv "$default_repo" "$default_repo.kept"
git init --quiet "$default_repo"
run feature -- tests/fake.sh 0
check "status 0" [ "$STATUS" = 0 ]
check "a bundle of the whole history" has "full history"
rm -rf "$default_repo"
mv "$default_repo.kept" "$default_repo"

echo "a dropped connection, then --attach"
touch "$work/control/drop-polls"
run feature -- tests/fake.sh 4 "$work/control/release"
id=$(run_id)
check "status 2 when the connection is lost" [ "$STATUS" = 2 ]
check "it says the connection is lost and how to attach" bash -c 'grep -q "connection is lost" <<< "$1" && grep -qF -- "--attach $2" <<< "$1"' _ "$OUTPUT" "$id"
check "the run goes on remotely" grep -q "^commit:" "$remote_home/.cache/h2s-shell-tests/remote-run/$id/run.log"
rm "$work/control/drop-polls"
touch "$work/control/release"
run --attach "$id"
check "--attach brings back status 4" [ "$STATUS" = 4 ]
check "--attach brings back the summary" has "fake: status 4"
check "nothing left on the remote" remote_clean
run --attach "$id"
check "a second --attach: no such run, status 2" bash -c '[ "$1" = 2 ] && grep -q "no run" <<< "$2"' _ "$STATUS" "$OUTPUT"
rm "$work/control/release"

echo "the time limit, then --attach"
run --wait-max 0 feature -- tests/fake.sh 0 "$work/control/release"
id=$(run_id)
check "status 2 at the limit" [ "$STATUS" = 2 ]
check "it says it is still running" has "still running"
touch "$work/control/release"
run --attach "$id"
check "--attach brings back status 0" [ "$STATUS" = 0 ]
check "nothing left on the remote" remote_clean

echo "quoting: an argument with shell syntax, a repository path with a space"
tricky='a b;$(touch $HOME/pwned) `touch $HOME/pwned`'
run --repo '~/src/h2s shell' --wait-max 0 feature -- tests/fake.sh 0 "$work/control/release2" "$tricky"
id=$(run_id)
check "it starts in the repository with a space" [ -n "$id" ]
touch "$work/control/release2"
run --attach "$id"
check "status 0" [ "$STATUS" = 0 ]
check "the argument reaches the command unchanged" has "argument: $tricky"
check "nothing it names ran" bash -c '[ -z "$(find "$1" "$2" -name pwned)" ]' _ "$remote_home" "$local_repo"
check "--attach cleans the run's own repository" remote_clean "$remote_home/src/h2s shell"

echo "ids that are no run's"
for bad in .. . ../x 20260101-000000-0123456789-abc; do
    run --attach "$bad"
    check "--attach $bad: status 2, refused here" bash -c '[ "$1" = 2 ] && grep -q "is not a run id" <<< "$2"' _ "$STATUS" "$OUTPUT"
done
check "the remote's run directory still there" [ -d "$remote_home/.cache/h2s-shell-tests" ]
# The remote half checks the id itself, whoever calls it
script_text=$(sed -n "/^remote_script='/,/^'$/p" "$local_repo/tests/remote-run.sh" | sed '1d;$d')
printf 'set -- clean %q ..\n%s\n' "$default_repo" "$script_text" | "$work/ssh" "$address" "bash -s" > /dev/null 2>&1
check "the remote half refuses a clean of '..'" bash -c '[ "$1" = 3 ] && [ -d "$2" ]' _ "$?" "$remote_home/.cache/h2s-shell-tests/remote-run"

echo "an unreachable remote"
touch "$work/control/unreachable"
run feature -- tests/fake.sh 0
check "status 2" [ "$STATUS" = 2 ]
check "the reason is given" has "cannot reach the remote: ssh: connect to host"
rm "$work/control/unreachable"

echo "no repository on the remote"
run --repo '~/src/elsewhere' feature -- tests/fake.sh 0
check "status 2" [ "$STATUS" = 2 ]
check "the reason is given" has "no git repository at ~/src/elsewhere"

echo "no address"
OUTPUT=$(cd "$local_repo" && env -u H2S_REMOTE tests/remote-run.sh 2>&1)
STATUS=$?
check "status 2 and the reason" bash -c '[ "$1" = 2 ] && grep -q "no remote: set H2S_REMOTE" <<< "$2"' _ "$STATUS" "$OUTPUT"

echo "the address in files"
check "in no file written here or on the remote" bash -c '! grep -rqF secret-host "$@"' _ \
    "$remote_home" "$work/local-cache" "$work/tmp" "$local_repo"
check "the temp files removed" [ -z "$(ls -A "$work/tmp")" ]

if [ "$failures" -gt 0 ]; then
    echo "remote-run-selftest.sh: $failures failed"
    exit 1
fi
echo "remote-run-selftest.sh: all passed"
