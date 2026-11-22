#!/usr/bin/env bash
# Checks tests/run-unit.sh's verdict against stand-in Quickshells (LOCKTEST_QS) that report
# the suites they are told to run (H2S_TEST_SUITES), each with three PASS lines, and end in a
# given way in the shard that runs FormatTest — the cases where a crash used to pass. Run on
# FormatTest, SidePanelTest and ModulesTest: three shards (the last two run alone,
# `ownProcess`), so the shards' verdicts and the one over them are both checked:
#
#   complete   every suite tests.qml registers, in its shards, all passed     → must pass
#              (and said how many shards; every suite reported once)
#   serial     -j 1: the same three shards one after another                  → must pass
#   crash      Format's summary, no FAIL line, then SIGSEGV (status 139)      → must fail
#   timeout    Format's summary, then the status of `timeout` (124)           → must fail
#   partial    Format does not report, exit 0                                 → must fail
#   empty      Format reports 0/0: it checked nothing                         → must fail
#   late       a PASS line no summary counts (a check made after its suite
#              reported)                                                      → must fail
#   mixed      -j 1: SidePanel's shard crashes, the shards after it cannot be
#              set up (the stand-in made itself unusable): a failure, not
#              "not run"                                                      → status 1
#   own-beside FormatTest and LockRulesTest in one shard, Format saying it
#              needs a process of its own (OWN-PROCESS)                       → must fail
#   inherited  H2S_UNIT_SHARD set from outside: a whole run still in shards   → must pass
#   capped     under a memory cap of 200M (H2S_TEST_MEMORY_MAX), Format's shard takes
#              400 MB after its summary: stopped, said to be killed at the memory cap,
#              naming the suite                                               → must fail
#
# with suites named to the runner (the `obedient` stand-in, which ends well everywhere):
#
#   selected   two named suites, both report                                  → must pass
#   logged     --log <file> with a named suite: the output is in the file     → must pass
#   logged-shards  --log <file> over three shards: all their output in it     → must pass
#   unknown    a name tests.qml does not register: status 2, nothing started
#   empty      an empty name, alone or beside a suite: status 2, nothing started
#   silent     one of two named suites does not report                        → must fail
#   extra      a suite that was not named reports as well                     → must fail
#   renamed    as many suites report as were named, one of them another suite → must fail
#   real       (the real Quickshell) FormatTest named: Format reports, alone  → must pass
#   limited    (the real Quickshell, a copy of the tree) a suite that never finishes, with
#              its own 2 s limit: fails as timed out at that limit             → must fail
#   leaky      (the same) a suite that leaves the shared state changed fails naming the keys
#              (an asynchronous one too, at most six named); one that puts it back passes;
#              one with a process of its own is not checked, and says so      → must fail
#   beside     (the same) two asynchronous suites in one process: the one that finishes
#              while the other has changed something for a while passes        → must pass
#   pinned     (the same) a suite that leaves a global setting behind, beside one that pins
#              another and puts back only what it pinned: the leak fails      → must fail
#
# tests/run-modules.sh with --suite, on the fixture module tests/fixtures/modules/good — the
# first two with the real Quickshell, so tests-modules.qml's part is checked too:
#
#   module-selected   one of its two suites named: that one reports, alone    → must pass
#   module-unknown    a name the module does not list: status 2, nothing run
#   module-extra      (stand-in) more suites report than were selected        → must fail
#   module-uncounted  (stand-in) a suite reports, but no line said how many   → must fail
#                     would: with --suite and without
#   module-empty      (stand-in) the one suite expected reports 0/0           → must fail
#
# the suite count against a small root file whose suites are written with and without
# arguments (`arguments`: each one must count), the suites a suite is given, read from the
# same file (`given`, `qualified`), a root file whose suites cannot be read reliably
# (`unbalanced`: said, not counted short), every suite's suiteName against its file name
# (`names`: a named suite is found by its suiteName followed by "Test"), the shard plan
# (`plan`: a suite with `ownProcess: true` alone, a suite and what it is given together, the
# others packed by their times, the longest first), and no suite of tests.qml given another
# (`unchained`: each builds its own state).
#
# and how the runner ends:
#
#   unreadable          a tests.qml like `unbalanced`: status 2, nothing started
#   interrupted         told to end while two shards' Quickshells run (-j 2): status
#                       130 at once, no process and no temp dir left, no shard started
#                       after
#   interrupted-twice   a Quickshell that ignores the request, and a second interrupt
#                       during the cleanup: the same
#
#   tests/run-unit-selftest.sh
#   UNIT_SELFTEST_KEEP=1 tests/run-unit-selftest.sh   the work dir kept, each case's log in it
#
# A case whose runner ends with another status than expected prints the runner's own reasons
# (its verdicts' lines), so that one failing now and then says why.
#
# It takes no lock, as the runner takes none: another run beside it shares only the
# processor. Each case starts the runner's private headless compositor (nothing shows); no shell runs
# (`real` runs tests.qml, the module cases tests-modules.qml). The tools are found as the
# runner finds them (tests/run-unit.sh), so the verdict is guarded with the pinned tools and
# with the system's.
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ut-self.XXXXXX") || exit 2
# remove_work: the work dir, unless UNIT_SELFTEST_KEEP=1 asks to keep it (each case's log,
# <case>.log, and the stand-ins); its path is said then
remove_work() {
    if [ "${UNIT_SELFTEST_KEEP:-0}" = 1 ]; then
        echo "kept: $work"
    else
        rm -rf "$work"
    fi
}
trap remove_work EXIT
# The shard plan's times: none (the defaults), never the user's
export H2S_UNIT_TIMES=$work/no-times
# shellcheck source=count-suites.sh
source "$REPO/tests/count-suites.sh"

