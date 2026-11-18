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

    // Stand-ins for CommandTools: no `timeout` on this system, and a look-up not answered yet
    property QtObject _noTimeout: QtObject {
        property bool known: true
        property string timeout: ""
    }
    property QtObject _lookingUp: QtObject {
        property bool known: false
        property string timeout: ""
    }

    // Inside `timeout` (the real one, found by CommandTools), bare, and waiting for the look-up
    property Io.CommandRunner wrapping: Io.CommandRunner {
        environment: ({ RUNNER_ONLY: "runner", BOTH: "runner" })
    }
    property Io.CommandRunner bare: Io.CommandRunner {
        tools: suite._noTimeout
    }
    property Io.CommandRunner waiting: Io.CommandRunner {
        tools: suite._lookingUp
    }
    property Api.CommandRunner api: Api.CommandRunner {}

    property Component _runnerComponent: Component {
        Io.CommandRunner {}
    }

    property Io.CommandAction action: Io.CommandAction {}
    property Io.CommandQuery query: Io.CommandQuery {
        onDone: lines => suite._queried.push(lines)
    }
    property var _queried: []
    property var _actions: []

    // name → { handle, result, answers, lines: [[line, stream]…], out: [chunk…], err: […] }
    property var _runs: ({})

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

    // A script that tells it runs, shrugs TERM off, and goes on until it is killed
    readonly property string _stubborn: "trap '' TERM; echo \"$$\"; while :; do sleep 0.05; done"
    // Ends when the process is gone
    readonly property string _untilGone: "while kill -0 \"$1\" 2>/dev/null; do sleep 0.05; done; echo gone"

    function runAsync() {
        _then("the look-up of timeout answered", () => CommandTools.known, () => {
            assert(CommandTools.timeout.startsWith("/") && CommandRules.timeoutCandidates.includes(CommandTools.timeout),
                   "coreutils' timeout found in a system directory: " + CommandTools.timeout);
            _plain();
        });
        _clock.start();
    }

    // ---- answers and output ----
    function _plain() {
        _start("exit", wrapping, ["sh", "-c", "printf 'a b\\n\\nc'; printf 'oops\\n' >&2; exit 3"]);
        _start("words", wrapping, ["sh", "-c", "printf '%s|%s|%s|%s' \"$1\" \"$2\" \"$RUNNER_ONLY\" \"$BOTH\"", "sh", "two words", "$HOME; `id`"],
               { environment: { BOTH: "run" } });
        _start("parent", wrapping, ["sh", "-c", "cat /proc/$PPID/comm"]);
        _start("parentNoLimit", wrapping, ["sh", "-c", "cat /proc/$PPID/comm"], { timeoutMs: 0 });
        _start("notKept", wrapping, ["sh", "-c", "echo out; echo err >&2"], { keepOutput: false });
        _start("capped", wrapping, ["sh", "-c", "head -c 5000 /dev/zero | tr '\\0' x; echo; echo short"], { maxOutputBytes: 1000 });
        _start("signalled", wrapping, ["sh", "-c", "kill -KILL $$"], { timeoutMs: 0 });
        _start("throws", wrapping, ["sh", "-c", "echo one; echo two"], {
            onLine: (line, stream) => {
                _runs.throws.lines.push([line, stream]);
                throw new Error("a module's mistake");
            }
        });
        const before = _runs.exit;
        assert(before.handle.running && before.result === null, "start(): a handle, running, no answer inside start()");
        assertEqual(wrapping.running, 8, "the runner counts its runs");

        _then("the plain runs answered", () => _answered("exit", "words", "parent", "parentNoLimit", "notKept", "capped", "signalled", "throws"), () => {
            const exit = _runs.exit.result;
            assertEqual(exit.ok + " " + exit.code + " " + exit.failedToStart + " " + exit.timedOut + " " + exit.cancelled + " " + exit.error,
                        "false 3 false false false ", "exit 3: not ok, the code, nothing else said");
            assertEqual(exit.stdout, "a b\n\nc", "stdout whole");
            assertEqual(exit.stderr, "oops\n", "stderr apart from it");
            assertEqual(JSON.stringify(_runs.exit.lines.filter(entry => entry[1] === "stdout").map(entry => entry[0])), "[\"a b\",\"\",\"c\"]",
                        "onLine: each line, an empty one, the last one without its newline");
            assertEqual(JSON.stringify(_runs.exit.lines.filter(entry => entry[1] === "stderr")), "[[\"oops\",\"stderr\"]]", "… stderr's lines named as such");
            assertEqual(_runs.exit.out.join("") + "|" + _runs.exit.err.join(""), "a b\n\nc|oops\n", "onStdout, onStderr: the same text as it came");
            assert(Object.isFrozen(exit) && exit.durationMs >= 0, "the answer is frozen");
            assert(!_runs.exit.handle.running, "the handle: not running after the answer");
            assertEqual(_runs.exit.answers, 1, "done once");

            assertEqual(_runs.words.result.stdout, "two words|$HOME; `id`|runner|run", "words kept whole, no shell reads them; the runner's environment, the run's on top");
            assert(_runs.words.result.ok, "exit 0: ok");
            assertEqual(_runs.parent.result.stdout.trim(), "timeout", "a run with a limit is started inside timeout");
            assert(_runs.parentNoLimit.result.ok && _runs.parentNoLimit.result.stdout.trim() !== "timeout", "one without a limit is not");

            assertEqual(_runs.notKept.result.stdout + "|" + _runs.notKept.result.stderr + "|" + _runs.notKept.lines.length, "||2", "keepOutput false: the answer holds none, the callbacks got it");
            const capped = _runs.capped.result;
            assertEqual(capped.stdout.length + " " + capped.truncated + " " + capped.ok, "1000 true true", "over the cap: the kept output cut, said, the run itself fine");
            assertEqual(_runs.capped.out.join("").length, 5007, "… the chunk callback still got everything");
            assertEqual(_runs.capped.lines.map(entry => entry[0].length).join(), "1000,5", "… a line over the cap handed over cut once, the next one whole");

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

        _then("the runs that cannot start answered", () => _answered("missingBare", "missingWrapped", "empty", "text", "number", "badLimit", "badCallback"), () => {
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

        _then("the runs past their limit answered", () => _answered("limitWrapped", "limitBare", "stubbornWrapped", "stubbornBare", "inTime"), () => {
            const wrapped = _runs.limitWrapped.result;
            assertEqual(wrapped.timedOut + " " + wrapped.ok + " " + wrapped.code + " " + wrapped.cancelled, "true false 124 false", "past the limit, inside timeout: timedOut, timeout's 124");
            assert(wrapped.durationMs >= 300 && wrapped.durationMs < 5000, "… at the limit, not at the script's end (" + wrapped.durationMs + " ms)");
            assertEqual(wrapped.stdout, "started\n", "… with what it printed until then");
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
            assertEqual(_runs.noLimitNoWait.result.stdout, "ran\n", "a run without a limit does not wait for the look-up");
            assert(_runs.cancelWaiting.handle.running && _runs.cancelWaiting.result === null && _runs.launchedLater.out.length === 0, "the others still wait");
            for (const name of ["cancelWrapped", "cancelBare", "cancelStubbornWrapped", "cancelStubbornBare", "cancelWaiting"]) {
                _runs[name].handle.cancel();
                _runs[name].handle.cancel();
            }
            _lookingUp.timeout = CommandTools.timeout;
            _lookingUp.known = true;
        });
        _then("the cancelled runs answered", () => _answered("cancelWrapped", "cancelBare", "cancelStubbornWrapped", "cancelStubbornBare", "cancelWaiting", "launchedLater"), () => {
            for (const name of ["cancelWrapped", "cancelBare"]) {
                const record = _runs[name];
                assertEqual(record.result.cancelled + " " + record.result.ok + " " + record.result.timedOut + " " + record.answers, "true false false 1",
                            name + ": cancelled, answered once (cancel() twice)");
                assertEqual(record.result.stdout + "|" + JSON.stringify(record.lines) + "|" + record.out.join(""), "ready\n|[[\"ready\",\"stdout\"]]|ready\n",
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
            assertEqual(_runs.launchedLater.result.stdout + " " + _runs.launchedLater.result.ok, "ran\n true", "the look-up answered: the run that waited is started");
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

    // ---- a line that comes in two reads ----
    // The script writes half a line and goes on only when told to: the first chunk has
    // been handed over by then, so the line really is split
    function _linesOverChunks() {
        _start("directory", bare, ["mktemp", "-d"]);
        _then("a scratch directory", () => _answered("directory"), () => {
            const directory = _runs.directory.result.stdout.trim();
            assert(_runs.directory.result.ok && directory.startsWith("/"), "a scratch directory for the test");
            suite._directory = directory;
            _start("split", bare, ["sh", "-c", "printf 'par'; until [ -e \"$1/go\" ]; do sleep 0.02; done; printf 'tial\\nsecond\\n'", "sh", directory], {
                onStdout: text => {
                    _runs.split.out.push(text);
                    if (_runs.split.out.length === 1)
                        _start("go", bare, ["touch", directory + "/go"]);
                }
            });
        });
        _then("the split line's run answered", () => _answered("split", "go"), () => {
            assert(_runs.split.out.length >= 2 && _runs.split.out[0] === "par", "the line came in two reads");
            assertEqual(JSON.stringify(_runs.split.lines), "[[\"partial\",\"stdout\"],[\"second\",\"stdout\"]]", "onLine: put together, one line");
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
            _start("cleanup", bare, ["rm", "-rf", "--", _directory]);
        });
        _then("the scratch directory removed", () => _answered("cleanup"), () => {
            assert(_runs.cleanup.result.ok, "the scratch directory removed");
        });
    }
}
