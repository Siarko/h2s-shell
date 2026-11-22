#!/usr/bin/env bash
# The shell's helper program (helper/, h2s-helper), built and run for real, and the two
# scripts that build and find it, on stand-ins:
#
#   1. the helper built into a temporary directory — with the system's cmake, compiler and
#      Qt through scripts/build-helper.sh, or, where the tools come from nix, as the flake's
#      h2s-helper package (the very derivation the NixOS package installs) — then
#      `--version` (the shell's version, the protocol HelperRules speaks), a wrong
#      subcommand, and `ping` driven as the shell drives it: ready, a round trip, what is
#      not a JSON object, a line too long, and its standard input closed: it ends;
#   2. scripts/build-helper.sh in a copy of the tree, with a stand-in cmake: the
#      directories it refuses (also by owner and mode), --print-path, --status, a build,
#      --if-changed with the source as it was, changed, and only the version changed, a
#      build that fails or runs out of time (and is not tried again by --if-changed);
#   3. scripts/launch.sh --helper (what the shell is handed as H2S_SHELL_HELPER) in a copy
#      of the tree, with a stand-in build-helper.sh: H2S_HELPER given, given empty, the
#      checkout's build current, stale (handed over at once, rebuilt in the background,
#      never waited for), missing, failed, the installation's helper (H2S_SHELL_LIBEXEC),
#      a session locked by a dead shell — and the launcher's log line, once per outcome;
#   4. nothing runs the helper or its build through pkexec, sudo or the like.
#
#   tests/run-helper.sh
#
# The tools, as every runner takes them: H2S_TEST_TOOLS=nix the flake's package (nix
# builds it, with its own cmake, compiler and Qt), =system cmake, a C++ compiler and Qt 6's
# development files from the system; unset, nix where there is a `nix` command. Nothing is
# written outside its temporary directory; no D-Bus, no shell, no compositor.
#
# Exit status: 0 when every check passed, 1 when one failed, 2 when it could not be set up
# (a missing tool is named with its use).
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd -P)
setup_error() { echo "run-helper.sh: $*" >&2; exit 2; }

missing=()
need() { type -P "$1" > /dev/null || missing+=("$1 not found on PATH ($2)"); }
for tool in bash timeout sha256sum find sort xargs sed grep mktemp cp; do
    need "$tool" "the build script and these checks use it"
done
source=${H2S_TEST_TOOLS:-}
if [ -z "$source" ]; then
    if type -P nix > /dev/null; then source=nix; else source=system; fi
fi
case "$source" in
    nix) need nix "builds the flake's h2s-helper package" ;;
    system) need cmake "builds the helper (with a C++ compiler and Qt 6's development files, Core and DBus)" ;;
    *) setup_error "H2S_TEST_TOOLS is '$source': nix or system" ;;