expected=$(count_suites "$REPO/tests.qml")
[ "$expected" -gt 1 ] || { echo "cannot count the suites in tests.qml"; exit 2; }
suites_agree "$REPO/tests.qml" || { echo "cannot read the suites of tests.qml: its registration lines and the suites read from them differ in number"; exit 2; }

failures=0

# A suite that takes arguments counts like one that takes none
cat > "$work/arguments.qml" << 'QML'
Item {
    property var _plain: PlainTest {}
    property var _spaced: SpacedTest { }
    property var _ordered: OrderedTest { after: _plain; other: _spaced }
    property var _open: OpenTest {
        after: _ordered
    }
    property var _qualified: QualifiedTest { after: root._spaced }
    property var notASuite: Helper {}
    // property var _commented: CommentedTest {}
}
QML
counted=$(count_suites "$work/arguments.qml")
if [ "$counted" = 5 ] && suites_agree "$work/arguments.qml"; then
    echo "PASS arguments: 5 suites counted, and as many read"
else
    echo "FAIL arguments: $counted suites counted, $(registered_suites "$work/arguments.qml" | grep -c .) read, expected 5"
    failures=$((failures + 1))
fi

# What a suite is given brings it along, on its line or on the next ones, each suite once
needed=$(suites_with_needed "$work/arguments.qml" OpenTest PlainTest | tr '\n' ' ')
if [ "$needed" = "OpenTest PlainTest OrderedTest SpacedTest " ]; then
    echo "PASS given: OpenTest brings OrderedTest, PlainTest and SpacedTest"
else
    echo "FAIL given: OpenTest and PlainTest gave '$needed'"
    failures=$((failures + 1))
fi

# A suite named through the root object is given all the same
needed=$(suites_with_needed "$work/arguments.qml" QualifiedTest | tr '\n' ' ')
if [ "$needed" = "QualifiedTest SpacedTest " ]; then
    echo "PASS qualified: QualifiedTest brings SpacedTest"
else
    echo "FAIL qualified: QualifiedTest gave '$needed'"
    failures=$((failures + 1))
fi

# A brace in a string hides the suites after it from the reading that follows braces: the
# two counts differ, and that is what the runner refuses to start on
cat > "$work/unbalanced.qml" << 'QML'
Item {
    property var _first: FirstTest {
        label: "{"
    }
    property var _second: SecondTest {}
    property var _third: ThirdTest { after: _first }
}
QML
if [ "$(count_suites "$work/unbalanced.qml")" = 3 ] && ! suites_agree "$work/unbalanced.qml"; then
    echo "PASS unbalanced: 3 suites counted, the reading that differs is noticed"
else
    echo "FAIL unbalanced: $(count_suites "$work/unbalanced.qml") suites counted, $(registered_suites "$work/unbalanced.qml" | grep -c .) read, and no difference noticed"
    failures=$((failures + 1))
fi

