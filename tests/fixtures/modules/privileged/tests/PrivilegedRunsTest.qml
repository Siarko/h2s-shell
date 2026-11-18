import QtQuick
import qs.api
import qs.tests

// Running as administrator from a module's side (tests/run-modules.sh, module test mode):
// module.privileged.start against the fixture's stand-in pkexec (tests/programs/pkexec, which
// prints the words it was given and runs them) and its command (tests/programs/talk). The
// polkit agent and the lock are the test kit's (ModuleTestKit.setPolkitAgent,
// setPolkitRequest, setSessionLocked; polkitAnnouncement: what the prompt would show). One
// scenario after another, each starting with the shell's queue idle: they share the one
// queue.
TestCase {
    id: suite
    suiteName: "privileged: runs as administrator"
    asynchronous: true
    timeLimitMs: 60000

    readonly property var module: Api.moduleAt(Qt.resolvedUrl("."))
    property var _steps: []
    property var _runs: ({})

    function _then(description, condition, action) {
        _steps.push({ description: description, condition: condition, action: action });
    }

    property Timer _clock: Timer {
        interval: 25
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

    function _path(name) {
        return module.programs[name]?.path ?? "";
    }

    // Starts a run and records what it hands over: its stdout lines (and when the first came,
    // and "started"), its stdout text, its done (and whether inside start())
    function _start(name, argv, extra) {
        const record = { lines: [], stdout: "", stderr: "", firstLineAt: 0, startedAt: 0, doneAt: 0, result: null, handle: null,
                         inside: true, doneInside: false, linesAfterCancel: 0, cancelledAt: 0 };
        _runs[name] = record;
        const options = Object.assign({
            what: name,
            timeoutMs: 30000,
            onLine: (line, stream) => {
                if (stream !== "stdout")
                    return;
                if (record.cancelledAt > 0)
                    record.linesAfterCancel++;
                if (record.firstLineAt === 0)
                    record.firstLineAt = Date.now();
                if (line === "started")
                    record.startedAt = Date.now();
                record.lines.push(line);
            },
            onStdout: text => record.stdout += text,
            onStderr: text => record.stderr += text,
            done: result => {
                record.doneInside = record.inside;
                record.result = result;
                record.doneAt = Date.now();
            }
        }, extra ?? {});
        record.handle = module.privileged.start(argv, options);
        record.inside = false;
        return record;
    }

    function _cancel(name) {
        _runs[name].cancelledAt = Date.now();
        _runs[name].handle.cancel();
    }

    function _done(...names) {
        return names.every(name => _runs[name]?.result !== null && _runs[name]?.result !== undefined);
    }

    function _idle() {
        return ModuleTestKit.privilegedIdle;
    }

    function runAsync() {
        assert(Api.testMode, "test mode is on");
        _then("its programs are known and running as administrator is available",
              () => module?.programsReady === true && module.privileged.available, () => _refusals());
        _clock.start();
    }

    // --- Refused before pkexec runs: every `blocked` reason, notFound, errors ---
    function _refusals() {
        assertEqual(module.privileged.unavailableReason, "", "available: no reason given");
        assert(_path("pkexec").endsWith("/tests/programs/pkexec"), "its pkexec is its stand-in: " + _path("pkexec"));
        ModuleTestKit.clearRecords();
        const talk = _path("talk");
        _start("relative", ["talk", "lines", "1", "0"]);
        _start("newline", [talk, "lines", "a\nb"]);
        _start("rtl", [talk, "lines", "report‮fdp.exe"]);
        _start("purpose", [talk, "lines", "1", "0"], { what: " ​\n " });
        _start("absent", [_path("absent"), "x"]);
        _start("no limit", [talk, "lines", "1", "0"], { timeoutMs: undefined });
        _start("too short", [talk, "lines", "1", "0"], { timeoutMs: 500 });
        _start("too long", [talk, "lines", "1", "0"], { timeoutMs: 3600001 });
        const handle = module.privileged.start([talk], "Connect");
        assert(handle && typeof handle.cancel === "function", "options not an object: a handle all the same");
        ModuleTestKit.setSessionLocked(true);
        _start("locked", [talk, "lines", "1", "0"]);
        ModuleTestKit.setSessionLocked(false);
        assert(Object.keys(_runs).every(name => !_runs[name].handle || _runs[name].handle.running === false),
               "a refused run is not running from the start");
        _then("every refusal is answered", () => _done("relative", "newline", "rtl", "purpose", "absent",
                                                       "no limit", "too short", "too long", "locked"), () => {
            const blocked = name => _runs[name].result.blocked;
            const relative = _runs.relative.result;
            assert(relative.notFound && relative.blocked === "" && !relative.ok, "argv[0] not an absolute path: notFound: " + JSON.stringify(relative));
            assertEqual(blocked("newline") + " " + blocked("rtl"), "unprintable unprintable", "a newline, U+202E in a word: unprintable");
            assertEqual(blocked("purpose"), "no-purpose", "what empty after cleaning: no-purpose");
            const locked = _runs.locked.result;
            assert(locked.blocked === "locked" && locked.dismissed && !locked.cancelled && !locked.ok, "asked for while locked: dismissed, blocked locked");
            const absent = _runs.absent.result;
            assert(absent.notFound && absent.blocked === "" && !absent.ok, "a program not found (path \"\"): notFound: " + JSON.stringify(absent));
            for (const name of ["no limit", "too short", "too long"])
                assert(_runs[name].result.error.startsWith("timeoutMs") && _runs[name].result.blocked === "", name + ": an error, timeoutMs named");
            for (const name of Object.keys(_runs).filter(key => _runs[key].handle)) {
                const record = _runs[name];
                assert(!record.doneInside && record.lines.length === 0 && Object.isFrozen(record.result) && record.result.code === -1,
                       name + ": answered after start() returned, frozen, nothing ran");
            }
            assertEqual(ModuleTestKit.notified.map(entry => entry.summary).join(", "), "relative failed, absent failed",
                        "refusals notify nothing — the locked one quietly — but a program not found");
            _unparsed();
        });
    }

    // --- The command is not parsed: a program named as a shell, handed `-c`, runs like any
    // other ---
    function _unparsed() {
        _runs = {};
        const shell = _path("sh");
        _start("shell", [shell, "-c", "echo hi"]);
        // Test mode: a pkexec among the words, other than the stand-in, is never run
        _start("pkexec word", [_path("talk"), "lines", "/usr/bin/pkexec"]);
        _then("the shell's run is answered", () => _done("shell", "pkexec word"), () => {
            const stray = _runs["pkexec word"].result;
            assert(!stray.ok && stray.error.includes("pkexec") && _pkexecWords(stray).length === 0 && _runs["pkexec word"].lines.length === 0,
                   "a pkexec word in test mode: an error, nothing run: " + JSON.stringify(stray));
            const result = _runs.shell.result;
            const words = _pkexecWords(result);
            assert(result.ok && result.blocked === "" && words[4] === shell, "it ran through pkexec: " + JSON.stringify(result));
            assertEqual(result.stdout, "sh ran: -c echo hi", "… with its words as given");
        });
        _then("the queue is idle", () => _idle(), () => _swapped());
    }

    // The words the stand-in pkexec printed it was given, after "pkexec:"
    function _pkexecWords(result) {
        return result.stderr.split("\n").filter(line => line.startsWith("pkexec:")).map(line => line.slice(7));
    }

    // --- argv read once: an accessor or a Proxy that shows one program to the checks and
    // another at the start runs the first, or nothing ---
    function _swapped() {
        _runs = {};
        const talk = _path("talk");
        const shell = _path("sh");
        // Element 0 answers `talk` for its first `firstReads` reads, then the shell: whichever
        // read the start would take, it must be the one that was judged
        for (let firstReads = 1; firstReads <= 12; firstReads++) {
            const argv = ["x", "-c", "echo PWNED"];
            let reads = 0;
            Object.defineProperty(argv, 0, { get() { return ++reads <= firstReads ? talk : shell; }, enumerable: true });
            _start("accessor " + firstReads, argv);
        }
        // A Proxy: element 0 and `length` change after their first read
        const asked = { word: 0, length: 0 };
        _start("proxy", new Proxy([talk, "-c", "echo PWNED"], {
            get(target, key) {
                if (key === "0")
                    return ++asked.word === 1 ? talk : shell;
                if (key === "length")
                    return ++asked.length === 1 ? 3 : 1;
                return target[key];
            }
        }));
        _start("array-like", { 0: talk, 1: "lines", 2: "1", 3: "0", length: 4 });
        _start("string object", [new String(talk), "lines", "1", "0"]);
        _then("the swapped runs are answered", () => _done("proxy", "array-like", "string object")
              && Object.keys(_runs).filter(name => name.startsWith("accessor")).every(name => _done(name)), () => {
            for (const name of Object.keys(_runs).filter(key => key.startsWith("accessor") || key === "proxy")) {
                const result = _runs[name].result;
                const words = _pkexecWords(result);
                assert(!result.stdout.includes("PWNED") && result.ok && words[4] === talk && words.length === 7,
                       name + ": the program judged is the one that ran, with the words read once"
                       + (result.ok && words[4] === talk ? "" : ": " + JSON.stringify(result)));
            }
            assertEqual(asked.word + " " + asked.length, "1 1", "the Proxy: element 0 and length each read once");
            for (const name of ["array-like", "string object"]) {
                const result = _runs[name].result;
                assert(!result.ok && result.blocked === "" && result.error !== "" && _pkexecWords(result).length === 0,
                       name + ": refused as not an array of strings, nothing ran: " + JSON.stringify(result));
            }
            _streaming();
        });
    }

    // --- Streaming, and the time limit inside pkexec ---
    function _streaming() {
        _runs = {};
        const talk = _path("talk");
        _start("stream", [talk, "lines", "3", "0.3"], { timeoutMs: 2500 });
        _then("the streamed run ends", () => _done("stream"), () => {
            const record = _runs.stream;
            const result = record.result;
            assert(result.ok && result.code === 0 && !result.dismissed && !result.refused && result.blocked === "", "it ran and exited 0: " + JSON.stringify(result));
            assertEqual(record.lines.join(","), "line 1,line 2,line 3", "every line through onLine, in order");
            assert(record.firstLineAt > 0 && record.doneAt - record.firstLineAt >= 400, "the first line came while it ran, before done (" + (record.doneAt - record.firstLineAt) + " ms)");
            assertEqual(record.stdout, "line 1\nline 2\nline 3\n", "onStdout: each line with its break");
            assertEqual(result.stdout, "line 1\nline 2\nline 3", "the result's stdout");
            assert(record.stderr.includes("to stderr\n") && result.stderr.includes("to stderr"), "stderr separate");
            // The words the stand-in pkexec was given, as it printed them
            const words = result.stderr.split("\n").filter(line => line.startsWith("pkexec:")).map(line => line.slice(7));
            assert(words[0].startsWith("/") && words[0].endsWith("/timeout"), "pkexec runs the shell's timeout, by its absolute path: " + words[0]);
            assertEqual(JSON.stringify(words.slice(1)), JSON.stringify(["-k", "3", "2.5", talk, "lines", "3", "0.3"]),
                        "… with its kill-after and the run's limit, then the command as given");
            _limit();
        });
    }

    function _limit() {
        ModuleTestKit.clearRecords();
        _start("limit", [_path("talk"), "sleep", "20"], { timeoutMs: 1000, what: "Sleep" });
        _then("the run past its limit ends", () => _done("limit"), () => {
            const result = _runs.limit.result;
            assert(result.timedOut && result.code === 124 && !result.ok && !result.cancelled, "the timeout inside pkexec ended it at its limit: " + JSON.stringify(result));
            assert(result.code === 124 && _runs.limit.doneAt - _runs.limit.startedAt < 5000, "… soon after the limit");
            const told = ModuleTestKit.notified.filter(entry => entry.summary === "Sleep failed");
            assert(told.length === 1 && told[0].body === "It did not end within 1 s" && told[0].appName === module.name,
                   "one notification, under the module's name: " + JSON.stringify(ModuleTestKit.notified));
            _denied();
        });
    }

    // --- 126 and 127 ---
    function _denied() {
        ModuleTestKit.clearRecords();
        _start("dismissed", [_path("dismiss")], { what: "Dismiss me" });
        _start("refused", [_path("refuse")], { what: "Refuse me" });
        _then("both answered", () => _done("dismissed", "refused"), () => {
            assert(_runs.dismissed.result.dismissed && !_runs.dismissed.result.refused, "126: dismissed");
            assert(_runs.refused.result.refused && !_runs.refused.result.dismissed, "127: refused");
            const told = ModuleTestKit.notified;
            assertEqual(told.length, 1, "one notification for both: none for the dismissed one, one for the refused: " + JSON.stringify(told));
            assertEqual(told[0]?.summary, "Refuse me — not allowed", "127 reported once, by the agent");
        });
        _then("the queue is idle", () => _idle(), () => _cancels());
    }

    // --- Cancel while queued, cancel after start, the next run after a cancelled one ---
    function _cancels() {
        _runs = {};
        // Another agent: strictly one run at a time
        ModuleTestKit.setPolkitAgent("other");
        const talk = _path("talk");
        _start("first", [talk, "sleep", "20"]);
        _start("queued", [talk, "lines", "1", "0"]);
        _then("the first run has started", () => _runs.first.startedAt > 0, () => {
            assert(_runs.queued.handle.running && _runs.queued.firstLineAt === 0, "with another agent the second waits while the first runs");
            _cancel("queued");
        });
        _then("the queued run is answered", () => _done("queued"), () => {
            const queued = _runs.queued;
            assert(queued.result.cancelled && !queued.result.ok && !queued.handle.running, "cancel while queued: cancelled");
            assert(queued.doneAt - queued.cancelledAt < 1000 && queued.lines.length === 0, "… at once, and it never ran");
            assert(_runs.first.handle.running, "… the first still runs");
            _start("after", [talk, "lines", "1", "0"]);
            _cancel("first");
        });
        _then("the first and the next are answered", () => _done("first", "after"), () => {
            const first = _runs.first;
            assert(first.result.cancelled && !first.result.ok && !first.result.timedOut, "cancel after start: cancelled");
            assert(first.doneAt - first.cancelledAt < 2500, "… its pkexec signalled and gone before killAfterMs (" + (first.doneAt - first.cancelledAt) + " ms)");
            assertEqual(first.linesAfterCancel, 0, "… no line handed over after cancel()");
            const after = _runs.after;
            assert(after.result.ok && after.firstLineAt >= first.cancelledAt, "the next one started only after the first was cancelled");
            assert(after.firstLineAt >= first.doneAt - 50, "… and once the cancelled one had gone");
        });
        _then("the queue is idle", () => _idle(), () => _cancelHeld());
    }

    // A cancelled run that does not end on TERM (as one run as root, which the shell cannot
    // signal): the next waits until it has gone or killAfterMs has passed
    function _cancelHeld() {
        _runs = {};
        ModuleTestKit.setPolkitAgent("active");
        const talk = _path("talk");
        _start("held", [talk, "hold", "5"]);
        _then("the held run has started", () => _runs.held.startedAt > 0, () => {
            // The shell's prompt asks for its password: the head is held
            ModuleTestKit.setPolkitRequest(true);
            _start("next", [talk, "lines", "1", "0"]);
            _cancel("held");
            ModuleTestKit.setPolkitRequest(false);
        });
        _then("both are answered", () => _done("held", "next"), () => {
            const held = _runs.held;
            const next = _runs.next;
            assert(held.result.cancelled, "the held run: cancelled");
            const waited = next.firstLineAt - held.cancelledAt;
            assert(waited >= 2500, "the next run waited for the cancelled one's end (" + waited + " ms; killAfterMs is 3000)");
            assert(next.firstLineAt >= held.doneAt - 50, "… it started once the cancelled one was answered");
            assert(next.result.ok, "… and ran");
        });
        _then("the queue is idle", () => _idle(), () => _requestEnds());
    }

    // --- The head: released when the shell's request ended, or after 2 s with none ---
    function _requestEnds() {
        _runs = {};
        const talk = _path("talk");
        _start("asking", [talk, "sleep", "20"]);
        _then("the asking run has started", () => _runs.asking.startedAt > 0, () => {
            ModuleTestKit.setPolkitRequest(true);
            _start("behind", [talk, "lines", "1", "0"]);
            // The words the stand-in pkexec was given, as it printed them
            const words = _runs.asking.stderr.split("\n").filter(line => line.startsWith("pkexec:")).map(line => line.slice(7));
            const shown = ModuleTestKit.polkitAnnouncement;
            assert(shown !== null, "the head's request (pkexec's message names its command) is announced");
            assertEqual(shown?.module, "Privileged fixture (privileged)", "Module: the manifest's name, the id after it");
            assertEqual(shown?.authorization, "asking", "Authorization: the run's what");
            assert(words.length === 7 && words.every(word => /^[A-Za-z0-9_@%+=:,.\/-]+$/.test(word)), "the stand-in's words, none needing quotes: " + JSON.stringify(words));
            assertEqual(shown?.command, words.join(" "), "the command shown is the very words handed to pkexec");
            assert(words[1] === "-k" && words[4] === talk, "… the shell's timeout in front: " + JSON.stringify(words));
        });
        _then("3 s with the request open", () => _runs.asking.startedAt > 0 && Date.now() - _runs.asking.startedAt >= 3000, () => {
            assertEqual(_runs.behind.firstLineAt, 0, "while the shell's request is open the next run waits, past the 2 s");
            _runs.asking.requestEndedAt = Date.now();
            ModuleTestKit.setPolkitRequest(false);
        });
        _then("the next one has run", () => _done("behind"), () => {
            assert(_runs.behind.result.ok && _runs.behind.firstLineAt >= _runs.asking.requestEndedAt,
                   "the request ended: the head let go, the next ran");
            assert(_runs.asking.handle.running, "… while the first still runs");
            _cancel("asking");
        });
        _then("the asking run is answered", () => _done("asking") && _idle(), () => _foreignRequest());
    }

    // --- Another program's request: neither holds nor releases the head, never announced
    // (one open before the run started, one while it asks, one replacing the head's own) ---
    function _foreignRequest() {
        _runs = {};
        const talk = _path("talk");
        const foreign = { actionId: "org.freedesktop.policykit.exec", message: "Authentication is needed to run `/usr/bin/true' as the super user" };
        // Open before the run starts
        ModuleTestKit.setPolkitRequest(true, foreign);
        _start("asking", [talk, "sleep", "20"]);
        _start("behind", [talk, "lines", "1", "0"]);
        let dressed = false;
        _then("the next one has run", () => {
            dressed = dressed || ModuleTestKit.polkitAnnouncement !== null;
            return _done("behind");
        }, () => {
            const after = _runs.behind.firstLineAt - _runs.asking.startedAt;
            assert(after >= 1500 && after < 4500, "a foreign request open at launch does not hold the head: released by the 2 s rule (" + after + " ms)");
            assert(!dressed, "… and it is never shown with the run's lines");
            ModuleTestKit.setPolkitRequest(false);
            _cancel("asking");
        });
        _then("the first is answered", () => _done("asking") && _idle(), () => {
            _start("own", [talk, "sleep", "20"]);
            _start("third", [talk, "lines", "1", "0"]);
        });
        _then("the run has started", () => _runs.own.startedAt > 0, () => {
            ModuleTestKit.setPolkitRequest(true);
            assert(ModuleTestKit.polkitAnnouncement !== null, "its own request is announced");
            _runs.own.askedAt = Date.now();
        });
        // Held past the 2 s by its own request; then another program's in its place
        _then("3 s with its request open", () => Date.now() - _runs.own.askedAt >= 3000, () => {
            assertEqual(_runs.third.firstLineAt, 0, "its own request holds the head past the 2 s");
            assert(ModuleTestKit.polkitAnnouncement !== null, "… announced all the while");
            ModuleTestKit.setPolkitRequest(true, foreign);
            assertEqual(ModuleTestKit.polkitAnnouncement, null, "a foreign request in its place is not announced");
            _runs.own.replacedAt = Date.now();
        });
        _then("the third has run", () => _done("third"), () => {
            assert(_runs.third.firstLineAt >= _runs.own.replacedAt, "the head's own request ended (replaced): let go");
            // The same head asking again: announced once, the second is shown as polkit sent it
            ModuleTestKit.setPolkitRequest(true);
            assertEqual(ModuleTestKit.polkitAnnouncement, null, "a request after the head's ended is not announced");
            ModuleTestKit.setPolkitRequest(false);
            _cancel("own");
        });
        _then("the queue is idle", () => _done("own") && _idle(), () => _quietHead());
    }

    function _quietHead() {
        _runs = {};
        const talk = _path("talk");
        _start("quiet", [talk, "sleep", "20"]);
        _start("second", [talk, "lines", "1", "0"]);
        _then("the second has run", () => _done("second"), () => {
            const quiet = _runs.quiet;
            const after = _runs.second.firstLineAt - quiet.startedAt;
            assert(after >= 1500 && after < 4500, "no request: the head let go about 2 s after the first started (" + after + " ms)");
            assert(quiet.handle.running && quiet.result === null, "… the first still running: a long run does not block the others");
            _cancel("quiet");
        });
        _then("the quiet run is answered", () => _done("quiet") && _idle(), () => _turnedOff());
    }

    // --- The module turned off with runs waiting and running ---
    function _turnedOff() {
        _runs = {};
        ModuleTestKit.setPolkitAgent("other");
        const talk = _path("talk");
        _start("running", [talk, "sleep", "20"]);
        _start("waiting", [talk, "lines", "1", "0"]);
        _then("the running one has started", () => _runs.running.startedAt > 0, () => {
            assert(ModuleTestKit.setEnabled("privileged", false), "turned off");
        });
        _then("the module is off", () => module.active === false, () => {
            _start("while off", [talk, "lines", "1", "0"]);
            assert(ModuleTestKit.setEnabled("privileged", true), "turned on again");
        });
        _then("the module is on again", () => module.active === true, () => {
            _start("on again", [talk, "lines", "1", "0"]);
        });
        _then("a run after it is on again has run", () => _done("on again"), () => {
            assert(_runs["on again"].result.ok, "after it is on again a run goes through: the cancelled one left the head");
            for (const name of ["running", "waiting", "while off"])
                assert(_runs[name].result === null && !_runs[name].handle.running, name + ": no callback at all, not running");
        });
        _then("the queue is idle", () => _idle(), () => _locked());
    }

    // --- The session locks with runs waiting ---
    function _locked() {
        _runs = {};
        ModuleTestKit.clearRecords();
        ModuleTestKit.setPolkitAgent("active");
        const talk = _path("talk");
        _start("going", [talk, "sleep", "20"]);
        _start("waiting 1", [talk, "lines", "1", "0"]);
        _start("waiting 2", [talk, "lines", "1", "0"]);
        _then("the first has started", () => _runs.going.startedAt > 0, () => {
            ModuleTestKit.setPolkitRequest(true);
            assert(ModuleTestKit.polkitRequestOpen && ModuleTestKit.polkitAnnouncement !== null, "its request is open, announced");
            ModuleTestKit.setSessionLocked(true);
            assert(!ModuleTestKit.polkitRequestOpen, "the session locks: the open prompt is closed");
            ModuleTestKit.setPolkitRequest(true, { actionId: "org.freedesktop.policykit.exec", message: "Authentication is needed to run `/usr/bin/true' as the super user" });
            assert(!ModuleTestKit.polkitRequestOpen, "… and one that opens while locked too");
        });
        _then("the waiting ones are answered", () => _done("waiting 1", "waiting 2"), () => {
            for (const name of ["waiting 1", "waiting 2"]) {
                const result = _runs[name].result;
                assert(result.dismissed && result.blocked === "locked" && !result.cancelled && !result.ok && _runs[name].lines.length === 0,
                       name + ": dismissed, blocked locked, never ran: " + JSON.stringify(result));
            }
            assert(_runs.going.handle.running, "the run already going ends as its pkexec answers (here: a stand-in that does not ask)");
            assertEqual(ModuleTestKit.notified.length, 0, "quietly: nothing notified");
            ModuleTestKit.setSessionLocked(false);
            _cancel("going");
        });
        _then("everything is answered", () => _done("going") && _idle(), () => {});
    }
}
