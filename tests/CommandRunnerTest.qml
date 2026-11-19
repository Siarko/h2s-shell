import QtQuick
import qs.singletons
import qs.singletons.io as Io
import qs.api as Api

// The command runner (singletons/io/CommandRunner.qml) against `sh -c` scripts: answers,
// output, time limits with coreutils' `timeout` and without, cancelling, a runner that goes.
// CommandAction and CommandQuery, which run on it, keep what they promise.
TestCase {
    id: suite
    suiteName: "CommandRunner"
    asynchronous: true

    property var _steps: []

    function _then(description, condition, action) {
        _steps.push({ description: description, condition: condition, action: action });
    }

    property Timer _clock: Timer {
        interval: 20
        repeat: true
        property int waited: 0
        onTriggered: {
            const step = suite._steps[0];
            if (!step) {
                stop();
                suite.finish();
                return;
            }
            waited += interval;
            let ready = false;
            try {
                ready = step.condition();
            } catch (error) {}
            if (!ready && waited < 10000)
                return;
            waited = 0;
            suite._steps.shift();
            if (!ready)
                suite.fail("timed out waiting: " + step.description);
            try {
                step.action();
            } catch (error) {
                suite.fail("threw in \"" + step.description + "\": " + error);
            }
        }
    }

    // Stand-ins for CommandTools: neither program on this system, `timeout` alone, and a
    // look-up not answered yet
    property QtObject _noTimeout: QtObject {
        property bool known: true
        property string timeout: ""
        property string setpriv: ""
    }
    property QtObject _noSetpriv: QtObject {
        property bool known: true
        property string timeout: CommandTools.timeout
        property string setpriv: ""
    }
    property QtObject _lookingUp: QtObject {
        property bool known: false
        property string timeout: ""
        property string setpriv: ""
    }

    // Inside `timeout` (the real one, found by CommandTools), bare, and waiting for the look-up
    property Io.CommandRunner wrapping: Io.CommandRunner {
        environment: ({ RUNNER_ONLY: "runner", BOTH: "runner" })
    }
    property Io.CommandRunner bare: Io.CommandRunner {
        tools: suite._noTimeout
    }
    property Io.CommandRunner halfWrapping: Io.CommandRunner {
        tools: suite._noSetpriv
    }
    property Io.CommandRunner waiting: Io.CommandRunner {
        tools: suite._lookingUp
    }
    property Api.CommandRunner api: Api.CommandRunner {}
    // A runner whose guard records the words it judged (CommandRunner.refuse)
    property var _judged: []
    property Io.CommandRunner guarded: Io.CommandRunner {
        refuse: argv => {
            suite._judged.push(argv.slice());
            return "";
        }
    }

    property Component _runnerComponent: Component {
        Io.CommandRunner {}
    }

    // A runner whose processes report, inside `running = true`, that they cannot start —
    // as Quickshell may for a failure found before the program is forked (every argv tried
    // here is reported later): the answer then waits for the runner's flush
    property Component _unstartableRunner: Component {
        Io.CommandRunner {
            id: unstartable
            tools: suite._noTimeout
            _runComponent: Component {
                QtObject {
                    id: run
                    property var job: null
                    property QtObject process: QtObject {
                        property var command: []
                        property var environment: ({})
                        property bool running: false
                        property int processId: 0
                        function signal(number) {}
                        onRunningChanged: {
                            if (running)
                                running = false;
                            else
                                unstartable._dispatch(run.job, { type: "stopped" });
                        }
                    }
                    property Timer watchdog: Timer {}
                    property Timer kill: Timer {}
                }
            }
        }
    }

    property Io.CommandAction action: Io.CommandAction {}
    property Io.CommandQuery query: Io.CommandQuery {
        onDone: lines => suite._queried.push(lines)
    }
    property var _queried: []
    property Io.LatestQuery latest: Io.LatestQuery {
        onAnswered: (lines, result) => suite._latest.push({ lines: lines, ok: result.ok, code: result.code, stderr: result.stderr })
    }
    property var _latest: []
    property var _actions: []

    // name → { handle, result, answers, lines: [[line, stream]…], out: [chunk…], err: […] }
    property var _runs: ({})
    property var _spareRunners: []

    function _start(name, runner, argv, options) {
        const record = { handle: null, result: null, answers: 0, lines: [], out: [], err: [], insideStart: true };
        _runs[name] = record;
        record.handle = runner.start(argv, Object.assign({
            onStdout: text => record.out.push(text),
            onStderr: text => record.err.push(text),
            onLine: (line, stream) => record.lines.push([line, stream]),
            done: result => {
                record.answers++;
                record.result = result;
                record.answeredInsideStart = record.insideStart;
            }
        }, options ?? {}));
        record.insideStart = false;
        return record;
    }

    function _answered() {
        for (let i = 0; i < arguments.length; i++) {
            if (!_runs[arguments[i]] || _runs[arguments[i]].result === null)
                return false;
        }
        return true;
    }

    function _has(name, line) {
        return _runs[name].lines.some(entry => entry[0] === line);
    }

    // Prints the program its parent was started as: the first word of its command line
    // (not the process's name, which coreutils as one program for all its tools sets to
    // the path it was called by, cut short)
    readonly property string _parentProgram: "tr '\\0' '\\n' < /proc/$PPID/cmdline | head -n 1"
    // A script that tells it runs, shrugs TERM off, and goes on until it is killed
    readonly property string _stubborn: "trap '' TERM; echo \"$$\"; while :; do sleep 0.05; done"
    // Ends when the process is gone
    readonly property string _untilGone: "while kill -0 \"$1\" 2>/dev/null; do sleep 0.05; done; echo gone"

    function runAsync() {
        _then("the look-up of timeout answered", () => CommandTools.known, () => {
            assert(CommandTools.timeout.startsWith("/") && CommandTools.timeout.endsWith("/timeout"), "coreutils' timeout found on PATH and trusted: " + CommandTools.timeout);
            assert(CommandTools.setpriv.startsWith("/") && CommandTools.setpriv.endsWith("/setpriv"), "util-linux's setpriv found on PATH and trusted: " + CommandTools.setpriv);
            _plain();
        });
        _clock.start();
    }

    // ---- answers and output ----
    function _plain() {
        _start("exit", wrapping, ["sh", "-c", "printf 'a b\\n\\nc'; printf 'oops\\n' >&2; exit 3"]);
        _start("words", wrapping, ["sh", "-c", "printf '%s|%s|%s|%s' \"$1\" \"$2\" \"$RUNNER_ONLY\" \"$BOTH\"", "sh", "two words", "$HOME; `id`"],
               { environment: { BOTH: "run" } });
        _start("parent", wrapping, ["sh", "-c", _parentProgram]);
        _start("parentNoLimit", wrapping, ["sh", "-c", _parentProgram], { timeoutMs: 0 });
        _start("parentNoSetpriv", halfWrapping, ["sh", "-c", _parentProgram]);
        _start("notKept", wrapping, ["sh", "-c", "echo out; echo err >&2"], { keepOutput: false });
        _start("capped", wrapping, ["sh", "-c", "head -c 5000 /dev/zero | tr '\\0' x; echo; echo short"], { maxOutputBytes: 1000 });
        const blanks = ["\\n\\na\\n", "a\\n\\n\\nb", "\\n", "a\\n\\nb\\n\\n\\nc\\n"];
        blanks.forEach((text, index) => _start("blank" + index, wrapping, ["printf", text]));
        _start("signalled", wrapping, ["sh", "-c", "kill -KILL $$"], { timeoutMs: 0 });
        _start("throws", wrapping, ["sh", "-c", "echo one; echo two"], {
            onLine: (line, stream) => {
                _runs.throws.lines.push([line, stream]);
                throw new Error("a module's mistake");
            }
        });
        // A word that answers one thing at its first read and another after: the guard
        // judges, and the process gets, the same copy
        const switching = ["sh", "-c", "printf %s \"$1\"", "sh", "first"];
        let switchReads = 0;
        Object.defineProperty(switching, 4, { get() { return ++switchReads === 1 ? "first" : "second"; }, enumerable: true });
        _start("readOnce", guarded, switching);
        const before = _runs.exit;
        assert(before.handle.running && before.result === null, "start(): a handle, running, no answer inside start()");
        assertEqual(wrapping.running, 12, "the runner counts its runs");

        _then("the plain runs answered", () => _answered("exit", "readOnce", "words", "parent", "parentNoLimit", "notKept", "parentNoSetpriv", "capped", "signalled", "throws", "blank0", "blank1", "blank2", "blank3"), () => {
            const exit = _runs.exit.result;
            assertEqual(exit.ok + " " + exit.code + " " + exit.failedToStart + " " + exit.timedOut + " " + exit.cancelled + " " + exit.error,
                        "false 3 false false false ", "exit 3: not ok, the code, nothing else said");
            assertEqual(exit.stdout, "a b\n\nc", "stdout: its lines, no line break after the last");
            assertEqual(exit.stderr, "oops", "stderr apart from it");
            assertEqual(JSON.stringify(_runs.exit.lines.filter(entry => entry[1] === "stdout").map(entry => entry[0])), "[\"a b\",\"\",\"c\"]",
                        "onLine: each line, an empty one, the last one without its newline");
            assertEqual(JSON.stringify(_runs.exit.lines.filter(entry => entry[1] === "stderr")), "[[\"oops\",\"stderr\"]]", "… stderr's lines named as such");
            assertEqual(_runs.exit.out.join("") + "|" + _runs.exit.err.join(""), "a b\n\nc\n|oops\n", "onStdout, onStderr: each line of theirs with its line break");
            assert(Object.isFrozen(exit) && exit.durationMs >= 0, "the answer is frozen");
            assert(!_runs.exit.handle.running, "the handle: not running after the answer");
            assertEqual(_runs.exit.answers, 1, "done once");

            assertEqual(_runs.readOnce.result.stdout + " " + JSON.stringify(suite._judged.map(argv => argv[4])), "first [\"first\"]",
                        "argv read once: the word the guard judged is the word that ran");
            assertEqual(_runs.words.result.stdout, "two words|$HOME; `id`|runner|run", "words kept whole, no shell reads them; the runner's environment, the run's on top");
            assert(_runs.words.result.ok, "exit 0: ok");
            assertEqual(_runs.parent.result.stdout, CommandTools.timeout, "a run with a limit is started inside timeout");
            assert(_runs.parentNoLimit.result.ok && !_runs.parentNoLimit.result.stdout.endsWith("/timeout"), "one without a limit is not");
            assert(_runs.parentNoSetpriv.result.ok && !_runs.parentNoSetpriv.result.stdout.endsWith("/timeout"),
                   "… nor one with a limit where setpriv is missing: it would outlive its timeout");

            assertEqual(_runs.notKept.result.stdout + "|" + _runs.notKept.result.stderr + "|" + _runs.notKept.lines.length, "||2", "keepOutput false: the answer holds none, the callbacks got it");
            const capped = _runs.capped.result;
            assertEqual(capped.stdout.length + " " + capped.truncated + " " + capped.ok, "1000 true true", "over the cap: the kept output cut, said, the run itself fine");
            assertEqual(_runs.capped.out.join("").length, 5007, "… the chunk callback still got everything");
            assertEqual(_runs.capped.lines.map(entry => entry[0].length).join(), "1000,5", "… a line over the cap handed over cut once, the next one whole");

            assertEqual([0, 1, 2, 3].map(index => JSON.stringify(_runs["blank" + index].lines.map(entry => entry[0]))).join(" "),
                        "[\"\",\"\",\"a\"] [\"a\",\"\",\"\",\"b\"] [\"\"] [\"a\",\"\",\"b\",\"\",\"\",\"c\"]", "empty lines: each one a line, at the start and between others");
            assertEqual(JSON.stringify(_runs.blank1.result.stdout), "\"a\\n\\n\\nb\"", "… and kept");
            const signalled = _runs.signalled.result;
            assertEqual(signalled.ok + " " + signalled.code + " " + signalled.failedToStart, "false -1 false", "ended by a signal: no exit status, not a failure to start");
            assertEqual(_runs.throws.lines.length + " " + _runs.throws.result.ok, "2 true", "a callback that throws: the run goes on and is answered");
            assertEqual(wrapping.running, 0, "all answered: the runner counts none");
            _cannotStart();
        });
    }

    // ---- a program that cannot start, a command that cannot be one ----
    function _cannotStart() {
        _start("missingBare", bare, ["/nonexistent/h2s-test-program", "x"]);
        _start("missingWrapped", wrapping, ["/nonexistent/h2s-test-program", "x"]);
        _start("empty", wrapping, []);
        _start("text", wrapping, "ls -l");
        _start("number", wrapping, ["sleep", 1]);
        _start("badLimit", wrapping, ["sh", "-c", "echo ran"], { timeoutMs: -1 });
        _start("badCallback", wrapping, ["sh", "-c", "echo ran"], { onLine: "print" });
        assert(!_runs.empty.handle.running && _runs.empty.result === null, "a command that cannot be one: no answer inside start()");
        // Cancelled while their answers wait for the flush: refused, and a program reported
        // as unable to start inside start()
        _start("refusedCancelled", wrapping, []);
        const missingOne = _unstartableRunner.createObject(suite);
        _start("missingCancelled", missingOne, ["/nonexistent/h2s-test-program", "x"]);
        assert(!_runs.refusedCancelled.handle.running && !_runs.missingCancelled.handle.running
               && _runs.refusedCancelled.result === null && _runs.missingCancelled.result === null,
               "a refused run and one that cannot start: done inside start(), their answers queued");
        _runs.refusedCancelled.handle.cancel();
        _runs.missingCancelled.handle.cancel();
        // The same through cancelAll(), on a runner of their own
        const refusedAll = _runnerComponent.createObject(suite);
        const missingAll = _unstartableRunner.createObject(suite);
        suite._spareRunners = [missingOne, refusedAll, missingAll];
        _start("refusedCancelAll", refusedAll, ["sh", 1]);
        _start("missingCancelAll", missingAll, ["/nonexistent/h2s-test-program"]);
        refusedAll.cancelAll();
        missingAll.cancelAll();

        _then("the runs that cannot start answered", () => _answered("missingBare", "missingWrapped", "empty", "text", "number", "badLimit", "badCallback",
                                                                 "refusedCancelled", "missingCancelled", "refusedCancelAll", "missingCancelAll"), () => {
            const missing = _runs.missingBare.result;
            assertEqual(missing.failedToStart + " " + missing.ok + " " + missing.code + " " + missing.timedOut, "true false -1 false", "a program that is not there, bare: failedToStart, once");
            assertEqual(_runs.missingBare.answeredInsideStart, false, "… answered after start() returned");
            assertEqual(_runs.missingBare.answers, 1, "… once");
            const wrapped = _runs.missingWrapped.result;
            assertEqual(wrapped.failedToStart + " " + wrapped.ok + " " + wrapped.code, "true false 127", "… inside timeout: failedToStart, timeout's 127");
            for (const name of ["empty", "text", "number", "badLimit", "badCallback"]) {
                const result = _runs[name].result;
                assert(result.error !== "" && !result.ok && !result.failedToStart && result.code === -1 && result.stdout === "", name + ": refused with `error` set — " + result.error);
            }
            assertEqual(_runs.badLimit.lines.length + _runs.badCallback.out.length, 0, "… and nothing run");
            assertEqual(wrapping.running + bare.running, 0, "… none of them counted any more");
            for (const name of ["refusedCancelled", "refusedCancelAll"]) {
                const record = _runs[name];
                assertEqual(record.result.cancelled + " " + record.result.ok + " " + (record.result.error !== "") + " " + record.answers + " " + record.answeredInsideStart,
                            "true false true 1 false", name + ": refused, cancelled before its answer — answered once, cancelled, the reason kept");
            }
            for (const name of ["missingCancelled", "missingCancelAll"]) {
                const record = _runs[name];
                assertEqual(record.result.cancelled + " " + record.result.failedToStart + " " + record.result.ok + " " + record.answers + " " + record.answeredInsideStart,
                            "true true false 1 false", name + ": cannot start, cancelled before its answer — answered once, cancelled");
            }
            assertEqual(_runs.missingBare.result.cancelled + " " + _runs.empty.result.cancelled, "false false", "… the ones not cancelled answer as before");
            for (const runner of suite._spareRunners)
                runner.destroy();
            suite._spareRunners = [];
            _limits();
        });
    }

    // ---- time limits ----
    function _limits() {
        _start("limitWrapped", wrapping, ["sh", "-c", "echo started; sleep 30"], { timeoutMs: 300 });
        _start("limitBare", bare, ["sh", "-c", "echo started; exec sleep 30"], { timeoutMs: 300 });
        _start("stubbornWrapped", wrapping, ["sh", "-c", _stubborn], { timeoutMs: 300, killAfterMs: 200 });
        _start("stubbornBare", bare, ["sh", "-c", _stubborn], { timeoutMs: 300, killAfterMs: 200 });
        _start("inTime", bare, ["sh", "-c", "echo quick"], { timeoutMs: 5000 });
        _start("limitNoSetpriv", halfWrapping, ["sh", "-c", "echo started; exec sleep 30"], { timeoutMs: 300 });

        _then("the runs past their limit answered", () => _answered("limitWrapped", "limitBare", "stubbornWrapped", "stubbornBare", "inTime", "limitNoSetpriv"), () => {
            const wrapped = _runs.limitWrapped.result;
            assertEqual(wrapped.timedOut + " " + wrapped.ok + " " + wrapped.code + " " + wrapped.cancelled, "true false 124 false", "past the limit, inside timeout: timedOut, timeout's 124");
            assert(wrapped.durationMs >= 300 && wrapped.durationMs < 5000, "… at the limit, not at the script's end (" + wrapped.durationMs + " ms)");
            assertEqual(wrapped.stdout, "started", "… with what it printed until then");
            const watchdog = _runs.limitBare.result;
            assertEqual(watchdog.timedOut + " " + watchdog.ok + " " + watchdog.code + " " + watchdog.failedToStart, "true false -1 false", "past the limit, bare: the runner's watchdog ends it, timedOut");
            assert(watchdog.durationMs >= 300 && watchdog.durationMs < 5000, "… at the limit (" + watchdog.durationMs + " ms)");
            const killedWrapped = _runs.stubbornWrapped.result;
            assertEqual(killedWrapped.timedOut + " " + killedWrapped.ok, "true false", "TERM shrugged off, inside timeout: its KILL ends it, timedOut");
            assert(killedWrapped.durationMs >= 500 && killedWrapped.durationMs < 5000, "… killAfterMs after the limit (" + killedWrapped.durationMs + " ms)");
            const killedBare = _runs.stubbornBare.result;
            assertEqual(killedBare.timedOut + " " + killedBare.ok + " " + killedBare.code, "true false -1", "TERM shrugged off, bare: the runner's KILL ends it, timedOut");
            assert(killedBare.durationMs >= 500 && killedBare.durationMs < 5000, "… killAfterMs after the limit (" + killedBare.durationMs + " ms)");
            assertEqual(_runs.inTime.result.ok + " " + _runs.inTime.result.timedOut, "true false", "a run that ends in time: the watchdog never speaks");
            assertEqual(_runs.limitNoSetpriv.result.timedOut + " " + _runs.limitNoSetpriv.result.code, "true -1", "timeout but no setpriv: the watchdog keeps the limit");
            _cancelling();
        });
    }

    // ---- cancelling ----
    function _cancelling() {
        // Says "late" when it gets the TERM: what must not be handed over any more
        const polite = "trap 'echo late; exit 0' TERM; echo ready; while :; do sleep 0.05; done";
        _start("cancelWrapped", wrapping, ["sh", "-c", polite]);
        _start("cancelBare", bare, ["sh", "-c", polite], { timeoutMs: 0 });
        _start("cancelStubbornWrapped", wrapping, ["sh", "-c", _stubborn], { killAfterMs: 200 });
        _start("cancelStubbornBare", bare, ["sh", "-c", _stubborn], { killAfterMs: 200 });
        _start("cancelWaiting", waiting, ["sh", "-c", "echo ran"]);
        _start("launchedLater", waiting, ["sh", "-c", "echo ran"]);
        _start("noLimitNoWait", waiting, ["sh", "-c", "echo ran"], { timeoutMs: 0 });
        assertEqual(waiting.running, 3, "runs with a limit wait for the look-up of timeout");

        _then("the runs to cancel are running", () => _has("cancelWrapped", "ready") && _has("cancelBare", "ready")
              && _runs.cancelStubbornWrapped.lines.length === 1 && _runs.cancelStubbornBare.lines.length === 1 && _answered("noLimitNoWait"), () => {
            assertEqual(_runs.noLimitNoWait.result.stdout, "ran", "a run without a limit does not wait for the look-up");
            assert(_runs.cancelWaiting.handle.running && _runs.cancelWaiting.result === null && _runs.launchedLater.out.length === 0, "the others still wait");
            for (const name of ["cancelWrapped", "cancelBare", "cancelStubbornWrapped", "cancelStubbornBare", "cancelWaiting"]) {
                _runs[name].handle.cancel();
                _runs[name].handle.cancel();
            }
            _lookingUp.timeout = CommandTools.timeout;
            _lookingUp.setpriv = CommandTools.setpriv;
            _lookingUp.known = true;
        });
        _then("the cancelled runs answered", () => _answered("cancelWrapped", "cancelBare", "cancelStubbornWrapped", "cancelStubbornBare", "cancelWaiting", "launchedLater"), () => {
            for (const name of ["cancelWrapped", "cancelBare"]) {
                const record = _runs[name];
                assertEqual(record.result.cancelled + " " + record.result.ok + " " + record.result.timedOut + " " + record.answers, "true false false 1",
                            name + ": cancelled, answered once (cancel() twice)");
                assertEqual(record.result.stdout + "|" + JSON.stringify(record.lines) + "|" + record.out.join(""), "ready|[[\"ready\",\"stdout\"]]|ready\n",
                            name + ": what the script said after the cancel is not handed over, nor kept");
                assert(record.result.durationMs < 5000, name + ": ended by the TERM (" + record.result.durationMs + " ms)");
            }
            for (const name of ["cancelStubbornWrapped", "cancelStubbornBare"]) {
                const result = _runs[name].result;
                assertEqual(result.cancelled + " " + result.ok + " " + result.timedOut, "true false false", name + ": TERM shrugged off, KILL after killAfterMs: cancelled");
                assert(result.durationMs >= 200 && result.durationMs < 5000, name + ": … not before killAfterMs (" + result.durationMs + " ms)");
            }
            const waited = _runs.cancelWaiting;
            assertEqual(waited.result.cancelled + " " + waited.result.failedToStart + " " + waited.result.stdout + " " + waited.result.durationMs + " " + waited.answers,
                        "true false  0 1", "cancelled while waiting: answered, never started");
            assertEqual(_runs.launchedLater.result.stdout + " " + _runs.launchedLater.result.ok, "ran true", "the look-up answered: the run that waited is started");
            _cancelAll();
        });
    }

    function _cancelAll() {
        _start("allOne", api, ["sh", "-c", "echo ready; sleep 30"]);
        _start("allTwo", api, ["sh", "-c", "echo ready; sleep 30"], { timeoutMs: 0 });
        api.environment = { API_RUNNER: "set" };
        _start("apiEnvironment", api, ["sh", "-c", "printf '%s' \"$API_RUNNER\""]);
        assertEqual(api.running, 3, "qs.api's CommandRunner: its runs counted");
        assert(api.tools === undefined && api.start !== undefined, "… the shell's look-up of timeout is not a module's to set");
        _then("both runs of the API's runner are running", () => _has("allOne", "ready") && _has("allTwo", "ready") && _answered("apiEnvironment"), () => api.cancelAll());
        _then("cancelAll() answered both", () => _answered("allOne", "allTwo", "apiEnvironment"), () => {
            assertEqual(_runs.apiEnvironment.result.stdout, "set", "… its environment handed to its runs");
            assertEqual(_runs.allOne.result.cancelled + " " + _runs.allTwo.result.cancelled + " " + api.running, "true true 0", "cancelAll(): every run cancelled and answered");
            _linesOverChunks();
        });
    }

    // ---- a line written in two pieces ----
    // The script writes half a line and goes on only when told to
    function _linesOverChunks() {
        _start("directory", bare, ["mktemp", "-d"]);
        _then("a scratch directory", () => _answered("directory"), () => {
            const directory = _runs.directory.result.stdout.trim();
            assert(_runs.directory.result.ok && directory.startsWith("/"), "a scratch directory for the test");
            suite._directory = directory;
            _start("split", bare, ["sh", "-c", "echo ready; printf 'par'; until [ -e \"$1/go\" ]; do sleep 0.02; done; printf 'tial\\nsecond\\n'", "sh", directory], {
                onLine: (line, stream) => {
                    _runs.split.lines.push([line, stream]);
                    if (line === "ready")
                        _start("go", bare, ["touch", directory + "/go"]);
                }
            });
        });
        _then("the split line's run answered", () => _answered("split", "go"), () => {
            assertEqual(JSON.stringify(_runs.split.lines), "[[\"ready\",\"stdout\"],[\"partial\",\"stdout\"],[\"second\",\"stdout\"]]",
                        "a line written in two pieces: handed over once, whole");
            assertEqual(_runs.split.out.join("|"), "ready\n|partial\n|second\n", "… to onStdout too");
            _wholeCharacters();
        });
    }

    // ---- a character that comes in two reads ----
    // "é" is two bytes: the script writes the first, waits to be told, and writes the
    // second. And 300 kB of a three-byte character, which no read boundary respects.
    function _wholeCharacters() {
        const half = "printf 'ready\\n'; printf 'caf\\303'; printf 'th\\303' >&2; until [ -e \"$1/go-on\" ]; do sleep 0.02; done; "
            + "printf '\\251 au lait\\n'; printf '\\251\\n' >&2";
        _start("character", wrapping, ["sh", "-c", half, "sh", _directory], {
            onLine: (line, stream) => {
                _runs.character.lines.push([line, stream]);
                if (line === "ready")
                    _start("goOn", bare, ["touch", _directory + "/go-on"]);
            }
        });
        const euros = "\u20ac".repeat(500);
        _start("characters", wrapping, ["sh", "-c", "i=0; while [ $i -lt 200 ]; do printf '%s\\n' \"$1\"; i=$((i+1)); done", "sh", euros]);
        _then("the runs with split characters answered", () => _answered("character", "characters", "goOn"), () => {
            const record = _runs.character;
            assertEqual(JSON.stringify(record.lines.map(entry => entry[0]).sort()), JSON.stringify(["caf\u00e9 au lait", "ready", "th\u00e9"]),
                        "a character whose bytes come in two reads: whole in the lines, on both streams");
            assertEqual(record.result.stdout + "|" + record.result.stderr, "ready\ncaf\u00e9 au lait|th\u00e9", "… and in the kept output");
            assert(!record.out.join("").includes("\ufffd") && !record.err.join("").includes("\ufffd"), "… and in what onStdout and onStderr got");
            const many = _runs.characters;
            const lines = many.lines.map(entry => entry[0]);
            assertEqual(lines.length + " " + lines.filter(line => line === euros).length, "200 200", "300 kB of a three-byte character: every line as written");
            assert(!many.result.stdout.includes("\ufffd") && many.result.stdout.length >= 200 * 500 && !many.out.join("").includes("\ufffd"),
                   "… the kept output and the chunks too");
            _wrapperKilled();
        });
    }

    // ---- timeout killed from outside ----
    // What the shell's own end does to a run with a limit: `timeout`, the shell's child,
    // gets a KILL it cannot pass on. The command must not outlive it.
    function _wrapperKilled() {
        _start("orphan", wrapping, ["sh", "-c", "trap '' TERM; echo \"$PPID $$\"; while :; do sleep 0.05; done"]);
        _then("the script inside timeout runs", () => _runs.orphan.lines.length === 1, () => {
            const pids = _runs.orphan.lines[0][0].split(" ");
            assert(/^[0-9]+$/.test(pids[0]) && /^[0-9]+$/.test(pids[1]), "the script runs inside timeout (" + pids.join(", ") + ")");
            _start("killWrapper", bare, ["kill", "-KILL", pids[0]]);
            _start("orphanGone", bare, ["sh", "-c", _untilGone, "sh", pids[1]], { timeoutMs: 8000 });
        });
        _then("the script is gone with its timeout", () => _answered("orphan", "killWrapper", "orphanGone"), () => {
            assertEqual(_runs.orphanGone.result.stdout.trim() + " " + _runs.orphanGone.result.timedOut, "gone false",
                        "timeout killed with KILL from outside: the command (which shrugs TERM off) goes with it");
            const result = _runs.orphan.result;
            assertEqual(result.ok + " " + result.code + " " + result.timedOut + " " + result.failedToStart, "false -1 false false", "… the run answered: not ok, no time-out");
            _destroyed();
        });
    }

    // ---- a runner that goes ----
    property string _directory: ""
    property var _doomed: []

    function _destroyed() {
        const kinds = [{ name: "goneWrapped", tools: CommandTools }, { name: "goneBare", tools: _noTimeout }];
        for (const kind of kinds) {
            const runner = _runnerComponent.createObject(suite, { tools: kind.tools });
            _doomed.push(runner);
            _start(kind.name, runner, ["sh", "-c", _stubborn], { killAfterMs: 200 });
            _runs[kind.name].runner = runner;
        }
        _then("the doomed runners' scripts run", () => _runs.goneWrapped.lines.length === 1 && _runs.goneBare.lines.length === 1, () => {
            for (const name of ["goneWrapped", "goneBare"]) {
                const record = _runs[name];
                record.pid = record.lines[0][0];
                assert(/^[0-9]+$/.test(record.pid), name + ": the script runs (" + record.pid + ")");
                record.runner.destroy();
                _start(name + "Pid", bare, ["sh", "-c", _untilGone, "sh", record.pid], { timeoutMs: 8000 });
            }
        });
        _then("the destroyed runners' scripts are gone", () => _answered("goneWrappedPid", "goneBarePid"), () => {
            for (const name of ["goneWrapped", "goneBare"]) {
                const record = _runs[name];
                assertEqual(_runs[name + "Pid"].result.stdout.trim() + " " + _runs[name + "Pid"].result.timedOut, "gone false",
                            name + ": the runner destroyed, its script (which shrugs TERM off) is ended all the same");
                assertEqual(record.answers + " " + record.lines.length, "0 1", name + ": … and nothing was called after");
                assert(!record.handle.running, name + ": … the handle says it is not running");
                record.handle.cancel();
            }
            _actionAndQuery();
        });
    }

    // ---- CommandAction and CommandQuery, on the runner ----
    function _actionAndQuery() {
        action.run(["sh", "-c", "sleep 0.1; printf 'first\\n\\n second \\n'; echo 'Error: no' >&2; exit 4"], result => _actions.push(result));
        action.run(["sh", "-c", "printf '%s' \"$SECRET\""], result => _actions.push(result), { SECRET: "s3cret" });
        action.run(["/nonexistent/h2s-test-program"], result => _actions.push(result));
        action.run(["sh", "-c", "echo after"], result => _actions.push(result));
        assert(action.busy, "CommandAction: busy while its commands run or wait");
        query.command = ["sh", "-c", "printf 'x\\n\\ny\\n'; echo ignored >&2; [ -e \"$1/again\" ] || { touch \"$1/again\"; sleep 0.1; }", "sh", _directory];
        query.request();
        assert(query.running, "CommandQuery: running after request()");
        query.request();
        query.request();
        _then("CommandAction answered four commands, CommandQuery two runs", () => _actions.length === 4 && _queried.length >= 2 && !query.running && !action.busy, () => {
            assertEqual(JSON.stringify(_actions[0]), JSON.stringify({ ok: false, code: 4, lines: ["first", " second "], error: "Error: no" }),
                        "CommandAction: { ok, code, lines (non-empty, as printed), error (stderr, trimmed) }");
            assertEqual(JSON.stringify(_actions[1]), JSON.stringify({ ok: true, code: 0, lines: ["s3cret"], error: "" }), "… one after another, in order; the environment handed over");
            assertEqual(_actions[2].ok + " " + _actions[2].code + " " + _actions[2].lines.length + " " + (_actions[2].error !== ""), "false -1 0 true",
                        "… a program that cannot start is answered, with an error");
            assertEqual(JSON.stringify(_actions[3].lines), "[\"after\"]", "… and the queue goes on after it");
            assertEqual(JSON.stringify(_queried), "[[\"x\",\"y\"],[\"x\",\"y\"]]", "CommandQuery: its non-empty stdout lines; requests while it ran: one more run, not two");
            _latestQuery();
        });
    }

    // LatestQuery: a run something was asked during is not answered; the run after is, with
    // whether it worked
    function _latestQuery() {
        latest.command = ["sh", "-c", "n=$(cat \"$1/count\" 2>/dev/null || echo 0); n=$((n + 1)); echo \"$n\" > \"$1/count\"; sleep 0.2; "
                          + "echo \"run$n\"; if [ -e \"$1/fail\" ]; then echo 'Error: invalid field' >&2; exit 3; fi", "sh", _directory];
        latest.request();
        assert(latest.running, "LatestQuery: running after request()");
        latest.request();
        latest.request();
        _then("LatestQuery answered", () => _latest.length >= 1 && !latest.running, () => {
            assertEqual(JSON.stringify(_latest), JSON.stringify([{ lines: ["run2"], ok: true, code: 0, stderr: "" }]),
                        "LatestQuery: requests while it ran — that run's answer dropped, one more run answered (its lines, ok)");
            _start("failNext", bare, ["touch", _directory + "/fail"]);
        });
        _then("the next run set to fail", () => _answered("failNext"), () => {
            latest.request();
        });
        _then("LatestQuery answered a failing run", () => _latest.length >= 2 && !latest.running, () => {
            assertEqual(JSON.stringify(_latest[1]), JSON.stringify({ lines: ["run3"], ok: false, code: 3, stderr: "Error: invalid field" }),
                        "LatestQuery: a run that fails — answered, not ok, with its stderr");
            assertEqual(_latest.length, 2, "LatestQuery: one answer per run answered");
            _start("cleanup", bare, ["rm", "-rf", "--", _directory]);
        });
        _then("the scratch directory removed", () => _answered("cleanup"), () => {
            assert(_runs.cleanup.result.ok, "the scratch directory removed");
        });
    }
}