# TestCase finds a named suite by its suiteName followed by "Test", the runner by its file
misnamed=""
for file in "$REPO"/tests/*Test.qml; do
    type=$(basename "$file" .qml)
    grep -q -E "^[[:space:]]*suiteName: \"${type%Test}\"[[:space:]]*$" "$file" || misnamed="$misnamed $type"
done
if [ -z "$misnamed" ]; then
    echo "PASS names: every suite's suiteName is its file name without Test"
else
    echo "FAIL names: suiteName is not the file name without Test in:$misnamed"
    failures=$((failures + 1))
fi

# The shard plan, on a root file of its own with suite files beside it: AloneTest says
# `ownProcess: true`; LongTest took 20 s last, MidATest and MidBTest 10 s; the others have no
# time (0.1 s each, synchronous), GiverTest is given TakerTest. Packed into ceil(40.4 / 20) =
# 3 shards, the longest first, each into the one with the least time so far
mkdir -p "$work/plan/tests"
{
    echo 'Item {'
    for type in Alone ShortA ShortB Long MidA MidB; do echo "    property var _${type,}: ${type}Test {}"; done
    echo '    property var _giver: GiverTest { after: _taker }'
    echo '    property var _taker: TakerTest {}'
    echo '}'
} > "$work/plan/root.qml"
for type in Alone ShortA ShortB Long MidA MidB Giver Taker; do echo "TestCase {}" > "$work/plan/tests/${type}Test.qml"; done
printf 'TestCase {\n    ownProcess:  true // a comment after it\n}\n' > "$work/plan/tests/AloneTest.qml"
printf 'LongTest 20000\nMidATest 10000\nMidBTest 10000\n' > "$work/plan/times"
planned=$(plan_shards "$work/plan/root.qml" "$work/plan/times" AloneTest ShortATest ShortBTest LongTest MidATest MidBTest GiverTest TakerTest | paste -s -d '|')
if [ "$planned" = "LongTest|MidATest GiverTest TakerTest|MidBTest ShortATest ShortBTest|AloneTest" ]; then
    echo "PASS plan: alone, given together, packed by time, the longest first"
else
    echo "FAIL plan: got '$planned'"
    failures=$((failures + 1))
fi
# Without times: short suites fill one shard (5 s at least), an asynchronous one weighs 5 s
printf 'TestCase {\n    asynchronous: true\n}\n' > "$work/plan/tests/LongTest.qml"
planned=$(plan_shards "$work/plan/root.qml" "" ShortATest ShortBTest LongTest | paste -s -d '|')
if [ "$planned" = "LongTest|ShortATest ShortBTest" ]; then
    echo "PASS plan: without times, short suites share a shard, an asynchronous one weighs 5 s"
else
    echo "FAIL plan: without times got '$planned'"
    failures=$((failures + 1))
fi

# No suite of tests.qml is given another: suites in other shards cannot wait for each other
chained=$(registered_suites "$REPO/tests.qml" | awk 'NF > 1')
if [ -z "$chained" ]; then
    echo "PASS unchained: no suite of tests.qml is given another"
else
    echo "FAIL unchained: given other suites: $chained"
    failures=$((failures + 1))
fi

# Reports the suites the runner selected (H2S_TEST_SUITES), under the names TestCase prints
# (the type without "Test"), each after three PASS lines; in the shard that runs FormatTest,
# <what then> is done before (it may change `names`) and <how it ends> after.
# `silent` leaves the last one out, `extra` adds one, `renamed` reports another suite in
# place of the last
selecting_stand_in() {
    {
        echo "#!$(command -v bash)"
        echo 'IFS=: read -r -a names <<< "${H2S_TEST_SUITES:-}"'
        echo 'format=""; [[ ":${H2S_TEST_SUITES:-}:" == *:FormatTest:* ]] && format=1'
        echo "$2"
        echo 'for name in "${names[@]}"; do for check in 1 2 3; do echo "  INFO:   PASS: check $check"; done; echo "  INFO: --- ${name%Test}: 3/3 passed"; done'
        echo "${3:-exit 0}"
    } > "$work/$1"
    chmod +x "$work/$1"
}
selecting_stand_in obedient ''
selecting_stand_in silent 'unset "names[-1]"'
selecting_stand_in extra 'names+=(UnnamedTest)'
selecting_stand_in renamed 'names[-1]=UnnamedTest'
selecting_stand_in crash '' '[ -n "$format" ] && kill -SEGV $$; exit 0'
selecting_stand_in timeout '' '[ -n "$format" ] && exit 124; exit 0'
selecting_stand_in partial '[ -n "$format" ] && names=("${names[@]/FormatTest/}") && names=(${names[@]})'
selecting_stand_in empty '' '[ -n "$format" ] && echo "  INFO: --- Empty: 0/0 passed ---"; exit 0'
selecting_stand_in late '' '[ -n "$format" ] && echo "  INFO:   PASS: a check after its suite reported"; exit 0'
selecting_stand_in capped '' '[ -n "$format" ] && s=$(head -c 419430400 /dev/zero | tr "\\0" x) && echo "allocated ${#s}"; exit 0'
selecting_stand_in own-beside '' '[ -n "$format" ] && echo "  INFO: OWN-PROCESS: Format"; exit 0'
# Crashes in SidePanel's shard, and makes itself no executable for the shards after it
selecting_stand_in mixed '' '[[ ":${H2S_TEST_SUITES:-}:" == *:SidePanelTest:* ]] && { chmod -x "$0"; kill -SEGV $$; }; exit 0'
three=(FormatTest SidePanelTest ModulesTest)

# runner_reasons <log>: why the runner ended as it did, in its own words — the lines of its
# verdicts that are not a suite's summary, and a set-up error (a line naming the runner) —
# so that a case failing now and then says why; the end of the log when there are none
runner_reasons() {
    local reasons
    reasons=$(grep -E -- "^  [^ -]|^$runner: " "$1" | grep -v -E -- '^  INFO:|^run-unit.sh: (running|[0-9]+ suites in)' | awk '!seen[$0]++' | head -n 20)
    [ -n "$reasons" ] || reasons=$(tail -n 6 "$1")
    printf '%s\n' "$reasons" | sed 's/^/    /'
}

# verdict <case> <stand-in, or "real" for the Quickshell the runners find> <expected status>
#         [<argument of the runner>…]: the runner is $runner
runner=run-unit.sh
verdict() {
    local name=$1 quickshell=$2 expected_status=$3 status
    shift 3
    if [ "$quickshell" = real ]; then
        "$REPO/tests/$runner" "$@" > "$work/$name.log" 2>&1
    else
        LOCKTEST_QS=$work/$quickshell "$REPO/tests/$runner" "$@" > "$work/$name.log" 2>&1
    fi
    status=$?
    if [ "$status" = "$expected_status" ]; then
        echo "PASS $name: $runner exited $status"
    else
        echo "FAIL $name: $runner exited $status, expected $expected_status"
        runner_reasons "$work/$name.log"
        failures=$((failures + 1))
    fi
}
# check <case> <what> <command…>: something else a case must show
check() {
    local name=$1 what=$2
    shift 2
    if "$@"; then
        echo "PASS $name: $what"
    else
        echo "FAIL $name: not so: $what"
        failures=$((failures + 1))
    fi
}
reports() { grep -q -- "--- $2: 3/3 passed" "$work/$1"; }
# The runner's verdict lists each suite that reported, indented
reports_only() {
    [ "$(grep -c -E -- '^  --- .* passed' "$work/$1")" = 1 ] && grep -q -E -- "^  --- $2: [0-9]+/[0-9]+ passed" "$work/$1"
}
reports_nothing() { ! grep -q -- "passed" "$work/$1"; }

verdict complete obedient 0
check complete "said it ran every suite in more than one shard" grep -q -E "^run-unit.sh: $expected suites in ([2-9]|[1-9][0-9]+) shards" "$work/complete.log"
# The verdict over the shards, the last block: each suite once
check complete "every suite reported once, in the verdict over the shards" \
    test "$(sed -n '/^Unit suites ([0-9]* s, [0-9]* shards/,$p' "$work/complete.log" | grep -c -E -- '^  --- .*: 3/3 passed$')" = "$expected"
verdict serial obedient 0 -j 1 "${three[@]}"
check serial "three shards, one at a time" grep -q "^run-unit.sh: 3 suites in 3 shards, at most 1 at once" "$work/serial.log"
verdict crash crash 1 "${three[@]}"
check crash "said which shard" grep -q "^  shard [0-9] (FormatTest) failed (status 1)" "$work/crash.log"
check crash "… and why" grep -q "^  quickshell exited with status 139" "$work/crash.log"
# The line under the shard's in the verdict over the shards (read whole, not piped into
# grep -q: under pipefail a writer cut off by grep's early end would fail the check)
reason_under_shard() {
    local under
    under=$(grep -A1 -E "^  shard [0-9]+ \($2\) failed \(status [0-9]+\):$" "$work/$1" | sed -n 2p)
    [ "$under" = "    $3" ]
}
# … only its start (prlimit's cap says more after the size)
reason_under_shard_starts() {
    local under
    under=$(grep -A1 -E "^  shard [0-9]+ \($2\) failed \(status [0-9]+\):$" "$work/$1" | sed -n 2p)
    [ "${under#"    $3"}" != "$under" ]
}
check crash "… and why again, under the shard in the verdict over the shards" \
    reason_under_shard crash.log FormatTest "quickshell exited with status 139"
verdict timeout timeout 1 "${three[@]}"
check timeout "said so" grep -q "^  quickshell timed out" "$work/timeout.log"
verdict partial partial 1 "${three[@]}"
check partial "said which suite, in its shard" grep -q "^  Format did not report" "$work/partial.log"
check partial "… and over the shards" grep -q "^  Format reported 0 times" "$work/partial.log"
verdict empty empty 1 "${three[@]}"
check empty "said which suite" grep -q "^  Empty ran no check (0/0)" "$work/empty.log"
verdict late late 1 "${three[@]}"
check late "said so" grep -q "checks passed, the suites' summaries count" "$work/late.log"
verdict mixed mixed 1 -j 1 "${three[@]}"
check mixed "said which shard failed" grep -q "^  shard [0-9] (SidePanelTest) failed (status 1)" "$work/mixed.log"
check mixed "… and which could not be set up" grep -q "^  shard [0-9] (.*) could not be set up" "$work/mixed.log"
verdict own-beside own-beside 1 FormatTest LockRulesTest
check own-beside "said so" grep -q "^  Format needs a process of its own, and 2 suites reported in it" "$work/own-beside.log"
H2S_UNIT_SHARD=1:1 verdict inherited obedient 0 "${three[@]}"
H2S_TEST_MEMORY_MAX=200M verdict capped capped 1 "${three[@]}"
if grep -q '^warning: no memory cap' "$work/capped.log"; then
    echo "SKIP capped: neither the user's service manager nor prlimit can be used here"
else
    check capped "said the cap" grep -q "^memory cap: 200M per process" "$work/capped.log"
    check capped "said Format's shard was killed at the memory cap, under the shard" \
        reason_under_shard_starts capped.log FormatTest "Format: killed at the memory cap (200M"
    check capped "… before it finished allocating" bash -c '! grep -q "^allocated" "$1"' _ "$work/capped.log"
fi
check inherited "still three shards" grep -q "^run-unit.sh: 3 suites in 3 shards" "$work/inherited.log"

verdict selected obedient 0 FormatTest LockRulesTest
check selected "FormatTest reported" reports selected.log Format
check selected "LockRulesTest reported" reports selected.log LockRules
verdict logged obedient 0 --log "$work/copy.log" FormatTest
check logged "the output is in the file" reports copy.log Format
verdict logged-shards obedient 0 --log "$work/copy-shards.log" "${three[@]}"
for name in Format SidePanel Modules; do check logged-shards "$name's output is in the file" reports copy-shards.log "$name"; done
verdict unknown obedient 2 FormatTest NoSuchTest
check unknown "no suite ran" reports_nothing unknown.log
verdict empty obedient 2 ""
check empty "no suite ran" reports_nothing empty.log
verdict empty-beside obedient 2 "" FormatTest
check empty-beside "no suite ran" reports_nothing empty-beside.log
verdict silent silent 1 FormatTest LockRulesTest
verdict extra extra 1 FormatTest
verdict renamed renamed 1 FormatTest LockRulesTest
verdict real real 0 FormatTest
check real "Format reported, alone" reports_only real.log "Format"

# tree_copy <dir>: a copy of the tree to put suites of its own into. The runner takes its tree
# from where it is, so the copy has run-unit.sh itself and a tests.qml of its own (written by
# the case); the rest of the tree is linked.
tree_copy() {
    local directory=$1 entry
    mkdir -p "$directory/tests"
    for entry in "$REPO"/* "$REPO"/.[!.]*; do
        case "${entry##*/}" in tests.qml|tests|.git) continue ;; esac
        ln -s "$entry" "$directory/${entry##*/}"
    done
    for entry in "$REPO"/tests/*; do ln -s "$entry" "$directory/tests/${entry##*/}"; done
    rm "$directory/tests/run-unit.sh"
    cp "$REPO/tests/run-unit.sh" "$directory/tests/"
}
# with_suites <dir> <type>…: the copy's tests.qml, tests.qml with those suites registered too
with_suites() {
    local directory=$1 type lines=""
    shift
    for type in "$@"; do lines="$lines    property var _${type,}: ${type} {}\\n"; done
    sed -e "s/^\(    property var _promises: PromisesTest {}\)$/${lines}\1/" "$REPO/tests.qml" > "$directory/tests.qml"
}

