pragma Singleton

import QtQuick
import Quickshell
import qs.singletons.io as Io

// The shell's one queue of commands run as administrator through pkexec: one password
// question at a time, for every module (`module.privileged.start`, api/ModuleHandle.qml),
// the old api/PrivilegedAction.qml and the shell's own fixed commands (startShell). The decisions are PrivilegedRules' (queueStep: when
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
    readonly property bool known: _pkexecFound.known
    // The system's pkexec: the first on PrivilegedRules.pkexecSearchPath (the distribution's
    // places, looked at once Distribution has answered) that only root can
    // change and that is setuid root; "" when none (`pkexecReason` says why)
    readonly property string pkexec: _pkexecFound.pkexec
    readonly property string pkexecReason: _pkexecFound.reason
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
    // The look-up of pkexec held, as if it had not answered yet (released: it answers with
    // what it found)
    property bool testLookupHeld: false

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
        return _queue.decide(flow).announcement;
    }

    // ---- For module.privileged and PrivilegedAction ----

    // A new owner key: what a handle or a PrivilegedAction is known by, so that its runs can
    // leave together (ownerGone)
    function newOwnerKey() {
        return _queue.newOwnerKey();
    }

    // A module's run (module.privileged.start). `handle`: the module's handle (moduleId,
    // active, notify(), _hostKey); `facts`: { owner (the handle's key in this queue: its runs
    // leave together), testMode, tools (PrivilegedRules.availability), declaration
    // (PrivilegedRules.declaration: what its manifest declares) }
    // → { running, cancel() }. `done` is called once, never inside
    // this call, and never while the module is off (a run asked for then is not answered).
    // `argv` and `options` are read once, here (CommandRules.argvSnapshot, a real array
    // only; PrivilegedRules.options): the words judged, the words shown and the words
    // handed to pkexec are that one copy.
    function start(handle, argv, options, facts) {
        const parsed = PrivilegedRules.options(options, facts?.testMode === true);
        const snapshot = CommandRules.argvSnapshot(argv, true);
        const words = snapshot.words;
        const job = {
            id: _queue.newId(), kind: "module", owner: String(facts?.owner ?? ""), handle: handle,
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
                    root._queue.dispatch({ type: "cancel", id: job.id, killAfterMs: PrivilegedRules.killAfterMs });
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
                available: facts?.tools?.available === true, unavailableReason: facts?.tools?.reason ?? "",
                declaration: facts?.declaration ?? null
            });
        if (refused) {
            // Not declared: in the module's status, logged once per text (ModuleHost.reportError)
            if (refused.blocked === "undeclared")
                ModuleHandleHosts.hostOf(handle._hostKey)?.reportError(job.moduleId, refused.error);
            else if (refused.blocked !== "locked")
                console.warn("[Privileged] " + job.moduleId + ": a run refused before pkexec — " + refused.error.slice(0, 300));
            _queue.refuse(job, PrivilegedRules.refusedResult(refused));
            return runHandle;
        }
        job.argv = PrivilegedRules.pkexecArgv(facts.tools.pkexec, facts.tools.timeout, parsed.timeoutMs, PrivilegedRules.killAfterMs, words);
        job.program = words[0];
        // In test mode only the module's own stand-in may be the pkexec; the environment a
        // suite gave (PrivilegedRules.options: test mode only) is the stand-in's
        job.standIns = job.testMode ? [facts.tools.pkexec] : [];
        job.environment = job.testMode ? parsed.environment : {};
        job.queued = true;
        _queue.add(job);
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
            id: _queue.newId(), kind: "legacy", owner: String(request.owner ?? ""), handle: null,
            moduleId: String(request.moduleId || "?"), what: PrivilegedRules.cleanWhat(String(request.what ?? "")),
            timeoutMs: 0, notifyFailures: false, onStdout: null, onStderr: null, onLine: null,
            done: answer, argv: Array.from(request.argv), systemPkexec: request.systemPkexec === true, program: String(request.program),
            environment: request.environment ?? {}, standIns: Array.isArray(request.standIns) ? request.standIns : [],
            testMode: request.testMode === true, answered: false, muted: false, runner: null, result: null,
            lines: [], errorText: "", pkexecWords: [], announcement: null
        };
        if (locked) {
            _queue.refuse(job, { kind: "locked", error: "the session is locked" });
            return;
        }
        _queue.add(job);
    }

    // A fixed command of the shell's own, started by the user's click (a setting's Apply):
    // `request` { what (for the log and a failure's notice), argv (an absolute program and
    // its words, from the shell's code), timeoutMs (optional: a longer limit, at most
    // PrivilegedRules.shellMaxRunMs), onLine (optional: (line, stream) for each line of its
    // output as it comes, as a module's run gets) }; `done(result)` once, never inside this
    // call, with PrivilegedRules' result (ok, code, stdout, stderr, dismissed, refused,
    // notFound, timedOut, cancelled, blocked, error). It runs under the trusted, setuid pkexec
    // found by the look-up (none: refused, not available), inside the shell's trusted
    // `timeout` with its limit, PrivilegedRules.shellRunMs when it asks for none (waiting,
    // checking, for its look-up; none found: refused at the launch); its prompt says who asks
    // ("Shell: h2s-shell", PolkitRules.announcement) and what, the command collapsed, as a
    // module's run. Never from a module's code (the call's stack names a module directory:
    // refused before the queue, so no module is announced as the shell). A refusal is told
    // once, as for every run (reportDenied); another failure as "<what> failed". In module
    // test mode it is refused at its launch — no stand-in is allowed for it, so nothing runs —
    // unless `request.testPkexec` names a module's stand-in pkexec (PrivilegedRules
    // .shellStandIn: the shell's fixture suites), which then runs in the trusted one's place.
    function startShell(request, done) {
        const fromModule = ModuleRules.stackDirectories(new Error().stack, Modules.host.directories).length > 0;
        const words = CommandRules.argvSnapshot(request?.argv, true).argv;
        const options = PrivilegedRules.shellOptions(request);
        const job = {
            id: _queue.newId(), kind: "shell", owner: "shell", handle: null, moduleId: "shell",
            what: PrivilegedRules.cleanWhat(String(request?.what ?? "")), timeoutMs: 0, notifyFailures: true,
            onStdout: null, onStderr: null, onLine: null, done: typeof done === "function" ? done : null,
            argv: [], systemPkexec: true, program: "", environment: {}, standIns: [], testMode: _testMode,
            answered: false, muted: false, runner: null, result: null, pkexecWords: [], announcement: null
        };
        if (fromModule) {
            console.warn("[Privileged] a run of the shell's own asked from a module's code: refused");
            _queue.refuse(job, PrivilegedRules.refusedResult({ blocked: "undeclared", error: "not from a module's code" }));
            return;
        }
        if (words === null || !words[0].startsWith("/")) {
            _queue.refuse(job, PrivilegedRules.refusedResult({ blocked: "", error: "not a command with an absolute program" }));
            return;
        }
        if (options.problem !== "") {
            _queue.refuse(job, PrivilegedRules.refusedResult({ blocked: "", error: options.problem }));
            return;
        }
        if (locked) {
            _queue.refuse(job, PrivilegedRules.lockedResult());
            return;
        }
        // Its words under the shell's trusted timeout are made at its launch (_launch), once
        // the look-up of the timeout has answered: it waits for it while checking
        job.words = words;
        job.timeoutMs = options.timeoutMs;
        job.onLine = options.onLine;
        job.program = String(words[0]);
        const standIn = _testMode ? PrivilegedRules.shellStandIn(true, String(request?.testPkexec ?? ""), Modules.host.testStandIns) : "";
        if (standIn !== "") {
            job.systemPkexec = false;
            job.standIns = [standIn];
        }
        _queue.add(job);
    }

    // Every run of this owner leaves the queue; the started ones are cancelled; nothing of
    // theirs is called any more (a module turned off, a PrivilegedAction destroyed)
    function ownerGone(owner) {
        if (typeof owner !== "string" || owner === "")
            return;
        _queue.ownerGone(owner);
    }

    // pkexec exited 127 for `what`: told once, by the agent in charge (Authentication's
    // reportDenied; the test kit's in module test mode)
    function reportDenied(what) {
        (_testMode ? testAgent : Authentication).reportDenied(String(what));
    }

    // ---- Inside ----

    // The queue: its state, its runs (each with the command it will run as root), the events
    // and answers in flight, the decisions on polkit's requests. A module importing
    // qs.singletons sees this singleton's members, so all of it is held in _queue's closures
    // and nothing of a run is handed out: what is reachable from outside acts on ids and
    // events, never on a queued run's command. `_state` follows its state as a read-only copy
    // (ReadOnlyRules.copy: a write to it changes nothing of the queue)
    readonly property var _state: ReadOnlyRules.copy(_queue.state())
    readonly property var _queue: (function () {
        const box = Qt.createQmlObject("import QtQuick; QtObject { property var state }", root, "PrivilegedRunsQueue");
        box.state = PrivilegedRules.queueStart(false);
        const jobs = new Map();
        let lastId = 0;
        let owners = 0;
        const events = [];
        let dispatching = false;
        let outbox = [];
        // The old type's runs whose program was looked at before the look-up of pkexec
        // answered: still "checking" in the queue (PrivilegedRules.legacyCheckWaits)
        let waitingForLookup = [];
        // The words the last command of the shell's own was launched with, before pkexec's
        // path replaced argv[0] (the fixture suites read it: in test mode it is refused right
        // after)
        let lastShellArgv = [];
        // The decisions for the last requests looked at: frozen { flow, id (the run it was
        // matched to, 0: none), announcement (or null) }, newest last: a request is decided
        // once and its decision never changes
        const decisions = [];

        // The decision for a request: the kept one when it was decided already, else made now —
        // the head's announcement when PolkitRules.announces ties the request to the head
        // (asking, with the shell's prompt, not announced yet), else none
        function decide(flow) {
            if (!flow)
                return Object.freeze({ flow: null, id: 0, announcement: null });
            const kept = decisions.find(decision => decision.flow === flow);
            if (kept)
                return kept;
            const head = PrivilegedRules.queueHead(box.state);
            const job = head ? jobs.get(head.id) : null;
            const own = !!job && !!job.announcement && head.phase === "asking" && head.shellAgent
                && PolkitRules.announces(flow, { pkexecArgv: job.pkexecWords ?? [], announced: head.requestSeen === true });
            const decision = Object.freeze({ flow: flow, id: own ? head.id : 0, announcement: own ? job.announcement : null });
            decisions.push(decision);
            if (decisions.length > 8)
                decisions.shift();
            return decision;
        }

        // A run's entry in the queue's state, or null
        function queued(id) {
            return box.state.jobs.find(entry => entry.id === id) ?? null;
        }

        // Events are taken one at a time, in order, also when an effect leads to another
        function dispatch(event) {
            events.push(event);
            if (dispatching)
                return;
            dispatching = true;
            try {
                while (events.length > 0) {
                    const next = Object.assign({ now: root._now() }, events.shift());
                    const stepped = PrivilegedRules.queueStep(box.state, next);
                    box.state = stepped.state;
                    for (const effect of stepped.effects)
                        perform(effect);
                }
            } finally {
                dispatching = false;
            }
            const deadline = PrivilegedRules.nextDeadline(box.state);
            if (deadline > 0) {
                root._tick.interval = Math.max(1, deadline - root._now());
                root._tick.restart();
            } else {
                root._tick.stop();
            }
        }

        function perform(effect) {
            const job = jobs.get(effect.id);
            switch (effect.type) {
            case "check":
                if (job)
                    check(job);
                break;
            case "launch":
                if (job)
                    launch(job);
                break;
            case "signal":
                if (job) {
                    job.muted = true;
                    job.runner?.cancel();
                }
                break;
            case "answer":
                if (job)
                    answer(job, effect.kind);
                break;
            case "forget":
                if (job) {
                    job.answered = true;
                    job.muted = true;
                    jobs.delete(job.id);
                }
                break;
            }
        }

        // Its program, looked at just before pkexec is asked (no shell reads the path: it is $1).
        // The old type's run naming the trusted pkexec before the look-up has answered stays
        // "checking" until it has, then is looked at again (resumeChecks): a lock ends it
        // meanwhile, and which agent answers is read just before it launches.
        function check(job) {
            root._probe.start([ModuleRules.probeShell, "-c", "[ -f \"$1\" ] && [ -x \"$1\" ]", "sh", job.program], {
                timeoutMs: 5000,
                keepOutput: false,
                // Only the shell's builtin `[` runs: nothing is looked up on this PATH
                environment: { PATH: ModuleRules.probeToolPath(Distribution.detection.facts) },
                done: result => {
                    if (!stillChecking(job))
                        return;
                    if (PrivilegedRules.legacyCheckWaits(job.systemPkexec === true, root._lookupAnswered)
                            || PrivilegedRules.shellCheckWaits(job.kind === "shell", root._timeoutKnown)) {
                        waitingForLookup.push(job);
                        return;
                    }
                    dispatch({ type: "checked", id: job.id, found: result.ok,
                               shellAgent: PrivilegedRules.shellAnswers(root._agentState()) });
                }
            });
        }

        // The run is still the one being checked (not ended by a lock, a cancel, its owner gone)
        function stillChecking(job) {
            return jobs.get(job.id) === job && !job.answered && !job.muted && queued(job.id)?.phase === "checking";
        }

        // The look-up answered: the runs that waited for it are looked at again, those still
        // being checked
        function resumeChecks() {
            const waiting = waitingForLookup;
            waitingForLookup = [];
            for (const job of waiting) {
                if (stillChecking(job))
                    check(job);
            }
        }

        function launch(job) {
            // A command of the shell's own: under the shell's trusted timeout, as a module's run,
            // so that the remembered authorization's rule covers it (PrivilegedRules.shellArgv)
            if (job.kind === "shell") {
                const argv = PrivilegedRules.shellArgv(CommandTools.timeout, job.words, job.timeoutMs);
                if (argv === null) {
                    job.result = { refusal: "running as administrator is not available: no trusted timeout (coreutils) on PATH" };
                    Qt.callLater(() => dispatch({ type: "exited", id: job.id }));
                    return;
                }
                // A suite's stand-in pkexec (test mode only) in place of pkexec by name
                job.argv = job.systemPkexec === true ? argv : [job.standIns[0]].concat(argv.slice(1));
                lastShellArgv = argv;
            }
            // The old type's default "pkexec": the trusted one, once the look-up has answered
            const launch = PrivilegedRules.legacyLaunch(job.argv, job.systemPkexec === true, root._lookupAnswered, root.pkexec, root.pkexecReason);
            job.argv = launch.argv;
            // Test mode: no pkexec but the stand-ins allowed (ModuleRules.testRunProblem)
            const problem = launch.problem !== "" ? launch.problem : ModuleRules.testRunProblem(job.argv, job.testMode, job.standIns);
            if (problem !== "") {
                job.result = { refusal: problem };
                Qt.callLater(() => dispatch({ type: "exited", id: job.id }));
                return;
            }
            // What the prompt shows for it, and what its request is known by: the words after
            // pkexec, the program pkexec is given first (a module's run: the shell's `timeout`)
            job.pkexecWords = job.argv.slice(1);
            // The shell's own command is announced as the shell's: "Shell: h2s-shell" and its `what`
            job.announcement = PolkitRules.announcement({
                shell: job.kind === "shell", legacy: job.kind === "legacy", moduleName: job.handle?.name ?? "", moduleId: job.moduleId,
                what: job.what, pkexecArgv: job.pkexecWords
            });
            console.log("[Privileged] " + job.moduleId + " runs " + JSON.stringify(job.what.slice(0, 100))
                        + " (" + JSON.stringify(job.program.slice(0, 300)) + ")");
            // With another agent, or none, the shell's prompt cannot say who asks: one
            // notification, now, names the module and the purpose (PrivilegedRules.launchNotice).
            // Which agent answers is the queue's, read when its program was checked
            const notice = PrivilegedRules.launchNotice(job.announcement, queued(job.id)?.shellAgent === true);
            if (notice)
                Notifier.send(notice.summary, notice.options);
            const legacy = job.kind === "legacy";
            // The end of its stderr, kept apart from the runner's output (which keeps the first
            // maxOutputBytes): the answer's stderr, so a long run's failure shows its last lines
            job.stderrTail = { lines: [], start: 0, chars: 0 };
            // No time limit around pkexec: a module's or the shell's limit is the `timeout` inside it
            // (PrivilegedRules.pkexecArgv); the old type has none, as before
            job.runner = root._runner.start(job.argv, {
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
                    if (!legacy && stream === "stderr")
                        keepTail(job.stderrTail, line);
                    if (legacy) {
                        if (stream === "stdout" && line.trim() !== "")
                            job.lines.push(line);
                    } else if (job.onLine) {
                        job.onLine(line, stream);
                    }
                },
                done: result => {
                    job.result = result;
                    dispatch({ type: "exited", id: job.id });
                }
            });
        }

        // The answer, handed over after the event that made it (never inside start())
        function answer(job, kind) {
            job.answered = true;
            job.muted = true;
            jobs.delete(job.id);
            if (job.kind === "legacy") {
                const refusal = job.result?.refusal;
                deliver(job, refusal ? { kind: "refused", error: refusal, lines: [], errorText: "" }
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
                result = PrivilegedRules.runResult(Object.assign({}, job.result, { stderr: tailText(job.stderrTail) }), job.timeoutMs);
            deliver(job, result);
        }

        // A stream's last lines, at most PrivilegedRules.stderrTailChars in all (line breaks
        // counted): old lines leave from the front; the array is compacted now and then
        function keepTail(tail, line) {
            tail.lines.push(line);
            tail.chars += line.length + 1;
            while (tail.chars > PrivilegedRules.stderrTailChars + 1 && tail.lines.length - tail.start > 1) {
                tail.chars -= tail.lines[tail.start].length + 1;
                tail.lines[tail.start] = "";
                tail.start++;
            }
            if (tail.start > 4096 && tail.start * 2 > tail.lines.length) {
                tail.lines = tail.lines.slice(tail.start);
                tail.start = 0;
            }
        }

        function tailText(tail) {
            if (!tail)
                return "";
            const text = tail.lines.slice(tail.start).join("\n");
            return text.length > PrivilegedRules.stderrTailChars ? text.slice(text.length - PrivilegedRules.stderrTailChars) : text;
        }

        function refuse(job, reply) {
            job.answered = true;
            deliver(job, reply);
        }

        function deliver(job, reply) {
            outbox.push({ job: job, reply: reply });
            root._flush.restart();
        }

        function flushOutbox() {
            const taken = outbox;
            outbox = [];
            for (const entry of taken) {
                const job = entry.job;
                const reply = entry.reply;
                if (job.kind === "shell") {
                    if (reply.refused)
                        root.reportDenied(job.what);
                    else {
                        const notice = PrivilegedRules.failureNotice(reply, job.what, job.timeoutMs, true);
                        if (notice)
                            Notifier.send(notice.summary, { body: notice.body });
                    }
                }
                if (job.kind === "module") {
                    // The module turned off meanwhile: nothing of its is called
                    if (job.handle && job.handle.active !== true && job.owner !== "")
                        continue;
                    if (reply.refused)
                        root.reportDenied(job.what);
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

        return Object.freeze({
            state: () => box.state,
            newId: () => ++lastId,
            newOwnerKey: () => "owner-" + (++owners),
            add: job => {
                jobs.set(job.id, job);
                dispatch({ type: "add", id: job.id, owner: job.owner });
            },
            ownerGone: owner => {
                for (const job of jobs.values()) {
                    if (job.owner === owner)
                        job.muted = true;
                }
                dispatch({ type: "ownerGone", owner: owner, killAfterMs: PrivilegedRules.killAfterMs });
            },
            refuse: (job, reply) => refuse(job, reply),
            dispatch: event => dispatch(event),
            decide: flow => decide(flow),
            resumeChecks: () => resumeChecks(),
            flushOutbox: () => flushOutbox(),
            lastShellArgv: () => Array.from(lastShellArgv),
            waitingCount: () => waitingForLookup.length
        });
    })()

    // The look-up has answered (in test mode, and not held by the suite)
    readonly property bool _lookupAnswered: _pkexecFound.known && !(_testMode && testLookupHeld)
    // What the look-up of pkexec found, frozen { known, pkexec, reason }. Every run as
    // administrator starts that program, so it is held where nothing outside can write it
    // (a module importing qs.singletons sees this singleton's properties): the look-up, its
    // runner and its answer live in _pkexecLookup's closures, which only look up and read
    readonly property var _pkexecFound: _pkexecLookup.current()
    readonly property var _pkexecLookup: (function () {
        const box = Qt.createQmlObject("import QtQuick; QtObject { property var value }", root, "PrivilegedRunsPkexec");
        box.value = Object.freeze({ known: false, pkexec: "", reason: "pkexec is still being looked for" });
        let runner = null;
        const answer = (path, reason) => {
            box.value = Object.freeze({ known: true, pkexec: String(path), reason: String(reason) });
            if (path === "")
                console.warn("[Privileged] running as administrator is not available: " + reason);
        };
        return Object.freeze({
            current: () => box.value,
            lookUp: () => {
                const searched = PrivilegedRules.pkexecSearchPath(Distribution.detection.facts);
                const toolPath = ModuleRules.probeToolPath(Distribution.detection.facts);
                if (searched === "" || toolPath === "") {
                    answer("", "the distribution is not known, so neither is where pkexec is");
                    return;
                }
                if (runner === null)
                    runner = Qt.createQmlObject("import qs.singletons.io; CommandRunner {}", root, "PrivilegedRunsPkexecLookup");
                const lines = [];
                runner.start([ModuleRules.probeShell, "-c", ModuleRules.programProbeScript, "sh", "all", searched, "pkexec"], {
                    timeoutMs: 5000,
                    keepOutput: false,
                    environment: { PATH: toolPath },
                    onLine: (line, stream) => {
                        if (stream === "stdout")
                            lines.push(line);
                    },
                    done: () => {
                        const choice = PrivilegedRules.pkexecChoice(lines);
                        answer(choice.path, choice.reason);
                    }
                });
            }
        });
    })()

    // The agent is looked at only while a run may still ask: Authentication is not made
    // (nor polkit reached) by a shell or a suite that never runs one
    readonly property bool _watching: PrivilegedRules.queueHead(_state)?.phase === "asking"
    readonly property var _agent: _watching ? (_testMode ? testAgent : Authentication) : null
    readonly property var _requestFlow: _agent !== null ? (_agent.flow ?? null) : null

    // Taken after the change has settled: the event changes the queue, which this binding
    // reads
    on_RequestFlowChanged: Qt.callLater(root._takeRequest)


    // Tells the queue what is open now: any request (`open`), and whether it is the head's
    // own (`own`: decided for this request and the head it was matched to)
    function _takeRequest() {
        const flow = _requestFlow;
        const head = PrivilegedRules.queueHead(_state);
        const decision = _queue.decide(flow);
        _queue.dispatch({ type: "request", open: flow !== null, own: flow !== null && head !== null && decision.id === head.id });
    }

    onLockedChanged: {
        _queue.dispatch({ type: "lock", locked: locked });
        if (_testMode)
            testAgent.closeForLock();
    }


    function _agentState() {
        return (_testMode ? testAgent : Authentication).state;
    }

    // The queue's clock (ms): monotonic (Quickshell's ElapsedTimer, a QElapsedTimer), so a
    // step of the wall clock neither stalls a deadline nor ends one early. Never 0, which
    // means "no deadline".
    readonly property ElapsedTimer _clock: ElapsedTimer {}

    function _now() {
        return Number(_clock.elapsedMs()) + 1;
    }






    on_LookupAnsweredChanged: {
        if (_lookupAnswered)
            _queue.resumeChecks();
    }
    // The look-up of the trusted timeout answered: the shell's own commands waiting for it
    readonly property bool _timeoutKnown: CommandTools.known
    on_TimeoutKnownChanged: {
        if (_timeoutKnown)
            _queue.resumeChecks();
    }








    readonly property Timer _flush: Timer {
        interval: 0
        onTriggered: root._queue.flushOutbox()
    }

    readonly property Timer _tick: Timer {
        onTriggered: root._queue.dispatch({ type: "tick" })
    }

    readonly property Io.CommandRunner _runner: Io.CommandRunner {}
    readonly property Io.CommandRunner _probe: Io.CommandRunner {}

    // ---- Where pkexec is ----


    Component.onCompleted: {
        // Locked already when this is made (a shell restarted under its lock)
        _queue.dispatch({ type: "lock", locked: locked });
        // Looked for once the distribution has answered: its setuid wrappers and program
        // directories are where pkexec is, and its program directories the probe's tools
        Distribution.whenReady(() => root._lookUpPkexec());
    }

    function _lookUpPkexec() {
        _pkexecLookup.lookUp();
    }
}