esac
if [ ${#missing[@]} -gt 0 ]; then
    printf 'run-helper.sh: %s\n' "${missing[@]}" >&2
    exit 2
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/run-helper.XXXXXX") || setup_error "cannot create a temp dir"
helper_pid=""
trap '[ -n "$helper_pid" ] && kill "$helper_pid" 2> /dev/null; rm -rf "$work"' EXIT
failed=0
check() {
    local description=$1
    shift
    if "$@"; then echo "  PASS $description"; else echo "  FAIL $description"; failed=1; fi
}

version=$(sed -n 's/.*readonly property string number: "\([^"]*\)".*/\1/p' "$REPO/singletons/Version.qml" | head -n 1)
protocol=$(sed -n 's/.*readonly property int protocol: \([0-9]*\).*/\1/p' "$REPO/singletons/HelperRules.qml" | head -n 1)
[ -n "$version" ] && [ -n "$protocol" ] || setup_error "cannot read the version (singletons/Version.qml) or the protocol (singletons/HelperRules.qml)"

# ---- 1. The helper, built and run ------------------------------------------------------
if [ "$source" = nix ]; then
    echo "tools: nix (the flake's h2s-helper package, its own cmake, compiler and Qt)"
    out=$(cd "$REPO" && nix --extra-experimental-features "nix-command flakes" build --no-link \
        --no-write-lock-file --print-out-paths "path:$REPO#h2s-helper" 2> "$work/build.log" | tail -n 1)
    helper=${out:+$out/libexec/h2s-shell/h2s-helper}
else
    echo "tools: system (PATH, not pinned) — $(cmake --version | head -n 1)"
    helper=$("$REPO/scripts/build-helper.sh" --out "$work/build" 2> "$work/build.log")
fi
if [ -z "$helper" ] || [ ! -x "$helper" ]; then
    tail -n 20 "$work/build.log"
    check "the helper builds" false
    echo "run-helper.sh: FAILED"
    exit 1
fi
check "the helper builds" true

answer=$("$helper" --version)
check "--version: exit 0" test $? = 0
check "--version: one JSON line with the shell's version ($version) and the protocol HelperRules speaks ($protocol)" \
    test "$answer" = "{\"protocol\":$protocol,\"version\":\"$version\"}"
"$helper" sideways > /dev/null 2> "$work/usage"
check "a wrong subcommand: exit 2" test $? = 2
check "… and its usage on standard error" grep -q "usage: h2s-helper" "$work/usage"
"$helper" > /dev/null 2>&1
check "no subcommand: exit 2" test $? = 2

# The ping conversation, as the shell holds it: a pipe each way
coproc HELPER { exec "$helper" ping 2> "$work/ping.err"; }
helper_pid=$HELPER_PID
to_helper=${HELPER[1]}
from_helper=${HELPER[0]}
reply() { local line=""; IFS= read -r -t 5 line <&"$from_helper"; printf '%s' "$line"; }
check "ping: it says it is ready, with its protocol" test "$(reply)" = "{\"event\":\"ready\",\"protocol\":$protocol}"
echo '{"ping":"one"}' >&"$to_helper"
check "ping: a round trip" test "$(reply)" = '{"event":"pong","ping":"one"}'
echo '{"ping":{"nested":[1,2]}}' >&"$to_helper"
check "… what it is sent comes back as it was" test "$(reply)" = '{"event":"pong","ping":{"nested":[1,2]}}'
echo 'not json' >&"$to_helper"
check "ping: a line that is not JSON: an error, and it goes on" test "$(reply)" = '{"event":"error","message":"not a JSON object"}'
echo '[1,2]' >&"$to_helper"
check "ping: JSON that is not an object: an error" test "$(reply)" = '{"event":"error","message":"not a JSON object"}'
echo '{"what":1}' >&"$to_helper"
check "ping: an object it does not know: an error" test "$(reply)" = '{"event":"error","message":"unknown message"}'
# (A builtin writes it: the coprocess's descriptors are not open in a pipeline's subshells)
printf '%s\n' "$(head -c 70000 /dev/zero | tr '\0' x)" >&"$to_helper"
check "ping: a line longer than 64 KiB: one error, the line dropped" test "$(reply)" = '{"event":"error","message":"line too long"}'
echo '{"ping":2}' >&"$to_helper"
check "… and the next line is answered" test "$(reply)" = '{"event":"pong","ping":2}'
exec {to_helper}>&-
gone() { ! kill -0 "$helper_pid" 2> /dev/null; }
waited=0
until gone || [ "$waited" -ge 100 ]; do sleep 0.05; waited=$((waited + 1)); done
check "ping: its standard input closed (the shell gone), it ends" gone
wait "$helper_pid" 2> /dev/null
check "… with status 0" test $? = 0
helper_pid=""
check "… having said nothing on standard error" test ! -s "$work/ping.err"

# ---- 2. scripts/build-helper.sh, with a stand-in cmake ------------------------------------
tree=$work/tree
mkdir -p "$tree/scripts" "$tree/singletons" "$tree/helper/src" "$work/bin" "$work/control"
cp "$REPO/scripts/build-helper.sh" "$tree/scripts/"
cp "$REPO/singletons/Version.qml" "$tree/singletons/"
echo "project(stand-in)" > "$tree/helper/CMakeLists.txt"
echo "int main() {}" > "$tree/helper/src/main.cpp"
control=$work/control
cat > "$work/bin/cmake" << STANDIN
#!$(type -P bash)
echo "cmake \$*" >> "$control/log"
case "\$1" in
    -S) exit 0 ;;
    --build)
        [ -e "$control/fail" ] && { echo "a compiler error" >&2; exit 1; }
        [ -e "$control/hang" ] && exec sleep 30
        mkdir -p "\$2"
        printf '#!/bin/sh\necho built %s\n' "\$(cat "$control/generation" 2> /dev/null)" > "\$2/h2s-helper"
        chmod +x "\$2/h2s-helper"
        ;;