# limited: an asynchronous suite that never finishes and sets its own limit (2 s) fails as
# timed out at that limit, not at the runner's default
tree_copy "$work/limited"
cat > "$work/limited/tests/HungTest.qml" << 'QML'
TestCase {
    suiteName: "Hung"
    asynchronous: true
    timeLimitMs: 2000
}
QML
with_suites "$work/limited" HungTest
limited_started=$SECONDS
"$work/limited/tests/run-unit.sh" HungTest > "$work/limited.log" 2>&1
limited_status=$?
limited_took=$((SECONDS - limited_started))
check limited "run-unit.sh exited 1 (it exited $limited_status)" test "$limited_status" = 1
check limited "the suite failed as timed out at its own limit" grep -q "FAIL: timed out (2 s)" "$work/limited.log"
check limited "… well before the runner's default (it took ${limited_took} s)" test "$limited_took" -lt 60

# leaky: (the real Quickshell, a copy of the tree) a suite that leaves the shared state
# changed fails, naming what changed; one that puts it back passes; an asynchronous one is
# checked when it reports, at most six keys named; one with a process of its own is not
# checked, and says so
tree_copy "$work/leaky"
cat > "$work/leaky/tests/LeakyTest.qml" << 'QML'
import qs.singletons
TestCase {
    suiteName: "Leaky"
    function run() {
        Config.disabledModules = ["leaky"];
        assert(true, "changed the modules turned off");
    }
}
QML
cat > "$work/leaky/tests/TidyTest.qml" << 'QML'
import qs.singletons
TestCase {
    suiteName: "Tidy"
    function run() {
        // A copy: a list property read is the live list
        const saved = Array.from(Config.disabledModules);
        Config.disabledModules = ["tidy"];
        assert(true, "changed the modules turned off");
        Config.disabledModules = saved;
    }
}
QML
cat > "$work/leaky/tests/ManyTest.qml" << 'QML'
import QtQuick
import qs.singletons
TestCase {
    suiteName: "Many"
    asynchronous: true
    function runAsync() {
        Config.sleepLockNotice = "many";
        Config.moduleUpdates = "many";
        Config.screensOff = ["many"];
        Config.gcal.viewMode = "many";
        Config.audio.appVolumes = "many";
        Config.network.vpnMemory = "many";
        Notifier.recordOnly = !Notifier.recordOnly;
        Theme.nerdFontWarningDismissed = !Theme.nerdFontWarningDismissed;
        Qt.callLater(() => { assert(true, "changed eight things"); finish(); });
    }
}
QML
cat > "$work/leaky/tests/OwnLeakyTest.qml" << 'QML'
import qs.singletons
TestCase {
    suiteName: "OwnLeaky"
    ownProcess: true
    function run() {
        Config.disabledModules = ["own"];
        assert(true, "changed the modules turned off");
    }
}
QML
with_suites "$work/leaky" LeakyTest TidyTest ManyTest OwnLeakyTest
"$work/leaky/tests/run-unit.sh" LeakyTest TidyTest ManyTest OwnLeakyTest > "$work/leaky.log" 2>&1
leaky_status=$?
check leaky "run-unit.sh exited 1 (it exited $leaky_status)" test "$leaky_status" = 1
check leaky "the suite that leaked failed, naming what" grep -q "FAIL: left Config.disabledModules changed$" "$work/leaky.log"
check leaky "… and counted it" grep -q -- "^  --- Leaky: 1/2 passed, 1 FAILED" "$work/leaky.log"
check leaky "the suite that put it back passed" grep -q -- "^  --- Tidy: 1/1 passed" "$work/leaky.log"
check leaky "the asynchronous one failed, six keys named and the rest counted" \
    grep -q "FAIL: left Config.audio.appVolumes, Config.gcal.viewMode, Config.moduleUpdates, Config.network.vpnMemory, Config.screensOff, Config.sleepLockNotice and 2 more changed$" "$work/leaky.log"
