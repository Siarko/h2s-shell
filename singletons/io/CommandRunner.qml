import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons

// Runs commands: any number at once, each with a time limit, its output as it comes, and
// one answer.
//
//   start(argv, options) → handle { running, cancel() }
//   options = { timeoutMs: 30000 (0: no limit), killAfterMs: 3000, environment,
//               onStdout(text), onStderr(text), onLine(line, stream), keepOutput: true,
//               maxOutputBytes: 1048576, done(result) }
//   result  = { ok, code, stdout, stderr, timedOut, cancelled, failedToStart, truncated,
//               durationMs, error }   — frozen (CommandRules.result says what each is)
//
// - `argv` is a non-empty list of strings, started as it is: no shell reads it. What is
//   asked wrongly (argv, an option of the wrong kind) is answered with `error` set and
//   nothing run.
// - `environment` ({ NAME: value }) is added to the command's, the runner's first, then
//   the run's: the way to hand a command a secret (a command line is anyone's to read).
// - The time limit is kept twice. The command is started inside coreutils' `timeout -k`
//   (CommandTools: found in a system directory), which ends it even when the shell is
//   gone; and the runner has its own watchdog, the only limit where there is no
//   `timeout`. Past the limit the command gets TERM, and KILL `killAfterMs` later.
// - cancel(): TERM, KILL after `killAfterMs`; no chunk or line is handed over from that
//   moment; `done` comes when the process is gone, with `cancelled: true`.
// - `done` is called exactly once per start(), never inside start() itself — and never
//   once the runner is destroyed: its runs are then ended at once (KILL), nothing is called.
// - Output is read in whole lines, each decoded as one piece (a character whose bytes
//   come in two reads is never broken): `onLine` gets each line, of both streams
//   ("stdout" | "stderr"); `onStdout` / `onStderr` each line of theirs with its line
//   break; the result holds both streams unless `keepOutput` is false — the lines joined
//   by line breaks, none after the last — each cut at `maxOutputBytes` (`truncated`
//   then; the callbacks still get every line, a single line cut at the same length).
//   What a command writes without ending the line is handed over when the line, or the
//   stream, ends. It is text from outside the shell: shown as plain text, never as
//   markup, never put on a command line unquoted.
// - A callback that throws is logged and changes nothing for the run.
// - Nothing is ever started by a declarative `running: true` (CLAUDE.md).
QtObject {
    id: root

    // Added to every run's environment
    property var environment: ({})

    // Runs started and not yet answered
    readonly property int running: _jobs.length

    // Where `timeout` is: { known, timeout }
    property var tools: CommandTools

    property var _jobs: []
    property var _deferred: []
    property bool _gone: false
    readonly property bool _toolsKnown: tools?.known === true

    function start(argv, options) {
        const problem = CommandRules.argvProblem(argv);
        const given = CommandRules.options(options);
        const callbacks = given.problem === "" && options ? options : {};
        const job = {
            argv: problem === "" ? Array.from(argv) : [],
            options: given,
            onStdout: callbacks.onStdout ?? null,
            onStderr: callbacks.onStderr ?? null,
            onLine: callbacks.onLine ?? null,
            // An answer is owed even where the options are what is wrong
            done: typeof options?.done === "function" ? options.done : null,
            state: CommandRules.fresh(given.timeoutMs, given.killAfterMs),
            item: null, starting: false, muted: false, truncated: false,
            stdout: "", stderr: "", startedAt: 0,
            lineCount: { stdout: 0, stderr: 0 },
            refusal: problem !== "" ? problem : given.problem
        };
        const handle = {
            get running() {
                return job.state.phase !== "done";
            },
            cancel: function () {
                if (job.state.phase !== "done" && !root._gone)
                    root._dispatch(job, { type: "cancel" });
            }
        };
        if (_gone) {
            job.state.phase = "done";
            return handle;
        }
        _jobs = _jobs.concat([job]);
        if (job.refusal !== "") {
            job.state.phase = "done";
            _deferred.push(job);
            _flush.restart();
        } else if (job.state.timeoutMs === 0 || _toolsKnown) {
            _launch(job);
        }
        return handle;
    }

    function cancelAll() {
        for (const job of _jobs.slice())
            _dispatch(job, { type: "cancel" });
    }

    on_ToolsKnownChanged: {
        if (!_toolsKnown)
            return;
        for (const job of _jobs.slice())
            _launch(job);
    }

    function _launch(job) {
        if (job.state.phase === "waiting")
            _dispatch(job, { type: "launch", wrapped: CommandRules.wraps(tools?.timeout, job.state.timeoutMs) });
    }

    function _dispatch(job, event) {
        const stepped = CommandRules.step(job.state, event);
        if (stepped.ignored !== "")
            return;
        job.state = stepped.state;
        for (const effect of stepped.effects)
            _perform(job, effect);
    }

    function _perform(job, effect) {
        const item = job.item;
        switch (effect.type) {
        case "start":
            _startProcess(job);
            break;
        case "timer":
            if (item) {
                item[effect.name].interval = effect.ms;
                item[effect.name].restart();
            }
            break;
        case "stop":
            item?.[effect.name].stop();
            break;
        case "signal":
            if (item?.process.running)
                item.process.signal(effect.signal);
            break;
        case "mute":
            job.muted = true;
            break;
        case "answer":
            _answer(job);
            break;
        }
    }

    function _startProcess(job) {
        // Set after it is made: handed to createObject, the job would arrive as a copy
        const item = _runComponent.createObject(root);
        item.job = job;
        job.item = item;
        item.process.command = CommandRules.commandLine(job.argv, tools?.timeout, job.state.timeoutMs, job.state.killAfterMs);
        item.process.environment = CommandRules.mergedEnvironment(root.environment, job.options.environment);
        job.startedAt = Date.now();
        // A program that cannot start may be reported inside the next line: its answer
        // waits for the flush, so that done is never called inside start()
        job.starting = true;
        item.process.running = true;
        job.starting = false;
    }

    function _call(job, name, first, second) {
        const callback = job[name];
        if (!callback)
            return;
        try {
            callback(first, second);
        } catch (error) {
            console.warn("[Commands] a run's " + name + " threw: " + String(error).slice(0, 300));
        }
    }

    function _read(job, stream, text) {
        for (const line of CommandRules.linesOf(text))
            _line(job, stream, line);
    }

    function _line(job, stream, line) {
        if (job.muted || job.state.phase === "done" || _gone)
            return;
        const limit = job.options.maxOutputBytes;
        if (job.options.keepOutput) {
            const kept = CommandRules.keptLine(job[stream], job.lineCount[stream], line, limit);
            job[stream] = kept.text;
            job.lineCount[stream]++;
            job.truncated = job.truncated || kept.truncated;
        }
        _call(job, stream === "stdout" ? "onStdout" : "onStderr", line + "\n");
        // A callback may have cancelled the run, or destroyed the runner
        if (!job.onLine || job.muted || _gone)
            return;
        const cut = CommandRules.kept("", line, limit);
        job.truncated = job.truncated || cut.truncated;
        _call(job, "onLine", cut.text, stream);
    }

    function _answer(job) {
        if (job.starting) {
            _deferred.push(job);
            _flush.restart();
            return;
        }
        _jobs = _jobs.filter(other => other !== job);
        if (_gone)
            return;
        const result = CommandRules.result(job.state, {
            stdout: job.stdout, stderr: job.stderr, truncated: job.truncated,
            durationMs: job.startedAt > 0 ? Date.now() - job.startedAt : 0
        });
        const item = job.item;
        job.item = null;
        item?.destroy();
        _call(job, "done", result);
    }

    function _flushDeferred() {
        const deferred = _deferred;
        _deferred = [];
        for (const job of deferred) {
            if (_gone)
                return;
            if (job.refusal !== "") {
                _jobs = _jobs.filter(other => other !== job);
                _call(job, "done", CommandRules.refusal(job.refusal));
            } else {
                _answer(job);
            }
        }
    }

    property Timer _flush: Timer {
        interval: 0
        onTriggered: root._flushDeferred()
    }

    property Component _runComponent: Component {
        QtObject {
            id: run
            property var job: null

            property Process process: Process {
                // Line by line: Quickshell decodes what a parser hands over as one piece,
                // so raw reads would break a character whose bytes come in two of them
                stdout: SplitParser {
                    splitMarker: "\n"
                    onRead: text => root._read(run.job, "stdout", text)
                }
                stderr: SplitParser {
                    splitMarker: "\n"
                    onRead: text => root._read(run.job, "stderr", text)
                }
                onExited: (exitCode, exitStatus) => root._dispatch(run.job, { type: "exited", code: exitCode, crashed: exitStatus !== 0 })
                onRunningChanged: {
                    if (!running)
                        root._dispatch(run.job, { type: "stopped" });
                }
            }
            property Timer watchdog: Timer {
                onTriggered: root._dispatch(run.job, { type: "watchdog" })
            }
            property Timer kill: Timer {
                onTriggered: root._dispatch(run.job, { type: "kill" })
            }
        }
    }

    // The runner goes (a module turned off, the shell reloading): nothing is called from
    // here on, and its runs are ended at once, with KILL — nobody is left to send one
    // later. A destroyed Process takes its own child with it, which for a wrapped run is
    // `timeout`: the command would go on without it, and without a limit. `timeout` makes
    // itself the leader of a process group that holds the command, so that group gets
    // the KILL (through `kill`: a Process can only signal its own child).
    Component.onDestruction: {
        _gone = true;
        for (const job of _jobs) {
            job.muted = true;
            const wrapped = job.state.wrapped;
            job.state = Object.assign({}, job.state, { phase: "done" });
            const process = job.item?.process;
            if (!process?.running)
                continue;
            const processId = process.processId;
            if (wrapped && typeof processId === "number" && processId > 1)
                Quickshell.execDetached(["kill", "-KILL", "--", "-" + processId]);
            process.signal(9);
        }
        _jobs = [];
    }
}
