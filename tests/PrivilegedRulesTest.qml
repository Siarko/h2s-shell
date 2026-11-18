import QtQuick
import qs.singletons

// Running as administrator, the decisions (singletons/PrivilegedRules.qml): text that cannot
// be shown, the options, every refusal before pkexec runs, the words handed to pkexec (the
// shell's `timeout` inside it), where pkexec is, the answer, and the queue's life.
TestCase {
    suiteName: "PrivilegedRules"

    function run() {
        const rules = PrivilegedRules;

        // --- text ---
        for (const text of ["a\nb", "tab\there", "‮evil", "zero​width", "soft­hyphen", "nul\u0000",
                            "tag󠀁", "lone \ud800 surrogate", "\u0085next line", "bom﻿",
                            "line\u2028separator", "paragraph\u2029separator"])
            assert(rules.unprintable(text), "unprintable: " + JSON.stringify(text));
        for (const text of ["", "plain words", "café", "日本語", "emoji 😀", "--flag=value", "a b"])
            assert(!rules.unprintable(text), "printable: " + JSON.stringify(text));
        assertEqual(rules.cleanWhat("  Send\n a\tfile ‮ "), "Send a file", "what: white space folded, a format character dropped, trimmed");
        assertEqual(rules.cleanWhat("​‮ \n"), "", "what: nothing left");
        assertEqual(rules.cleanWhat(42) + rules.cleanWhat(null) + rules.cleanWhat(undefined), "", "what: not a string → \"\"");
        assertEqual(rules.cleanWhat("x".repeat(500)).length, rules.whatMaxLength, "what: capped");
        assertEqual(rules.cleanWhat("Send\u2028a\u2029file"), "Send a file", "what: line and paragraph separators are white space, folded");

        // --- the options ---
        const good = { what: "Connect", timeoutMs: 30000 };
        assertEqual(JSON.stringify(rules.options(good)), JSON.stringify({ problem: "", what: "Connect", timeoutMs: 30000, notifyFailures: true,
                                                                        callbacks: { onStdout: null, onStderr: null, onLine: null, done: null } }),
                    "options: what and timeoutMs, notifyFailures true by default");
        for (const given of [undefined, null, "x", [1]])
            assert(rules.options(given).problem !== "", "options: not an object (" + JSON.stringify(given) + ") → a problem");
        for (const limit of [undefined, 999, 3600001, NaN, Infinity, "30000"])
            assert(rules.options({ what: "x", timeoutMs: limit }).problem.startsWith("timeoutMs"), "timeoutMs " + String(limit) + " → a problem");
        assertEqual(rules.options({ what: "x", timeoutMs: 1000 }).timeoutMs + rules.options({ what: "x", timeoutMs: 3600000 }).timeoutMs, 3601000,
                    "timeoutMs: 1 s and 1 h are the ends of the range");
        assert(rules.options({ what: "x", timeoutMs: 1000, notifyFailures: "yes" }).problem.startsWith("notifyFailures"), "notifyFailures not a bool → a problem");
        assert(rules.options({ what: "x", timeoutMs: 1000, done: "no" }).problem.startsWith("done"), "done not a function → a problem");
        assertEqual(rules.options({ what: "x", timeoutMs: 1000, notifyFailures: false }).notifyFailures, false, "notifyFailures false");
        // Each option read once: a getter cannot pass the check and then hand over another value
        const reads = {};
        const counted = {};
        const answers = { what: "Connect", timeoutMs: 2000, notifyFailures: false, onStdout: () => {}, onStderr: () => {}, onLine: () => {}, done: () => {} };
        for (const name of Object.keys(answers)) {
            reads[name] = 0;
            Object.defineProperty(counted, name, { get() { return ++reads[name] === 1 ? answers[name] : "switched"; }, enumerable: true });
        }
        const once = rules.options(counted);
        assert(Object.keys(reads).every(name => reads[name] === 1), "options: every field read once: " + JSON.stringify(reads));
        assert(once.problem === "" && once.what === "Connect" && once.timeoutMs === 2000 && once.notifyFailures === false
               && once.callbacks.done === answers.done && once.callbacks.onLine === answers.onLine, "… and what was read is what is kept");
        assert(rules.options({ what: "x", done: answers.done }).callbacks.done === answers.done && rules.options({ what: "x", onLine: answers.onLine }).callbacks.onLine === null,
               "options wrong: done kept (an answer is owed), the others not");

        // --- refusals before pkexec runs ---
        const base = { argv: ["/usr/bin/tailscale", "up"], options: rules.options(good), active: true, locked: false,
                       available: true, unavailableReason: "" };
        const asked = changes => rules.refusal(Object.assign({}, base, changes));
        assertEqual(asked({}), null, "everything right: no refusal");
        assert(asked({ options: rules.options({ what: "x" }) }).error.startsWith("timeoutMs") && asked({ options: rules.options({ what: "x" }) }).blocked === "",
               "bad options: error, not blocked");
        assert(asked({ argv: "not a list" }).error !== "" && !asked({ argv: "not a list" }).notFound, "argv not a list: error");
        assert(asked({ argv: [] }).error !== "", "argv empty: error");
        const missing = asked({ argv: ["", "up"] });
        assert(missing.notFound && missing.blocked === "" && missing.error.includes("not found"),
               "argv[0] \"\" (the path of a program not found): notFound: " + JSON.stringify(missing));
        assertEqual(asked({ active: false }).error, "the module is off", "module off: error");
        assertEqual(asked({ locked: true }).blocked, "locked", "locked: blocked locked");
        assertEqual(asked({ options: rules.options({ what: " ‮\n", timeoutMs: 1000 }) }).blocked, "no-purpose", "what empty after cleaning: no-purpose");
        assertEqual(asked({ options: rules.options({ timeoutMs: 1000 }) }).blocked, "no-purpose", "no what at all: no-purpose");
        assertEqual(asked({ argv: ["/usr/bin/tailscale", "file", "a\nb"] }).blocked, "unprintable", "a newline in a word: unprintable");
        const rtl = asked({ argv: ["/usr/bin/tailscale", "cp", "report‮fdp.exe"] });
        assert(rtl.blocked === "unprintable" && rtl.error.startsWith("word 3"), "U+202E in a word: unprintable, which word said: " + JSON.stringify(rtl));
        assertEqual(asked({ available: false, unavailableReason: "no pkexec found" }).error, "no pkexec found", "not available: error, the reason");
        assertEqual(asked({ available: false, unavailableReason: "x" }).blocked, "", "… not blocked");
        const relative = asked({ argv: ["tailscale", "up"] });
        assert(relative.notFound && relative.blocked === "" && relative.error.includes("absolute"),
               "argv[0] not absolute (root's PATH is never searched): notFound: " + JSON.stringify(relative));
        // The command is not parsed: whatever argv[0] is, an absolute path passes
        for (const argv of [["/bin/sh", "-c", "id"], ["/usr/bin/env", "tailscale"], ["/usr/bin/python3", "-c", "x"],
                            ["/usr/bin/timeout", "5", "/bin/sh"], ["/nix/store/abc-coreutils-9.5/bin/coreutils", "--coreutils-prog=env", "/bin/sh"],
                            ["/home/u/.local/bin/tool"]])
            assertEqual(asked({ argv: argv }), null, "an absolute argv[0] passes, whatever it is: " + argv[0]);
        // The order
        assertEqual(asked({ locked: true, options: rules.options({ timeoutMs: 1000 }) }).blocked, "locked", "locked before no-purpose");
        assertEqual(asked({ active: false, locked: true }).error, "the module is off", "module off before locked");
        assertEqual(asked({ options: rules.options({ timeoutMs: 1000 }), argv: ["/usr/bin/tailscale", "a\nb"] }).blocked, "no-purpose",
                    "no-purpose before unprintable");
        assertEqual(asked({ argv: ["/usr/bin/tailscale", "a\nb"], available: false }).blocked, "unprintable", "unprintable before availability");
        assert(asked({ argv: ["relative"], active: false }).notFound, "a relative argv[0] (notFound) before the module off");
        assertEqual(rules.refusedResult(asked({ locked: true })).dismissed, true, "a run refused for the lock is dismissed too");
        assertEqual(rules.refusedResult(asked({ options: rules.options({ timeoutMs: 1000 }) })).dismissed, false, "… other refusals are not");

        // --- the words handed to pkexec ---
        assertEqual(JSON.stringify(rules.pkexecArgv("/run/wrappers/bin/pkexec", "/usr/bin/timeout", 30000, 3000, ["/usr/bin/tailscale", "file", "cp", "--", "-x"])),
                    JSON.stringify(["/run/wrappers/bin/pkexec", "/usr/bin/timeout", "-k", "3", "30", "/usr/bin/tailscale", "file", "cp", "--", "-x"]),
                    "pkexec, then the shell's timeout with its kill-after and the limit, then the command as given");
        assertEqual(rules.pkexecArgv("/p", "/t", 2500, 0, ["/c"]).slice(2, 5).join(" "), "-k 0.001 2.5", "seconds with decimals; a kill-after of 0 is 1 ms");

        // --- the old PrivilegedAction: its default "pkexec" is the shell's trusted one ---
        assert(rules.legacySystemPkexec(["pkexec"], false), "\"pkexec\" by name outside test mode: the trusted pkexec");
        assert(rules.legacySystemPkexec(["pkexec", "--disable-internal-agent"], false), "… with words of its own too");
        assert(!rules.legacySystemPkexec(["pkexec"], true), "test mode: left to the test-mode gate");
        assert(!rules.legacySystemPkexec(["/usr/bin/pkexec"], false) && !rules.legacySystemPkexec(["/opt/x/elevate"], false),
               "an elevating program given by its path: as given");
        const legacyArgv = ["pkexec", "/usr/bin/tailscale", "up"];
        assertEqual(JSON.stringify(rules.legacyLaunch(legacyArgv, true, true, "/run/wrappers/bin/pkexec", "")),
                    JSON.stringify({ argv: ["/run/wrappers/bin/pkexec", "/usr/bin/tailscale", "up"], wait: false, problem: "" }),
                    "the trusted pkexec in place of the name, the command after it");
        assertEqual(rules.legacyLaunch(legacyArgv, true, false, "", "").wait, true, "the look-up not answered yet: wait for it");
        const unavailable = rules.legacyLaunch(legacyArgv, true, true, "", "pkexec is not installed");
        assert(unavailable.problem.includes("not available") && unavailable.problem.includes("not installed") && unavailable.argv.length === 0,
               "no trusted pkexec: the run fails as not available, nothing run: " + JSON.stringify(unavailable));
        assertEqual(JSON.stringify(rules.legacyLaunch(["/opt/x/elevate", "/bin/true"], false, false, "", "").argv), JSON.stringify(["/opt/x/elevate", "/bin/true"]),
                    "an elevating program given by its path: run as given, no look-up waited for");

        // --- where pkexec is ---
        const root = path => "stat\tpkexec\t0\t755\t0\t" + path;
        const wrapper = ["user\t1000\t1000 998", "cand\tpkexec\t/run/wrappers/bin/pkexec", root("/"), root("/run"), root("/run/wrappers"),
                         root("/run/wrappers/bin"), "stat\tpkexec\t0\t4511\t0\t/run/wrappers/bin/pkexec"];
        assertEqual(JSON.stringify(rules.pkexecChoice(wrapper)), JSON.stringify({ path: "/run/wrappers/bin/pkexec", reason: "" }),
                    "NixOS: the setuid wrapper, root's");
        const storeFirst = ["user\t1000\t1000", "cand\tpkexec\t/usr/bin/pkexec", root("/"), root("/usr"), root("/usr/bin"), root("/usr/bin/pkexec"),
                            "cand\tpkexec\t/bin/pkexec", root("/"), root("/bin"), "stat\tpkexec\t0\t4755\t0\t/bin/pkexec"];
        assertEqual(rules.pkexecChoice(storeFirst).path, "/bin/pkexec", "a trusted copy that is not setuid is passed over for the setuid one after it");
        assert(rules.pkexecChoice(storeFirst.slice(0, 6)).reason.includes("not setuid"), "only a copy that is not setuid: none, and why");
        const userOwned = ["user\t1000\t1000", "cand\tpkexec\t/usr/bin/pkexec", root("/"), root("/usr"), root("/usr/bin"),
                           "stat\tpkexec\t1000\t4755\t1000\t/usr/bin/pkexec"];
        assertEqual(rules.pkexecChoice(userOwned).path, "", "setuid but the user's file: none");
        assertEqual(rules.pkexecChoice(["user\t1000\t1000", "cand\tpkexec\t"]).reason, "pkexec is not installed", "not found: not installed");
        assertEqual(rules.pkexecChoice([]).reason, "the look-up for pkexec did not answer", "no answer: said so");

        // --- available ---
        const facts = { testMode: false, standIn: "", pkexecKnown: true, pkexec: "/usr/bin/pkexec", pkexecReason: "",
                        timeoutKnown: true, timeout: "/usr/bin/timeout" };
        const availability = changes => rules.availability(Object.assign({}, facts, changes));
        assertEqual(JSON.stringify(availability({})), JSON.stringify({ available: true, reason: "", pkexec: "/usr/bin/pkexec", timeout: "/usr/bin/timeout" }),
                    "both found: available");
        assert(!availability({ pkexecKnown: false }).available, "pkexec still looked for: not yet");
        assertEqual(availability({ pkexec: "", pkexecReason: "pkexec is not installed" }).reason, "pkexec is not installed", "no pkexec: the reason");
        assert(!availability({ timeout: "" }).available && availability({ timeout: "" }).reason.includes("timeout"), "no trusted timeout: not available");
        assert(!availability({ timeoutKnown: false }).available, "timeout still looked for: not yet");
        assertEqual(availability({ testMode: true, standIn: "/m/tests/programs/pkexec" }).pkexec, "/m/tests/programs/pkexec",
                    "test mode: the module's stand-in");
        const noStandIn = availability({ testMode: true, standIn: "" });
        assert(!noStandIn.available && noStandIn.reason.startsWith("test mode:"), "test mode without a stand-in: not available — never the system's pkexec");
        assert(rules.shellAnswers("active") && rules.shellAnswers("conflict") && !rules.shellAnswers("other") && !rules.shellAnswers("none")
               && !rules.shellAnswers("blocked") && !rules.shellAnswers("deciding"), "the shell's prompt answers in active and conflict only");

        // --- the answer ---
        const ran = (code, more) => rules.runResult(Object.assign({ ok: code === 0, code: code, stdout: "out", stderr: "", cancelled: false,
                                                                   failedToStart: false, durationMs: 100, error: "" }, more ?? {}), 30000);
        assert(ran(0).ok && Object.isFrozen(ran(0)) && ran(0).stdout === "out" && ran(0).blocked === "", "exit 0: ok, frozen, the output");
        assert(ran(126).dismissed && !ran(126).ok, "126: dismissed");
        assert(ran(127).refused && !ran(127).dismissed, "127: refused");
        assert(ran(124, { durationMs: 30000 }).timedOut && ran(137, { durationMs: 31000 }).timedOut, "124 or 137 after the limit: timedOut");
        assert(!ran(124, { durationMs: 500 }).timedOut, "124 before the limit: the command's own status");
        assert(!ran(126, { cancelled: true, code: 126 }).dismissed && ran(-1, { cancelled: true }).cancelled, "cancelled: nothing else");
        assertEqual(ran(-1, { failedToStart: true }).error, "pkexec could not be started", "pkexec not started: said so");
        assertEqual(rules.failureNotice(ran(127), "Connect", 30000, true), null, "refused: no failure notice (the agent tells it)");
        assertEqual(rules.failureNotice(ran(126), "Connect", 30000, true), null, "dismissed: none");
        assertEqual(rules.failureNotice(ran(0), "Connect", 30000, true), null, "ok: none");
        assertEqual(rules.failureNotice(rules.lockedResult(), "Connect", 30000, true), null, "locked: none");
        assertEqual(rules.failureNotice(rules.cancelledResult(), "Connect", 30000, true), null, "cancelled: none");
        assertEqual(JSON.stringify(rules.failureNotice(ran(1, { stderr: "first\nError: no route\n" }), "Connect", 30000, true)),
                    JSON.stringify({ summary: "Connect failed", body: "Error: no route" }), "a failure: its last stderr line");
        assertEqual(rules.failureNotice(ran(3), "Connect", 30000, true).body, "Exit code 3", "… or its exit code");
        assertEqual(rules.failureNotice(ran(124, { durationMs: 30000 }), "Connect", 30000, true).body, "It did not end within 30 s", "timed out: said so");
        assert(rules.failureNotice(rules.notFoundResult("/usr/bin/x"), "Connect", 30000, true).body.includes("/usr/bin/x"), "not found: the program named");
        assertEqual(rules.failureNotice(rules.refusedResult({ blocked: "", error: "timeoutMs is needed" }), "Connect", 30000, false), null,
                    "refused before the queue, asked wrongly: no notification (the result says it)");
        assert(rules.failureNotice(rules.refusedResult({ blocked: "", notFound: true, error: "the program was not found" }), "Connect", 30000, false) !== null,
               "… but a program not found is told");

        // --- the queue ---
        const step = (state, event) => rules.queueStep(state, event);
        const kinds = stepped => stepped.effects.map(effect => effect.type + ":" + effect.id + (effect.kind ? ":" + effect.kind : "")).join(" ");
        const phases = state => state.jobs.map(job => job.id + "=" + job.phase).join(" ");
        let queue = rules.queueStart(false);
        let stepped = step(queue, { type: "add", id: 1, owner: "m1", now: 0 });
        assertEqual(kinds(stepped), "check:1", "queue: the first run is looked at at once");
        stepped = step(stepped.state, { type: "add", id: 2, owner: "m1", now: 0 });
        assertEqual(kinds(stepped) + " | " + phases(stepped.state), " | 1=checking 2=waiting", "… a second one waits");
        stepped = step(stepped.state, { type: "checked", id: 1, found: true, shellAgent: true, now: 100 });
        assertEqual(kinds(stepped) + " | " + rules.nextDeadline(stepped.state), "launch:1 | 2100", "found: pkexec started, the head held for 2 s");
        const asking = stepped.state;
        assertEqual(kinds(step(asking, { type: "tick", now: 2099 })), "", "before 2 s: still held");
        stepped = step(asking, { type: "tick", now: 2100 });
        assertEqual(kinds(stepped) + " | " + phases(stepped.state), "check:2 | 1=running 2=checking", "2 s with no request: released, the next looked at");
        // A request seen
        stepped = step(asking, { type: "request", own: true, now: 500 });
        assertEqual(rules.nextDeadline(stepped.state), 0, "a request opens: held while it is open, no deadline");
        assertEqual(kinds(step(stepped.state, { type: "tick", now: 60000 })), "", "… a minute later still held");
        stepped = step(stepped.state, { type: "request", own: false, now: 61000 });
        assertEqual(kinds(stepped) + " | " + phases(stepped.state), "check:2 | 1=running 2=checking", "the request ended: released");
        assertEqual(kinds(step(asking, { type: "request", own: false, now: 500 })), "", "a request ending that was never seen opening: nothing");
        // The run ends while it holds the head
        stepped = step(asking, { type: "exited", id: 1, now: 300 });
        assertEqual(kinds(stepped) + " | " + phases(stepped.state), "answer:1:result check:2 | 2=checking", "exited: answered, the next looked at");
        // Another agent: strict
        const strict = step(step(step(rules.queueStart(false), { type: "add", id: 1, owner: "m", now: 0 }).state,
                                 { type: "add", id: 2, owner: "m", now: 0 }).state,
                            { type: "checked", id: 1, found: true, shellAgent: false, now: 0 }).state;
        assertEqual(rules.nextDeadline(strict), rules.headStrictMs, "another agent: held up to 2 minutes");
        assertEqual(kinds(step(strict, { type: "request", own: true, now: 10 })) + kinds(step(strict, { type: "tick", now: 2000 })), "",
                    "… requests are not looked at, 2 s mean nothing");
        assertEqual(kinds(step(strict, { type: "tick", now: rules.headStrictMs })), "check:2", "… released after 2 minutes");
        assertEqual(kinds(step(strict, { type: "exited", id: 1, now: 5000 })), "answer:1:result check:2", "… or when it ends");
        // Not found
        const checking = step(rules.queueStart(false), { type: "add", id: 1, owner: "m", now: 0 }).state;
        assertEqual(kinds(step(step(checking, { type: "add", id: 2, owner: "m", now: 0 }).state, { type: "checked", id: 1, found: false, now: 1 })),
                    "answer:1:notFound check:2", "its program not there: notFound, pkexec never started, the next looked at");
        // Cancels
        assertEqual(kinds(step(asking, { type: "cancel", id: 2, now: 200 })), "answer:2:cancelled", "cancel while waiting: answered at once, nothing signalled");
        assertEqual(kinds(step(checking, { type: "cancel", id: 1, now: 1 })), "answer:1:cancelled", "cancel while its program is looked at: the same");
        stepped = step(asking, { type: "cancel", id: 1, killAfterMs: 3000, now: 1000 });
        assertEqual(kinds(stepped) + " | " + phases(stepped.state), "signal:1 | 1=ending 2=waiting",
                    "cancel after start: signalled, not answered yet, the next still waits");
        const cancelled = stepped.state;
        assertEqual(kinds(step(cancelled, { type: "tick", now: 2100 })), "", "… the 2 s mean nothing now: it holds the head until it is gone");
        assertEqual(kinds(step(cancelled, { type: "exited", id: 1, now: 1500 })), "answer:1:cancelled check:2", "… its exit: answered cancelled, the next starts");
        stepped = step(cancelled, { type: "tick", now: 4000 });
        assertEqual(kinds(stepped), "answer:1:cancelled check:2", "… or killAfterMs later without an exit (run as root, it cannot be signalled)");
        assertEqual(kinds(step(stepped.state, { type: "exited", id: 1, now: 9000 })), "", "… its late exit is not answered again");
        assertEqual(kinds(step(cancelled, { type: "cancel", id: 1, now: 1100 })), "", "cancel twice: once");
        const released = step(asking, { type: "tick", now: 2100 }).state;
        stepped = step(released, { type: "cancel", id: 1, killAfterMs: 3000, now: 2200 });
        assertEqual(kinds(stepped) + " | " + phases(stepped.state), "signal:1 | 1=ending 2=checking", "cancel of a run that let the head go: the next goes on");
        // A module turned off
        let off = step(rules.queueStart(false), { type: "add", id: 1, owner: "m1", now: 0 }).state;
        off = step(off, { type: "add", id: 2, owner: "m1", now: 0 }).state;
        off = step(off, { type: "add", id: 3, owner: "m2", now: 0 }).state;
        off = step(off, { type: "checked", id: 1, found: true, shellAgent: true, now: 0 }).state;
        stepped = step(off, { type: "ownerGone", owner: "m1", killAfterMs: 3000, now: 100 });
        assertEqual(kinds(stepped) + " | " + phases(stepped.state), "signal:1 forget:2 | 1=ending 3=waiting",
                    "module off: its waiting run forgotten, its started one cancelled; another module's waits for the cancelled one");
        assertEqual(kinds(step(stepped.state, { type: "exited", id: 1, now: 500 })), "forget:1 check:3", "… the cancelled one ends with no answer, the next starts");
        assertEqual(kinds(step(stepped.state, { type: "tick", now: 3100 })), "forget:1 check:3", "… or killAfterMs later");
        assertEqual(kinds(step(off, { type: "ownerGone", owner: "", now: 0 })), "", "an empty owner touches nothing");
        // The lock
        let lockQueue = step(rules.queueStart(false), { type: "add", id: 1, owner: "m", now: 0 }).state;
        lockQueue = step(lockQueue, { type: "checked", id: 1, found: true, shellAgent: true, now: 0 }).state;
        lockQueue = step(lockQueue, { type: "tick", now: 2000 }).state;
        lockQueue = step(lockQueue, { type: "add", id: 2, owner: "m", now: 2000 }).state;
        lockQueue = step(lockQueue, { type: "add", id: 3, owner: "n", now: 2000 }).state;
        assertEqual(phases(lockQueue), "1=running 2=checking 3=waiting", "lock: a run going, one looked at, one waiting");
        stepped = step(lockQueue, { type: "lock", locked: true, now: 2100 });
        assertEqual(kinds(stepped) + " | " + phases(stepped.state), "answer:2:locked answer:3:locked | 1=running",
                    "locked: the waiting runs answered locked; the started one goes on");
        assertEqual(kinds(step(stepped.state, { type: "add", id: 4, owner: "m", now: 2200 })), "answer:4:locked", "… a run asked for while locked: answered locked");
        const askingLocked = step(asking, { type: "lock", locked: true, now: 200 });
        assertEqual(kinds(askingLocked) + " | " + phases(askingLocked.state), "answer:2:locked | 1=asking", "… a run already asking is left to its prompt");
        assertEqual(kinds(step(askingLocked.state, { type: "tick", now: 2100 })), "", "… and nothing starts while locked");
        const unlocked = step(step(askingLocked.state, { type: "add", id: 5, owner: "m", now: 300 }).state, { type: "lock", locked: false, now: 400 });
        assertEqual(kinds(unlocked), "", "unlocked: nothing was kept to start");
        // Odd events
        assertEqual(kinds(step(asking, { type: "exited", id: 99, now: 0 })) + kinds(step(asking, { type: "checked", id: 2, found: true, now: 0 }))
                    + kinds(step(asking, { type: "add", id: 1, now: 0 })) + kinds(step(asking, { type: "nonsense", now: 0 })), "",
                    "an unknown run, a run not being looked at, an id queued twice, an unknown event: nothing");
    }
}