check leaky "the one with a process of its own passed" grep -q -- "^  --- OwnLeaky: 1/1 passed" "$work/leaky.log"
check leaky "… and said it was not checked" grep -q "SHARED-STATE: not checked for OwnLeaky: it runs in a process of its own" "$work/leaky.log"

# beside: (the same) two asynchronous suites in one process (one is given the other): the one
# that finishes first while the other has changed something for a while is not blamed for it
tree_copy "$work/beside"
cat > "$work/beside/tests/WhileTest.qml" << 'QML'
import QtQuick
import qs.singletons
TestCase {
    suiteName: "While"
    asynchronous: true
    property var saved: []
    property Timer later: Timer { interval: 500; onTriggered: { Config.enabledModules = saved; finish(); } }
    function runAsync() {
        saved = Array.from(Config.enabledModules);
        Config.enabledModules = ["while"];
        assert(true, "changed the built-in modules turned on, for a while");
        later.start();
    }
}
QML
cat > "$work/beside/tests/QuickTest.qml" << 'QML'
import QtQuick
TestCase {
    suiteName: "Quick"
    asynchronous: true
    property var other: null
    function runAsync() {
        Qt.callLater(() => { assert(true, "changed nothing"); finish(); });
    }
}
QML
sed -e 's/^\(    property var _promises: PromisesTest {}\)$/    property var _while: WhileTest {}\n    property var _quick: QuickTest { other: _while }\n\1/' "$REPO/tests.qml" > "$work/beside/tests.qml"
"$work/beside/tests/run-unit.sh" QuickTest > "$work/beside.log" 2>&1
beside_status=$?
check beside "run-unit.sh exited 0 (it exited $beside_status)" test "$beside_status" = 0
check beside "both ran in one process" grep -q "^Unit suites ([0-9]* s, quickshell exit 0)" "$work/beside.log"
check beside "the one that finished first passed" grep -q -- "^  --- Quick: 1/1 passed" "$work/beside.log"

