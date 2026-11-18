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
// - One log line per run started, with the module's id and its `what`. With the shell's own
//   prompt nothing else shows when polkit lets a run go without a password. With another
//   agent, or none (Authentication.state other than "active" and "conflict"), the shell
//   cannot dress that agent's prompt: one notification just before pkexec starts names the
//   module and the purpose (PrivilegedRules.launchNotice), whether or not a password is
//   then asked.
// - Which request is the head's: with the shell's own prompt (Authentication.state
//   "active" or "conflict") a request is the head's when PolkitRules.announces says so —
//   pkexec's action, and its message quotes the command the head handed to pkexec as
//   pkexec shortens it. Only that request is shown with the head's announcement
//   (announcementFor: "Module", "Authorization", the command), decided once per request:
//   a new head never re-dresses a request still open. The agent shows one request at a
//   time, so the head's own may wait behind another program's: while any request is open
//   the head is held (PrivilegedRules.queueStep, `request { open, own }`), and once its own
//   was seen it lets go when no request is open any more.
// - The session locked (Profiles.screenLocked, which Lockscreen reports): nothing starts,
//   and the runs waiting are answered `dismissed`, `blocked: "locked"`, quietly. The agent
//   closes the open prompt (Authentication; the test kit's agent in test mode): the run
//   whose pkexec asked ends `dismissed` when pkexec exits.
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
    // request (`flow`: null or { actionId, message }), and what reportDenied() tells. Like
    // Authentication, it closes its request when the session locks
    readonly property QtObject testAgent: QtObject {
        property string state: "active"
        property var flow: null

        onFlowChanged: closeForLock()

        function closeForLock() {
            if (PolkitRules.closesForLock(root.locked, flow !== null))
                flow = null;
        }

        function reportDenied(what) {
            const notice = PolkitRules.deniedNotice(state, what);
            Notifier.send(notice.summary, { body: notice.body });
        }
    }
    property bool testLocked: false

    readonly property bool _testMode: Modules.host.testMode
    readonly property bool locked: _testMode ? testLocked : Profiles.screenLocked

    // ---- For the prompt ----

    // What the prompt shows for a request (`flow`) besides polkit's own words: the head's
    // announcement (PolkitRules.announcement: module, authorization, command) when the
    // request is the head's, else null. Decided the first time the request is looked at
    // (here or by the queue, _takeRequest) and kept for it: the prompt is dressed from its
    // first frame, and a request still open when the next run becomes the head is never
    // dressed as that run's.
    function announcementFor(flow) {
        return _decide(flow).announcement;
    }

    // ---- For module.privileged and PrivilegedAction ----

    // A new owner key: what a handle or a PrivilegedAction is known by, so that its runs can
    // leave together (ownerGone)
    function newOwnerKey() {
        _owners++;
        return "owner-" + _owners;
    }

    // A module's run (module.privileged.start). `handle`: the module's handle (moduleId,
    // active, notify(), _privilegedKey); `facts`: { testMode, tools (PrivilegedRules
    // .availability) } → { running, cancel() }. `done` is called once, never inside
    // this call, and never while the module is off (a run asked for then is not answered).
    // `argv` and `options` are read once, here (CommandRules.argvSnapshot, a real array
    // only; PrivilegedRules.options): the words judged, the words shown and the words
    // handed to pkexec are that one copy.
    function start(handle, argv, options, facts) {
        const parsed = PrivilegedRules.options(options);
        const snapshot = CommandRules.argvSnapshot(argv, true);
        const words = snapshot.words;
        const job = {
            id: ++_lastId, kind: "module", owner: handle._privilegedKey, handle: handle,
            moduleId: String(handle.moduleId), what: parsed.what, timeoutMs: parsed.timeoutMs,
            notifyFailures: parsed.notifyFailures,
            onStdout: parsed.callbacks.onStdout, onStderr: parsed.callbacks.onStderr, onLine: parsed.callbacks.onLine,
            done: parsed.callbacks.done,
            argv: [], program: "", environment: {}, standIns: [], testMode: facts?.testMode === true,
            answered: false, muted: false, runner: null, result: null,
            pkexecWords: [], announcement: null
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
        const refused = parsed.problem === "" && words === null
            ? { blocked: "", notFound: false, error: snapshot.problem }
            : PrivilegedRules.refusal({
                argv: words, options: parsed, active: handle.active === true, locked: locked,
                available: facts?.tools?.available === true, unavailableReason: facts?.tools?.reason ?? ""
            });
        if (refused) {
            if (refused.blocked !== "locked")
                console.warn("[Privileged] " + job.moduleId + ": a run refused before pkexec — " + refused.error.slice(0, 300));
            _refuse(job, PrivilegedRules.refusedResult(refused));
            return runHandle;
        }
        job.argv = PrivilegedRules.pkexecArgv(facts.tools.pkexec, facts.tools.timeout, parsed.timeoutMs, PrivilegedRules.killAfterMs, words);
        job.program = words[0];
        // In test mode only the module's own stand-in may be the pkexec
        job.standIns = job.testMode ? [facts.tools.pkexec] : [];
        job.queued = true;
        _jobs.set(job.id, job);
        _dispatch({ type: "add", id: job.id, owner: job.owner });
        return runHandle;
    }

    // A run of the old PrivilegedAction (its checks made, the test-mode gate among them):
    // `request` { owner, argv (elevating program and command, as they run), systemPkexec
    // (PrivilegedRules.legacySystemPkexec: argv[0] is replaced by the trusted `pkexec` when
    // the run starts; none found — the run is answered "refused", not available), program
    // (command[0]), environment, standIns (what test mode lets run as pkexec), testMode,
    // moduleId, what }; `answer(reply)` once: { kind: "result" | "notFound" | "locked" |
    // "cancelled" | "refused", result (the runner's, for "result"), lines (stdout's non-empty
    // lines), errorText (stderr), error }. No time limit, as before.
    function startLegacy(request, answer) {
        const job = {
            id: ++_lastId, kind: "legacy", owner: String(request.owner ?? ""), handle: null,
            moduleId: String(request.moduleId || "?"), what: PrivilegedRules.cleanWhat(String(request.what ?? "")),
            timeoutMs: 0, notifyFailures: false, onStdout: null, onStderr: null, onLine: null,
            done: answer, argv: Array.from(request.argv), systemPkexec: request.systemPkexec === true, program: String(request.program),
            environment: request.environment ?? {}, standIns: Array.isArray(request.standIns) ? request.standIns : [],
            testMode: request.testMode === true, answered: false, muted: false, runner: null, result: null,
            lines: [], errorText: "", pkexecWords: [], announcement: null
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
    // The old type's runs whose turn came before the look-up of pkexec answered
    property var _waitingForLookup: []
    property string _pkexec: ""
    property string _pkexecReason: "pkexec is still being looked for"

    // The agent is looked at only while a run may still ask: Authentication is not made
    // (nor polkit reached) by a shell or a suite that never runs one
    readonly property bool _watching: PrivilegedRules.queueHead(_state)?.phase === "asking"
    readonly property var _agent: _watching ? (_testMode ? testAgent : Authentication) : null
    readonly property var _requestFlow: _agent !== null ? (_agent.flow ?? null) : null
    // The decisions for the last requests looked at: [{ flow, id (the run it was matched to,
    // 0: none), announcement (or null) }], newest last. A plain array changed in place — no
    // binding is told: a request is decided once and its decision never changes.
    readonly property var _decisions: []

    // Taken after the change has settled: the event changes the queue, which this binding
    // reads
    on_RequestFlowChanged: Qt.callLater(root._takeRequest)

    // The decision for a request: the kept one when it was decided already, else made now —
    // the head's announcement when PolkitRules.announces ties the request to the head
    // (asking, with the shell's prompt, not announced yet), else none
    function _decide(flow) {
        if (!flow)
            return { flow: null, id: 0, announcement: null };
        const kept = _decisions.find(decision => decision.flow === flow);
        if (kept)
            return kept;
        const head = PrivilegedRules.queueHead(_state);
        const job = head ? _jobs.get(head.id) : null;
        const own = !!job && !!job.announcement && head.phase === "asking" && head.shellAgent
            && PolkitRules.announces(flow, { pkexecArgv: job.pkexecWords ?? [], announced: head.requestSeen === true });
        const decision = { flow: flow, id: own ? head.id : 0, announcement: own ? job.announcement : null };
        _decisions.push(decision);
        if (_decisions.length > 8)
            _decisions.shift();
        return decision;
    }

    // Tells the queue what is open now: any request (`open`), and whether it is the head's
    // own (`own`: decided for this request and the head it was matched to)
    function _takeRequest() {
        const flow = _requestFlow;
        const head = PrivilegedRules.queueHead(_state);
        const decision = _decide(flow);
        _dispatch({ type: "request", open: flow !== null, own: flow !== null && head !== null && decision.id === head.id });
    }

    onLockedChanged: {
        _dispatch({ type: "lock", locked: locked });
        if (_testMode)
            testAgent.closeForLock();
    }

    // A run's entry in the queue's state, or null
    function _queued(id) {
        return _state.jobs.find(entry => entry.id === id) ?? null;
    }

    function _agentState() {
        return (_testMode ? testAgent : Authentication).state;
    }

    // The queue's clock (ms): monotonic (Quickshell's ElapsedTimer, a QElapsedTimer), so a
    // step of the wall clock neither stalls a deadline nor ends one early. Never 0, which
    // means "no deadline".
    property ElapsedTimer _clock: ElapsedTimer {}

    function _now() {
        return Number(_clock.elapsedMs()) + 1;
    }

    // Events are taken one at a time, in order, also when an effect leads to another
    function _dispatch(event) {
        _events.push(event);
        if (_dispatching)
            return;
        _dispatching = true;
        try {
            while (_events.length > 0) {
                const next = Object.assign({ now: _now() }, _events.shift());
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
            _tick.interval = Math.max(1, deadline - _now());
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
        // The old type's default "pkexec": the trusted one, once the look-up has answered
        const launch = PrivilegedRules.legacyLaunch(job.argv, job.systemPkexec === true, _known, _pkexec, _pkexecReason);
        if (launch.wait) {
            _waitingForLookup.push(job);
            return;
        }
        job.argv = launch.argv;
        // Test mode: no pkexec but the stand-ins allowed (ModuleRules.testRunProblem)
        const problem = launch.problem !== "" ? launch.problem : ModuleRules.testRunProblem(job.argv, job.testMode, job.standIns);
        if (problem !== "") {
            job.result = { refusal: problem };
            Qt.callLater(() => root._dispatch({ type: "exited", id: job.id }));
            return;
        }
        // What the prompt shows for it, and what its request is known by: the words after
        // pkexec, the program pkexec is given first (a module's run: the shell's `timeout`)
        job.pkexecWords = job.argv.slice(1);
        job.announcement = PolkitRules.announcement({
            legacy: job.kind === "legacy", moduleName: job.handle?.name ?? "", moduleId: job.moduleId,
            what: job.what, pkexecArgv: job.pkexecWords
        });
        console.log("[Privileged] " + job.moduleId + " runs " + JSON.stringify(job.what.slice(0, 100))
                    + " (" + JSON.stringify(job.program.slice(0, 300)) + ")");
        // With another agent, or none, the shell's prompt cannot say who asks: one
        // notification, now, names the module and the purpose (PrivilegedRules.launchNotice).
        // Which agent answers is the queue's, read when its program was checked
        const notice = PrivilegedRules.launchNotice(job.announcement, _queued(job.id)?.shellAgent === true);
        if (notice)
            Notifier.send(notice.summary, notice.options);
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
                const waiting = root._waitingForLookup;
                root._waitingForLookup = [];
                for (const job of waiting) {
                    if (root._jobs.get(job.id) === job && !job.answered && !job.muted)
                        root._launch(job);
                }
            }
        });
    }
}
