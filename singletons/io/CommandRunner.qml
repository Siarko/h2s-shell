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
//               outputAfterCancel: false, endWithShell: false, maxOutputBytes: 1048576,
//               done(result) }
//   result  = { ok, code, stdout, stderr, timedOut, cancelled, failedToStart, truncated,
//               durationMs, error }   — frozen (CommandRules.result says what each is)
//
// - `argv` is a non-empty list of strings, started as it is: no shell reads it. What is
//   asked wrongly (argv, an option of the wrong kind) is answered with `error` set and
//   nothing run.
// - `environment` ({ NAME: value }) is added to the command's, the runner's first, then
//   the run's: the way to hand a command a secret (a command line is anyone's to read).
// - The time limit is kept twice. The command is started inside coreutils' `timeout -k`
//   (CommandTools: found on PATH, trusted only), which ends it even when the shell is
//   gone — with `setpriv --pdeathsig KILL` between the two, so that the command dies
//   with `timeout` when the shell's own end kills that; and the runner has its own
//   watchdog, the only limit where one of the two programs is missing. Past the limit
//   the command gets TERM, and KILL `killAfterMs` later.
// - A run without a time limit is started bare and at once: what it starts may be meant
//   to outlive the shell. With `endWithShell` it is started behind `setpriv --pdeathsig
//   KILL` alone (also where `timeout` is missing), so that it dies with the shell. Runs
//   that take the two programs (a limit, or `endWithShell`) wait for their look-up.
// - cancel(): TERM, KILL after `killAfterMs`; no chunk or line is handed over from that
//   moment (with `outputAfterCancel`: they still are, and kept, until the process is
//   gone); `done` comes when the process is gone, with `cancelled: true` — also for a
//   run whose answer is still waiting to be handed over (refused, or unable to start).
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

    // Where `timeout` and `setpriv` are: { known, timeout, setpriv }
    property var tools: CommandTools

    // null, or a function (argv) → "" or why the run is refused: answered like an argv
    // that is wrong, nothing started (the module API's guard in module test mode)
    property var refuse: null

    property var _jobs: []
    // The timings' clock (ms): monotonic (Quickshell's ElapsedTimer), unmoved by the wall clock
    property ElapsedTimer _clock: ElapsedTimer {}

    function _now() {
        return Number(_clock.elapsedMs());
    }

    // A run's timers as the runner kept them: { armed: { <timer>: ms }, armedAt, fired: { <timer>:
    // ms since the run started } } — what the runner's suite checks the limits against, unmoved
    // by how late a loaded event loop hands over the answer
    function _timingsOf(handle) {
        return handle?._timings ?? null;
    }

    // A timer of a run fired: early (Qt's timers may), it waits the rest; then the event
    function _fired(job, name) {
        const elapsed = _now() - job.clockStart;
        const remainder = CommandRules.timerRemainder(job.timings.armed[name], elapsed - (job.timings.armedAt[name] ?? 0));
        if (remainder > 0 && job.item) {
            job.item[name].interval = remainder;
            job.item[name].restart();
            return;
        }
        job.timings.fired[name] = elapsed;
        _dispatch(job, { type: name });
    }
    property var _deferred: []
    // False once the runner is being destroyed — and also where Qt dropped its properties
    // (onDestruction): a bool that cannot be read reads false
    property bool _live: true
    readonly property bool _toolsKnown: tools?.known === true

    function start(argv, options) {
        // One copy of the command, read once: what `refuse` judges is what runs
        const snapshot = CommandRules.argvSnapshot(argv, false);
        let problem = snapshot.problem;
        if (problem === "" && typeof refuse === "function")
            problem = String(refuse(Array.from(snapshot.argv)) ?? "");
        // Every option read once (callbacks too)
        const given = CommandRules.options(options);
        const job = {
            argv: problem === "" ? snapshot.argv : [],
            options: given,
            onStdout: given.callbacks.onStdout,
            onStderr: given.callbacks.onStderr,
            onLine: given.callbacks.onLine,
            // An answer is owed even where the options are what is wrong
            done: given.callbacks.done,
            state: CommandRules.fresh(given.timeoutMs, given.killAfterMs, given.outputAfterCancel, given.endWithShell),
            // queued: done, its answer waiting in `_deferred` for the flush
            item: null, starting: false, queued: false, muted: false, truncated: false,
            stdout: "", stderr: "", lastStderr: "", startedAt: 0,
            // Its timers, on the monotonic clock from its start (_startProcess): the interval
            // each was armed with, and when it was armed and fired (_timingsOf)
            clockStart: 0, timings: { armed: {}, armedAt: {}, fired: {} },
            lineCount: { stdout: 0, stderr: 0 },
            refusal: problem !== "" ? problem : given.problem
        };
        const handle = {
            get running() {
                return job.state.phase !== "done";
            },
            cancel: function () {
                if ((job.state.phase !== "done" || job.queued) && root._live)
                    root._cancel(job);
            }
        };
        // Its timings, for the runner's own suite (_timingsOf): a frozen copy made at each read
        // (the runner's own numbers stay on the job, where no caller reaches them), not
        // enumerable
        Object.defineProperty(handle, "_timings", { get: () => Object.freeze({
            armed: Object.freeze(Object.assign({}, job.timings.armed)),
            armedAt: Object.freeze(Object.assign({}, job.timings.armedAt)),
            fired: Object.freeze(Object.assign({}, job.timings.fired))
        }) });
        if (!_live) {
            job.state.phase = "done";
            return handle;
        }
        _jobs = _jobs.concat([job]);
        if (job.refusal !== "") {
            job.state.phase = "done";
            _defer(job);
        } else if (!CommandRules.waitsForTools(job.state.timeoutMs, job.state.endWithShell) || _toolsKnown) {
            _launch(job);
        }
        return handle;
    }

    function cancelAll() {
        for (const job of _jobs.slice())
            _cancel(job);
    }

    // A run whose answer waits in `_deferred` is done already: cancelled, that answer says so
    function _cancel(job) {
        _dispatch(job, { type: "cancel", queued: job.queued });
    }

    on_ToolsKnownChanged: {
        if (!_toolsKnown)
            return;
        for (const job of _jobs.slice())
            _launch(job);
    }

    function _launch(job) {
        if (job.state.phase === "waiting")
            _dispatch(job, { type: "launch", wrapped: CommandRules.wraps(tools, job.state.timeoutMs), guarded: CommandRules.guards(tools, job.state.timeoutMs, job.state.endWithShell) });
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
                job.timings.armed[effect.name] = effect.ms;
                job.timings.armedAt[effect.name] = _now() - job.clockStart;
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
        item.process.command = CommandRules.commandLine(job.argv, tools, job.state.timeoutMs, job.state.killAfterMs, job.state.endWithShell);
        item.process.environment = CommandRules.mergedEnvironment(root.environment, job.options.environment);
        job.startedAt = Date.now();
        job.clockStart = _now();
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
        if (job.muted || job.state.phase === "done" || !_live)
            return;
        // Enough to know setpriv's own message (CommandRules.result)
        if (stream === "stderr")
            job.lastStderr = line.slice(0, 64);
        const limit = job.options.maxOutputBytes;
        if (job.options.keepOutput) {
            const kept = CommandRules.keptLine(job[stream], job.lineCount[stream], line, limit);
            job[stream] = kept.text;
            job.lineCount[stream]++;
            job.truncated = job.truncated || kept.truncated;
        }
        _call(job, stream === "stdout" ? "onStdout" : "onStderr", line + "\n");
        // A callback may have cancelled the run, or destroyed the runner
        if (!job.onLine || job.muted || !_live)
            return;
        const cut = CommandRules.kept("", line, limit);
        job.truncated = job.truncated || cut.truncated;
        _call(job, "onLine", cut.text, stream);
    }

    function _answer(job) {
        if (job.starting) {
            _defer(job);
            return;
        }
        _jobs = _jobs.filter(other => other !== job);
        if (!_live)
            return;
        const result = CommandRules.result(job.state, {
            stdout: job.stdout, stderr: job.stderr, truncated: job.truncated, lastStderr: job.lastStderr,
            durationMs: job.startedAt > 0 ? Date.now() - job.startedAt : 0
        });
        const item = job.item;
        job.item = null;
        item?.destroy();
        _call(job, "done", result);
    }

    function _defer(job) {
        job.queued = true;
        _deferred.push(job);
        _flush.restart();
    }

    function _flushDeferred() {
        const deferred = _deferred;
        _deferred = [];
        for (const job of deferred) {
            if (!_live)
                return;
            job.queued = false;
            if (job.refusal !== "") {
                _jobs = _jobs.filter(other => other !== job);
                _call(job, "done", CommandRules.refusal(job.refusal, job.state.cancelled));
            } else {
                _answer(job);
            }
        }
    }

    property Timer _flush: Timer {
        interval: 0
        onTriggered: {
            if (root._live)
                root._flushDeferred();
        }
    }

    property Component _runComponent: Component {
        QtObject {
            id: run
            property var job: null

            // The run while the runner takes its reports: none once the runner is going, nor
            // where Qt dropped its properties or the run's (onDestruction) — nor once its
            // `root` is gone, as it is while a Process reports from its own destruction
            function _job() {
                return root && root._live && run.job ? run.job : null;
            }
            function _read(stream, text) {
                const job = run._job();
                if (job)
                    root._read(job, stream, text);
            }
            function _event(event) {
                const job = run._job();
                if (job)
                    root._dispatch(job, event);
            }
            function _timer(name) {
                const job = run._job();
                if (job)
                    root._fired(job, name);
            }

            property Process process: Process {
                // Line by line: Quickshell decodes what a parser hands over as one piece,
                // so raw reads would break a character whose bytes come in two of them
                stdout: SplitParser {
                    splitMarker: "\n"
                    onRead: text => run._read("stdout", text)
                }
                stderr: SplitParser {
                    splitMarker: "\n"
                    onRead: text => run._read("stderr", text)
                }
                onExited: (exitCode, exitStatus) => run._event({ type: "exited", code: exitCode, crashed: exitStatus !== 0 })
                onRunningChanged: {
                    if (!running)
                        run._event({ type: "stopped" });
                }

                // Destroyed with its command still running (the runner went): ended at once,
                // with KILL — nobody is left to send one later. Its own properties alone,
                // which Qt keeps while the runner's and the run's may be gone. The destroyed
                // Process takes its child with it, which for a wrapped run is `timeout`, and
                // the command dies with that (commandLine); what the command started itself
                // is in the process group `timeout` leads, so that group gets a KILL too
                // (through `kill`: a Process can only signal its own child).
                Component.onDestruction: {
                    if (!running)
                        return;
                    const pid = Number(processId);
                    if (CommandRules.wrappedLine(command) && pid > 1)
                        Quickshell.execDetached(["kill", "-KILL", "--", "-" + pid]);
                    signal(9);
                }
            }
            property Timer watchdog: Timer {
                onTriggered: run._timer("watchdog")
            }
            property Timer kill: Timer {
                onTriggered: run._timer("kill")
            }
        }
    }

    // The runner is destroyed (a module turned off): nothing is called from here on, and
    // its runs' processes end with KILL as they are destroyed with it (_runComponent). When
    // the shell itself ends or reloads nothing here runs: then the command dying with
    // `timeout` is all there is.
    //
    // An object waiting for a deferred delete (destroy(), an item a Loader let go) whose
    // JavaScript wrapper the collector took first — an owner made without a parent, say —
    // has lost its properties by now: each reads as undefined, null or false, and a write
    // finds nothing to write to. Then there is nothing to mark here (`_live` reads false
    // already) and the runs end from their own Processes all the same.
    Component.onDestruction: {
        const jobs = _jobs;
        if (!Array.isArray(jobs))
            return;
        _live = false;
        for (const job of jobs) {
            job.muted = true;
            job.queued = false;
            job.state = Object.assign({}, job.state, { phase: "done" });
        }
        _jobs = [];
    }
}