# pinned: (the same) a suite that leaves a global setting behind, beside one that pins
# another for a while and puts back only what it pinned (GlobalsPin): the leak is still seen
tree_copy "$work/pinned"
cat > "$work/pinned/tests/LeakBesideTest.qml" << 'QML'
import QtQuick
import qs.singletons
TestCase {
    suiteName: "LeakBeside"
    asynchronous: true
    function runAsync() {
        const globals = JSON.parse(Config.globals || "{}");
        globals["general.debug"] = true;
        Config.globals = JSON.stringify(globals);
        Qt.callLater(() => { assert(true, "left a global setting behind"); finish(); });
    }
}
QML
cat > "$work/pinned/tests/PinnerTest.qml" << 'QML'
import QtQuick
TestCase {
    suiteName: "Pinner"
    asynchronous: true
    property var other: null
    property GlobalsPin pin: GlobalsPin {}
    property Timer later: Timer { interval: 500; onTriggered: { pin.restore(); finish(); } }
    function runAsync() {
        pin.use({ "notifications.toasts": false });
        assert(true, "pinned a global setting for a while");
        later.start();
    }
}
QML
sed -e 's/^\(    property var _promises: PromisesTest {}\)$/    property var _leakBeside: LeakBesideTest {}\n    property var _pinner: PinnerTest { other: _leakBeside }\n\1/' "$REPO/tests.qml" > "$work/pinned/tests.qml"
"$work/pinned/tests/run-unit.sh" PinnerTest > "$work/pinned.log" 2>&1
pinned_status=$?
check pinned "run-unit.sh exited 1 (it exited $pinned_status)" test "$pinned_status" = 1
check pinned "the suite that leaked failed, naming the globals" grep -q "FAIL: left Config.globals, Profiles.globals changed" "$work/pinned.log"
check pinned "… counted on it" grep -q -- "^  --- LeakBeside: 1/2 passed, 1 FAILED" "$work/pinned.log"