esac
STANDIN
chmod +x "$work/bin/cmake"
build() { PATH="$work/bin:$PATH" XDG_CACHE_HOME="$work/cache" "$tree/scripts/build-helper.sh" "$@" 2> "$work/build.err"; }
builds() { grep -c -- '--build' "$control/log" 2> /dev/null || echo 0; }

build --out relative/path > /dev/null
check "build-helper: a relative directory: refused (2)" test $? = 2
build --out "$tree/build/helper" > /dev/null
check "build-helper: a directory inside the checkout: refused (2)" test $? = 2
ln -s "$tree" "$work/link-into-tree"
build --out "$work/link-into-tree/out" > /dev/null
check "build-helper: … also through a link" test $? = 2
build --out "$work/link-into-tree" > /dev/null
check "build-helper: a link as the directory: refused (2)" test $? = 2
mkdir -p "$work/someone"; echo mine > "$work/someone/file"
build --out "$work/someone" > /dev/null
check "build-helper: a directory holding files it did not make: refused (2)" test $? = 2
check "… and left as it was" test "$(ls -A "$work/someone")" = file
build --out "$work/a/../b" > /dev/null
check "build-helper: a directory with .. in it: refused (2)" test $? = 2
check "build-helper: nothing was built for any of them" test "$(builds)" = 0

printed=$(build --print-path)
check "build-helper --print-path: the default is in the cache, under a hash of the checkout's path" \
    grep -qx "$work/cache/h2s-shell/helper/[0-9a-f]\{16\}/h2s-helper" <<< "$printed"
check "… and nothing is built or made" test ! -e "$work/cache"

echo 1 > "$control/generation"
first=$(build)
check "build-helper: a build prints the binary's path" test "$first" = "$printed"
check "… the binary is there, built" test "$("$first" 2> /dev/null)" = "built 1"
check "… cmake told the shell's version" grep -q -- "-DH2S_VERSION=$version" "$control/log"
check "… and its output is in build.log beside it" test -f "$(dirname "$first")/build.log"
echo 2 > "$control/generation"
build --if-changed > /dev/null
check "build-helper --if-changed, the source as it was: no build" test "$(builds)" = 1
echo "// changed" >> "$tree/helper/src/main.cpp"
again=$(build --if-changed)
check "build-helper --if-changed, the source changed: built again" test "$(builds)" = 2 -a "$("$again")" = "built 2"
: > "$control/fail"
echo "// changed again" >> "$tree/helper/src/main.cpp"
build --if-changed > /dev/null
check "build-helper: a build that fails: exit 1" test $? = 1
check "… says where its log is" grep -q "build.log" "$work/build.err"
check "… the binary there is left as it was" test "$("$again")" = "built 2"
build --if-changed > /dev/null
check "build-helper --if-changed after that failure, the same source: not tried again (exit 1)" test $? = 1 -a "$(builds)" = 3
rm "$control/fail"
echo 3 > "$control/generation"
build > /dev/null
check "build-helper without --if-changed: tried again, and built" test $? = 0 -a "$(builds)" = 4 -a "$("$again")" = "built 3"
check "build-helper: the build directory is the user's alone (700)" test "$(stat -c %a "$(dirname "$first")")" = 700
check "build-helper --status: current" test "$(build --status)" = current
sed -i 's/readonly property string number: "[^"]*"/readonly property string number: "99.0.0"/' "$tree/singletons/Version.qml"
build --if-changed > /dev/null
check "build-helper --if-changed, only the shell's version changed: no build" test "$(builds)" = 4
echo "// changed for the status" >> "$tree/helper/src/main.cpp"
check "build-helper --status, the source changed: stale" test "$(build --status)" = stale
: > "$control/hang"
started_at=$SECONDS
build --if-changed --time-limit 1 > /dev/null
check "build-helper: a build past its time limit: ended, exit 1" test $? = 1 -a $((SECONDS - started_at)) -lt 10
check "… said so" grep -q "longer than 1 s" "$work/build.err"
check "… and counted as failed (--status)" test "$(build --status)" = failed
build --if-changed > /dev/null
check "… not tried again by --if-changed" test $? = 1 -a "$(builds)" = 5
rm "$control/hang"
check "build-helper --status, nothing built there: missing" test "$(build --out "$work/fresh" --status)" = missing
mkdir -p "$work/shared"
chmod 775 "$work/shared"
build --out "$work/shared/out" > /dev/null
check "build-helper: a directory in one the group can write to: refused (2)" test $? = 2
check "build-helper: nothing was written into the checkout" \
    test "$(cd "$tree" && find . -newer "$tree/singletons/Version.qml" -type f | grep -v '^./helper/src/main.cpp$')" = ""

