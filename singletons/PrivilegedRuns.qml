pragma Singleton

import QtQuick
import Quickshell
import qs.singletons.io as Io

// The shell's one queue of commands run as administrator through pkexec: one password
// question at a time, for every module (`module.privileged.start`, api/ModuleHandle.qml)
// and the old api/PrivilegedAction.qml. The decisions are PrivilegedRules' (queueStep: when
// a run may start, when the next one may, what a cancel, a lock and a module turned off do);
// this only starts processes, keeps one timer and hands the answers over.
//
// - A run is looked at before pkexec is asked: its program must be there, an executable
//   file (a missing one is `notFound`, never pkexec's "not authorised").
// - One log line per run started, with the module's id and its `what`. Nothing else shows
//   when polkit lets a run go without a password.
// - Which request the head of the queue waits for: with the shell's own prompt
//   (Authentication.state "active" or "conflict") a request that opens while the head may
//   still ask counts as the head's, and its end lets the head go. The agent's flow names no
//   caller, so any request seen then counts (one that was open before the run started
//   too): what tells the head's own request apart is the prompt's work
//   (notes/plans/api-next/commands.md §3.4, "Which request is announced").
// - The session locked (Profiles.screenLocked, which Lockscreen reports): nothing starts,
//   and the runs waiting are answered `dismissed`, `blocked: "locked"`, quietly. A run whose
//   pkexec has started is left to its prompt.
// - In module test mode (ModuleHost.testMode of the shell's host) the polkit agent and the
//   lock are the test kit's (`testAgent`, `testLocked`: tests/ModuleTestKit.qml), never the
//   shell's: a suite never meets the real agent.
Singleton {
    id: root

    // The look-up of pkexec is done (`pkexec` holds what it found)
    readonly property bool known: _known
    // The system's pkexec: the first on PrivilegedRules.pkexecSearchPath that only root can
    // change and that is setuid root; "" when none (`pkexecReason` says why)
    readonly property string pkexec: _pkexec
    readonly property string pkexecReason: _pkexecReason
    // No run waits, checks or runs
    readonly property bool idle: _state.jobs.length === 0
    // How many runs are queued or running
    readonly property int count: _state.jobs.length

    // ---- Module test mode: the seams (tests/ModuleTestKit.qml) ----
    // The polkit agent as a suite sets it: its state (PolkitRules.state's words) and an open
    // request (`flow`: null or an object), and what reportDenied() tells
    readonly property QtObject testAgent: QtObject {
        property string state: "active"
        property var flow: null

        function reportDenied(what) {
            const notice = PolkitRules.deniedNotice(state, what);
            Notifier.send(notice.summary, { body: notice.body });
        }
    }
    property bool testLocked: false

    readonly property bool _testMode: Modules.host.testMode
    readonly property bool locked: _testMode ? testLocked : Profiles.screenLocked

    // ---- For module.privileged and PrivilegedAction ----

    // A new owner key: what a handle or a PrivilegedAction is known by, so that its runs can
    // leave together (ownerGone)
    function newOwnerKey() {
        _owners++;
        return "owner-" + _owners;
    }

    // A module's run (module.privileged.start). `handle`: the module's handle (moduleId,
    // active, notify(), _privilegedKey); `facts`: { testMode, tools (PrivilegedRules
    // .availability), program (what the handle knows of argv[0]) } → { running, cancel() }.
    // `done` is called once, never inside this call, and never while the module is off (a
    // run asked for then is not answered).
    function start(handle, argv, options, facts) {
        const parsed = PrivilegedRules.options(options);
        const callbacks = parsed.problem === "" ? options : {};
        const job = {
            id: ++_lastId, kind: "module", owner: handle._privilegedKey, handle: handle,
            moduleId: String(handle.moduleId), what: parsed.what, timeoutMs: parsed.timeoutMs,
            notifyFailures: parsed.notifyFailures,
            onStdout: callbacks.onStdout ?? null, onStderr: callbacks.onStderr ?? null, onLine: callbacks.onLine ?? null,
            done: typeof options?.done === "function" ? options.done : null,
            argv: [], program: "", environment: {}, standIns: [], testMode: facts?.testMode === true,
            answered: false, muted: false, runner: null, result: null
        };
        const runHandle = {
            get running() {
                return !job.answered;
            },
            cancel: function () {
                if (!job.answered)
                    root._dispatch({ type: "cancel", id: job.id, killAfterMs: PrivilegedRules.killAfterMs });
            }
        };
        // A module that is off gets no answer at all
        if (handle.active !== true) {
            job.answered = true;
            return runHandle;
        }
        const refused = PrivilegedRules.refusal({
            argv: argv, options: parsed, active: handle.active === true, locked: locked,
            available: facts?.tools?.available === true, unavailableReason: facts?.tools?.reason ?? "",
            program: facts?.program ?? null
        });
        if (refused) {
            if (refused.blocked !== "locked")
                console.warn("[Privileged] " + job.moduleId + ": a run refused before pkexec — " + refused.error.slice(0, 300));
            _refuse(job, PrivilegedRules.refusedResult(refused));
            return runHandle;
        }
        job.argv = PrivilegedRules.pkexecArgv(facts.tools.pkexec, facts.tools.timeout, parsed.timeoutMs, PrivilegedRules.killAfterMs, argv);
        job.program = argv[0];
        // In test mode only the module's own stand-in may be the pkexec
        job.standIns = job.testMode ? [facts.tools.pkexec] : [];
        job.queued = true;
        _jobs.set(job.id, job);
        _dispatch({ type: "add", id: job.id, owner: job.owner });
        return runHandle;
    }

    // A run of the old PrivilegedAction (its checks made, the test-mode gate among them):
    // `request` { owner, argv (elevating program and command, as they run), program
    // (command[0]), environment, standIns (what test mode lets run as pkexec), testMode,
    // moduleId, what }; `answer(reply)` once: { kind: "result" | "notFound" | "locked" |
    // "cancelled" | "refused", result (the runner's, for "result"), lines (stdout's non-empty
    // lines), errorText (stderr), error }. No time limit, as before.
    function startLegacy(request, answer) {
        const job = {
            id: ++_lastId, kind: "legacy", owner: String(request.owner ?? ""), handle: null,
            moduleId: String(request.moduleId || "?"), what: PrivilegedRules.cleanWhat(String(request.what ?? "")),
            timeoutMs: 0, notifyFailures: false, onStdout: null, onStderr: null, onLine: null,
            done: answer, argv: Array.from(request.argv), program: String(request.program),
            environment: request.environment ?? {}, standIns: Array.isArray(request.standIns) ? request.standIns : [],
            testMode: request.testMode === true, answered: false, muted: false, runner: null, result: null,
            lines: [], errorText: ""
        };
        if (locked) {
            _refuse(job, { kind: "locked", error: "the session is locked" });
            return;
        }
        _jobs.set(job.id, job);
        _dispatch({ type: "add", id: job.id, owner: job.owner });
    }

    // Every run of this owner leaves the queue; the started ones are cancelled; nothing of
    // theirs is called any more (a module turned off, a PrivilegedAction destroyed)
    function ownerGone(owner) {
        if (typeof owner !== "string" || owner === "")
            return;
        for (const job of _jobs.values()) {
            if (job.owner === owner)
                job.muted = true;
        }
        _dispatch({ type: "ownerGone", owner: owner, killAfterMs: PrivilegedRules.killAfterMs });
    }

    // pkexec exited 127 for `what`: told once, by the agent in charge (Authentication's
    // reportDenied; the test kit's in module test mode)
    function reportDenied(what) {
        (_testMode ? testAgent : Authentication).reportDenied(String(what));
    }

    // ---- Inside ----

    property var _state: PrivilegedRules.queueStart(false)
    property var _jobs: new Map()
    property int _lastId: 0
    property int _owners: 0
    property var _events: []
    property bool _dispatching: false
    property var _outbox: []

    property bool _known: false
    property string _pkexec: ""
    property string _pkexecReason: "pkexec is still being looked for"

    // The agent is looked at only while a run may still ask: Authentication is not made
    // (nor polkit reached) by a shell or a suite that never runs one
    readonly property bool _watching: PrivilegedRules.queueHead(_state)?.phase === "asking"
    readonly property var _agent: _watching ? (_testMode ? testAgent : Authentication) : null
    readonly property bool _requestOpen: _agent !== null && (_agent.flow ?? null) !== null

    // Taken after the change has settled: the event changes the queue, which this binding
    // reads
    on_RequestOpenChanged: Qt.callLater(root._takeRequest)

    function _takeRequest() {
        _dispatch({ type: "request", open: _requestOpen });
    }
    onLockedChanged: _dispatch({ type: "lock", locked: locked })

    function _agentState() {
        return (_testMode ? testAgent : Authentication).state;
    }

    // Events are taken one at a time, in order, also when an effect leads to another
    function _dispatch(event) {
        _events.push(event);
        if (_dispatching)
            return;
        _dispatching = true;
        try {
            while (_events.length > 0) {
                const next = Object.assign({ now: Date.now() }, _events.shift());
                const stepped = PrivilegedRules.queueStep(_state, next);
                _state = stepped.state;
                for (const effect of stepped.effects)
                    _perform(effect);
            }
        } finally {
            _dispatching = false;
        }
        const deadline = PrivilegedRules.nextDeadline(_state);
        if (deadline > 0) {
            _tick.interval = Math.max(1, deadline - Date.now());
            _tick.restart();
        } else {
            _tick.stop();
        }
    }

    function _perform(effect) {
        const job = _jobs.get(effect.id);
        switch (effect.type) {
        case "check":
            if (job)
                _check(job);
            break;
        case "launch":
            if (job)
                _launch(job);
            break;
        case "signal":
            if (job) {
                job.muted = true;
                job.runner?.cancel();
            }
            break;
        case "answer":
            if (job)
                _answer(job, effect.kind);
            break;
        case "forget":
            if (job) {
                job.answered = true;
                job.muted = true;
                _jobs.delete(job.id);
            }
            break;
        }
    }

    // Its program, looked at just before pkexec is asked (no shell reads the path: it is $1)
    function _check(job) {
        _probe.start([ModuleRules.probeShell, "-c", "[ -f \"$1\" ] && [ -x \"$1\" ]", "sh", job.program], {
            timeoutMs: 5000,
            keepOutput: false,
            environment: { PATH: ModuleRules.probeToolPath },
            done: result => root._dispatch({ type: "checked", id: job.id, found: result.ok,
                                             shellAgent: PrivilegedRules.shellAnswers(root._agentState()) })
        });
    }

    function _launch(job) {
        // Test mode: no pkexec but the stand-ins allowed (ModuleRules.testRunProblem)
        const problem = ModuleRules.testRunProblem(job.argv, job.testMode, job.standIns);
        if (problem !== "") {
            job.result = { refusal: problem };
            Qt.callLater(() => root._dispatch({ type: "exited", id: job.id }));
            return;
        }
        console.log("[Privileged] " + job.moduleId + " runs " + JSON.stringify(job.what.slice(0, 100))
                    + " (" + JSON.stringify(job.program.slice(0, 300)) + ")");
        const legacy = job.kind === "legacy";
        // No time limit around pkexec: the module's limit is the `timeout` inside it
        // (PrivilegedRules.pkexecArgv); the old type has none, as before
        job.runner = _runner.start(job.argv, {
            timeoutMs: 0,
            killAfterMs: PrivilegedRules.killAfterMs,
            environment: job.environment,
            keepOutput: !legacy,
            onStdout: text => {
                if (!job.muted && job.onStdout)
                    job.onStdout(text);
            },
            onStderr: text => {
                if (job.muted)
                    return;
                if (legacy)
                    job.errorText += text;
                else if (job.onStderr)
                    job.onStderr(text);
            },
            onLine: (line, stream) => {
                if (job.muted)
                    return;
                if (legacy) {
                    if (stream === "stdout" && line.trim() !== "")
                        job.lines.push(line);
                } else if (job.onLine) {
                    job.onLine(line, stream);
                }
            },
            done: result => {
                job.result = result;
                root._dispatch({ type: "exited", id: job.id });
            }
        });
    }

    // The answer, handed over after the event that made it (never inside start())
    function _answer(job, kind) {
        job.answered = true;
        job.muted = true;
        _jobs.delete(job.id);
        if (job.kind === "legacy") {
            const refusal = job.result?.refusal;
            _deliver(job, refusal ? { kind: "refused", error: refusal, lines: [], errorText: "" }
                                  : { kind: kind, result: job.result, lines: job.lines, errorText: job.errorText,
                                      error: kind === "locked" ? "the session is locked" : "" });
            return;
        }
        let result;
        if (kind === "locked")
            result = PrivilegedRules.lockedResult();
        else if (kind === "notFound")
            result = PrivilegedRules.notFoundResult(job.program);
        else if (kind === "cancelled")
            result = PrivilegedRules.cancelledResult();
        else if (job.result?.refusal)
            result = PrivilegedRules.refusedResult({ blocked: "", error: job.result.refusal });
        else
            result = PrivilegedRules.runResult(job.result, job.timeoutMs);
        _deliver(job, result);
    }

    function _refuse(job, reply) {
        job.answered = true;
        _deliver(job, reply);
    }

    function _deliver(job, reply) {
        _outbox.push({ job: job, reply: reply });
        _flush.restart();
    }

    function _flushOutbox() {
        const outbox = _outbox;
        _outbox = [];
        for (const entry of outbox) {
            const job = entry.job;
            const reply = entry.reply;
            if (job.kind === "module") {
                // The module turned off meanwhile: nothing of its is called
                if (job.handle && job.handle.active !== true && job.owner !== "")
                    continue;
                if (reply.refused)
                    reportDenied(job.what);
                else if (job.notifyFailures) {
                    const notice = PrivilegedRules.failureNotice(reply, job.what, job.timeoutMs, job.queued === true);
                    if (notice)
                        job.handle.notify(notice.summary, { body: notice.body });
                }
            }
            if (!job.done)
                continue;
            try {
                job.done(reply);
            } catch (error) {
                console.warn("[Privileged] a run's done threw: " + String(error).slice(0, 300));
            }
        }
    }

    property Timer _flush: Timer {
        interval: 0
        onTriggered: root._flushOutbox()
    }

    property Timer _tick: Timer {
        onTriggered: root._dispatch({ type: "tick" })
    }

    property Io.CommandRunner _runner: Io.CommandRunner {}
    property Io.CommandRunner _probe: Io.CommandRunner {}

    // ---- Where pkexec is ----

    property Io.CommandRunner _lookup: Io.CommandRunner {}

    Component.onCompleted: {
        // Locked already when this is made (a shell restarted under its lock)
        _dispatch({ type: "lock", locked: locked });
        const lines = [];
        _lookup.start([ModuleRules.probeShell, "-c", ModuleRules.programProbeScript, "sh", "all", PrivilegedRules.pkexecSearchPath, "pkexec"], {
            timeoutMs: 5000,
            keepOutput: false,
            environment: { PATH: ModuleRules.probeToolPath },
            onLine: (line, stream) => {
                if (stream === "stdout")
                    lines.push(line);
            },
            done: () => {
                const choice = PrivilegedRules.pkexecChoice(lines);
                root._pkexec = choice.path;
                root._pkexecReason = choice.reason;
                root._known = true;
                if (choice.path === "")
                    console.warn("[Privileged] running as administrator is not available: " + choice.reason);
            }
        });
    }
}