runner=run-modules.sh
good=$REPO/tests/fixtures/modules/good
verdict module-selected real 0 --suite GoodStateTest "$good"
check module-selected "GoodStateTest reported, alone" reports_only module-selected.log "good: GoodState"
verdict module-unknown real 2 --suite GoodStateTest --suite NoSuchTest "$good"
check module-unknown "no suite ran" reports_nothing module-unknown.log
{
    echo "#!$(command -v bash)"
    echo "echo 'MODULE-SUITES-EXPECTED: 1'"
    echo "echo '  INFO: --- one: 3/3 passed ---'"
    echo "echo '  INFO: --- another: 3/3 passed ---'"
} > "$work/module-extra"
chmod +x "$work/module-extra"
verdict module-extra module-extra 1 --suite GoodStateTest "$good"
{
    echo "#!$(command -v bash)"
    echo "echo '  INFO: --- good: GoodState: 5/5 passed ---'"
} > "$work/module-uncounted"
chmod +x "$work/module-uncounted"
verdict module-uncounted module-uncounted 1 --suite GoodStateTest "$good"
check module-uncounted "said so" grep -q "no MODULE-SUITES-EXPECTED line" "$work/module-uncounted.log"
verdict module-uncounted-all module-uncounted 1 "$good"
{
    echo "#!$(command -v bash)"
    echo "echo 'MODULE-SUITES-EXPECTED: 1'"
    echo "echo '  INFO: --- good: GoodState: 0/0 passed ---'"
} > "$work/module-empty"
chmod +x "$work/module-empty"
verdict module-empty module-empty 1 "$good"
check module-empty "said which suite" grep -q "^  good: GoodState ran no check (0/0)" "$work/module-empty.log"

# unreadable: a tests.qml whose suites cannot be read reliably (the `unbalanced` file) ends
# the runner with status 2 before anything is started, with and without a name. The runner
# takes its tree from where it is, so a copy of it beside that file reads that file (and
# has no headless.sh to start anything with).
mkdir -p "$work/tree/tests"
cp "$REPO/tests/run-unit.sh" "$REPO/tests/count-suites.sh" "$work/tree/tests/"
cp "$work/unbalanced.qml" "$work/tree/tests.qml"
refuses_unreadable() {
    "$work/tree/tests/run-unit.sh" "$@" > "$work/unreadable.log" 2>&1
    [ $? = 2 ] && grep -q "^run-unit.sh: cannot read the suites of tests.qml: .*nothing was run" "$work/unreadable.log" \
        && [ "$(grep -c . "$work/unreadable.log")" = 1 ]
}
check unreadable "run-unit.sh exited 2 and said why, nothing else" refuses_unreadable
check unreadable "… with a suite named too" refuses_unreadable FirstTest