# ---- 3. scripts/launch.sh --helper, with a stand-in build-helper.sh -------------------------
shell=$work/shell
mkdir -p "$shell/scripts" "$shell/helper" "$work/runtime" "$work/home" "$work/libexec" "$work/own"
cp "$REPO/scripts/launch.sh" "$REPO/scripts/seams.sh" "$shell/scripts/"
: > "$shell/helper/CMakeLists.txt"
printf '#!/bin/sh\nexit 0\n' > "$work/libexec/h2s-helper"
chmod +x "$work/libexec/h2s-helper"
# The stand-in: --status answers what control/status says; a build notes its start and end
# (in builds, kept across cases), takes 3 s with control/slow, and makes the binary
cat > "$shell/scripts/build-helper.sh" << STANDIN
#!$(type -P bash)
echo "build-helper \$*" >> "$control/launcher-log"
case "\$1" in
    --print-path) echo "$work/own/h2s-helper"; exit 0 ;;
    --status) cat "$control/status"; exit 0 ;;
esac
echo start >> "$control/builds"
[ -e "$control/slow" ] && sleep 3
printf '#!/bin/sh\nexit 0\n' > "$work/own/h2s-helper"
chmod +x "$work/own/h2s-helper"
echo end >> "$control/builds"
STANDIN
: > "$control/builds"
helper_for() {
    : > "$control/launcher-log"
    env -i PATH="$PATH" HOME="$work/home" XDG_RUNTIME_DIR="$work/runtime" "$@" \
        bash "$shell/scripts/launch.sh" --helper 2> /dev/null
}
said() { grep -c "helper: " "$work/runtime/h2s-shell-launcher.log" 2> /dev/null || echo 0; }
last_said() { grep "helper: " "$work/runtime/h2s-shell-launcher.log" | tail -n 1; }
asked_status() { grep -q -- "--status" "$control/launcher-log"; }
started() { grep -c start "$control/builds"; }
settled() { [ "$(grep -c start "$control/builds")" = "$(grep -c end "$control/builds")" ]; }
wait_for() { local tries=0; until "${@:2}"; do [ "$tries" -ge $(($1 * 20)) ] && return 1; sleep 0.05; tries=$((tries + 1)); done; }
own_binary() { printf '#!/bin/sh\nexit 0\n' > "$work/own/h2s-helper"; chmod +x "$work/own/h2s-helper"; }
# (Counted at each try, not once when the check is written)
more_builds_than() { [ "$(started)" -gt "$1" ]; }
# A build started in the background shows within this long, or not at all
no_build_since() { ! wait_for 1 more_builds_than "$1"; }