# interrupted: the runner is told to end while two shards' Quickshells run (-j 2; a stand-in
# that never ends). It ends at once with status 130 and leaves nothing: not a Quickshell, not
# a compositor, not a temp dir, and starts no other shard. TERM stands for an interrupt here: a command a script starts
# in the background ignores INT.
# interrupted-twice: a Quickshell that does not end when told to (TERM ignored), and a
# second interrupt while the runner is stopping it: the runner still leaves nothing.
{
    echo "#!$(command -v bash)"
    # Asked for its version (the runner's first lines), it only ends
    echo '[ "${1:-}" = --version ] && exit 0'
    echo "echo \"\$XDG_RUNTIME_DIR\" >> '$work/sleeper.started'"
    echo "exec sleep 200"
} > "$work/sleeper"
{
    echo "#!$(command -v bash)"
    echo '[ "${1:-}" = --version ] && exit 0'
    # Says when it was told to end, which is when the runner has begun to clean up
    echo "trap \"echo told > '$work/stubborn.told'\" TERM"
    echo "(trap '' TERM; exec sleep 200) &"
    echo "echo \"\$XDG_RUNTIME_DIR\" >> '$work/stubborn.started'"
    echo 'while kill -0 $! 2> /dev/null; do wait; done'
} > "$work/stubborn"
chmod +x "$work/sleeper" "$work/stubborn"

runner_pid=""
runner_processes=()
runner_dirs=()
# descendants <pid>: its children and theirs, to any depth
descendants() {
    local child
    for child in $(pgrep -P "$1"); do
        echo "$child"
        descendants "$child"
    done
}
none_left() {
    local process
    for process in "${runner_processes[@]}"; do kill -0 "$process" 2> /dev/null && return 1; done
    return 0
}
# Whatever of a case's runner is still there, and its temp dir: after the case, and when
# this script is ended in the middle of one. The runner is asked first — it stops what it
# started, also what was not written down here yet — then the pids written down are killed.
stop_runner() {
    local process
    if [ -n "$runner_pid" ] && kill -TERM "$runner_pid" 2> /dev/null; then
        for _ in $(seq 1 50); do kill -0 "$runner_pid" 2> /dev/null || break; sleep 0.1; done
    fi
    for process in $runner_pid "${runner_processes[@]}"; do
        kill -0 "$process" 2> /dev/null && kill -KILL "$process" 2> /dev/null
    done
    [ -n "$runner_pid" ] && wait "$runner_pid" 2> /dev/null
    for directory in "${runner_dirs[@]}"; do
        case "$directory" in /tmp/ut.*) rm -rf "$directory" ;; esac
    done
    runner_pid=""
    runner_processes=()
    runner_dirs=()
}
trap 'trap "" INT TERM HUP; stop_runner; remove_work' EXIT

# interrupt <case> <stand-in> <processes it makes the runner have> [twice]
interrupt() {
    local name=$1 quickshell=$2 expected_processes=$3 twice=${4:-} status
    local directory present
    LOCKTEST_QS=$work/$quickshell "$REPO/tests/run-unit.sh" -j 2 > "$work/$name.log" 2>&1 &
    runner_pid=$!
    for _ in $(seq 1 1200); do
        [ "$(grep -c . "$work/$quickshell.started" 2> /dev/null)" = 2 ] && break
        kill -0 "$runner_pid" 2> /dev/null || break
        sleep 0.1
    done
    # The shards, and in each timeout and the compositor, timeout and Quickshell (and what
    # Quickshell started)
    mapfile -t runner_processes < <(descendants "$runner_pid")
    runner_dirs=()
    while read -r directory; do runner_dirs+=("$(dirname "$directory")"); done < "$work/$quickshell.started"
    present() { [ ${#runner_dirs[@]} = 2 ] && test -d "${runner_dirs[0]}" -a -d "${runner_dirs[1]}" -a "${runner_dirs[0]}" != "${runner_dirs[1]}"; }
    check "$name" "two Quickshells were running, each in its shard's temp dir" present
    check "$name" "the compositors and Quickshells are the runner's processes" test "${#runner_processes[@]}" -ge "$expected_processes"
    kill -TERM "$runner_pid" 2> /dev/null
    if [ -n "$twice" ]; then
        for _ in $(seq 1 100); do [ -s "$work/$quickshell.told" ] && break; sleep 0.1; done
        check "$name" "Quickshell was told to end: the runner is cleaning up" test -s "$work/$quickshell.told"
        kill -TERM "$runner_pid" 2> /dev/null
    fi
    for _ in $(seq 1 100); do kill -0 "$runner_pid" 2> /dev/null || break; sleep 0.1; done
    if kill -0 "$runner_pid" 2> /dev/null; then
        echo "FAIL $name: run-unit.sh still runs 10 s after the interrupt"
        failures=$((failures + 1))
    else
        wait "$runner_pid"
        status=$?
        check "$name" "run-unit.sh exited 130" test "$status" = 130
        check "$name" "none of its processes is left" none_left
        check "$name" "the shards' temp dirs are gone" test ! -e "${runner_dirs[0]:-/nonexistent}" -a ! -e "${runner_dirs[1]:-/nonexistent}"
        check "$name" "no other shard was started" test "$(grep -c . "$work/$quickshell.started")" = 2
    fi
    stop_runner
}
interrupt interrupted sleeper 8
interrupt interrupted-twice stubborn 10 twice
[ "$failures" = 0 ]