echo missing > "$control/status"
before=$(started)
check "launch.sh: no installation helper, none built yet: none this start" test "$(helper_for)" = ""
check "… the build started in the background, for the next start" wait_for 5 more_builds_than "$before"
check "… said, with 'runs without it'" grep -q "helper: none yet: building .*the shell runs without it" "$work/runtime/h2s-shell-launcher.log"
wait_for 10 settled
echo stale > "$control/status"
: > "$control/slow"
before=$(started)
begun=$SECONDS
check "launch.sh: the source changed, a build there: that binary at once" test "$(helper_for)" = "$work/own/h2s-helper"
check "… without waiting for the build (3 s here)" test $((SECONDS - begun)) -le 2
check "… which runs in the background" wait_for 5 more_builds_than "$before"
check "… and ends after the launcher has" eval '! settled'
check "… said" grep -q "rebuilding in the background" <<< "$(last_said)"
wait_for 10 settled
rm "$control/slow"
echo current > "$control/status"
before=$(started)
check "launch.sh: the checkout's build is current: it, nothing built" test "$(helper_for)" = "$work/own/h2s-helper"
check "… nothing built" no_build_since "$before"
lines=$(said)
helper_for > /dev/null
check "… said once: the same outcome again adds no line" test "$(said)" = "$lines"
echo failed > "$control/status"
before=$(started)
check "launch.sh: this source failed to build: the older build there, not built again" test "$(helper_for)" = "$work/own/h2s-helper"
check "… nothing built" no_build_since "$before"
check "… the failure said, with the log" grep -q "helper: failed: .*build.log" <<< "$(last_said)"
rm "$work/own/h2s-helper"
check "launch.sh: failed and no build there, the installation has one: the installation's" \
    test "$(helper_for H2S_SHELL_LIBEXEC="$work/libexec")" = "$work/libexec/h2s-helper"
check "launch.sh: the installation has one, this checkout none: the installation's, the checkout not asked" \
    test "$(helper_for H2S_SHELL_LIBEXEC="$work/libexec")" = "$work/libexec/h2s-helper"
check "… its status not even asked" eval '! asked_status'
own_binary
check "launch.sh: H2S_HELPER given: that one" \
    test "$(helper_for H2S_HELPER="$work/libexec/h2s-helper")" = "$work/libexec/h2s-helper"
check "… the checkout not asked" eval '! asked_status'
check "launch.sh: H2S_HELPER set and empty: none" test "$(helper_for H2S_HELPER=)" = ""
check "… the checkout not asked" eval '! asked_status'
check "launch.sh: H2S_HELPER not a program: none" test "$(helper_for H2S_HELPER="$work/nothing")" = ""
echo stale > "$control/status"
echo "locked key" > "$work/runtime/h2s-shell-lock"
before=$(started)
check "launch.sh: the session locked by a shell that died: the checkout's build as it is" test "$(helper_for)" = "$work/own/h2s-helper"
check "… not rebuilt" no_build_since "$before"
rm "$work/runtime/h2s-shell-lock"
wait_for 10 settled

# ---- 4. Never as root ------------------------------------------------------------------
# The helper is the user's program: nothing that names it, its build or its path runs it
# through a way to become root (a privileged action goes through the root-helper path, from
# a root-owned location)
escalation='(pkexec|sudo|doas|run0|su -c)'
helper_names='(h2s-helper|build-helper|H2S_SHELL_HELPER|H2S_HELPER|H2S_SHELL_LIBEXEC|helper/src)'
near=$(cd "$REPO" && grep -rnE "$escalation.*$helper_names|$helper_names.*$escalation" \
    --include='*.sh' --include='*.qml' --include='*.nix' --include='*.cpp' --include='*.h' --include='*.txt' \
    scripts singletons helper nix install.sh shell.qml api components 2> /dev/null | grep -v ':[0-9]*:[[:space:]]*\(#\|//\)')
[ -z "$near" ] || printf '%s\n' "$near"
check "nothing runs the helper or its build through pkexec, sudo, doas, run0 or su" test -z "$near"
check "build-helper.sh refuses to run as root" grep -q 'id -u)" != 0 ] ||' "$REPO/scripts/build-helper.sh"

echo
if [ "$failed" = 0 ]; then echo "run-helper.sh: passed"; else echo "run-helper.sh: FAILED"; fi
exit "$failed"
