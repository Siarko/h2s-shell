import QtQuick
import qs.singletons

// The command runner's decisions (singletons/CommandRules.qml): what may be run, the
// command line with `timeout` and `setpriv`, a run's life, the output's cuts, the answer
TestCase {
    suiteName: "CommandRules"

    function _types(effects) {
        return effects.map(effect => effect.type + (effect.name ? ":" + effect.name : "") + (effect.signal ? ":" + effect.signal : "")
                                     + (effect.ms !== undefined ? ":" + effect.ms : "")).join(" ");
    }

    // A state after the events, each of which must be taken
    function _after(state, events) {
        for (const event of events) {
            const stepped = CommandRules.step(state, event);
            if (stepped.ignored !== "")
                fail("event " + event.type + " ignored: " + stepped.ignored);
            state = stepped.state;
        }
        return state;
    }

    // A QML list, which is no array
    property list<string> qmlWords: ["ls", "-l"]

    function run() {
        const rules = CommandRules;

        // --- what may be run ---
        assertEqual(rules.argvProblem(["ls", "-l", ""]), "", "a list of strings, an empty word among them");
        assert(rules.argvProblem([]) !== "", "an empty list: refused");
        assert(rules.argvProblem("ls -l") !== "", "a string, not a list: refused");
        assert(rules.argvProblem(null) !== "" && rules.argvProblem(undefined) !== "" && rules.argvProblem(7) !== "", "nothing, a number: refused");
        assert(rules.argvProblem(["ls", 3]) !== "", "a word that is a number: refused");
        assert(rules.argvProblem([""]) !== "", "an empty program: refused");
        assert(rules.argvProblem(["echo", "a\u0000b"]) !== "", "a NUL in a word: refused");

        // --- the command read once (argvSnapshot) ---
        const copied = rules.argvSnapshot(["ls", "-l"], true);
        assertEqual(JSON.stringify(copied), JSON.stringify({ argv: ["ls", "-l"], words: ["ls", "-l"], problem: "" }), "an array of strings: copied");
        const original = ["ls"];
        assert(rules.argvSnapshot(original, true).argv !== original, "… a fresh array, not the one given");
        // An element that answers one thing to the checks and another later
        let reads = 0;
        const switching = ["/usr/bin/true", "x"];
        Object.defineProperty(switching, 0, { get() { reads++; return reads === 1 ? "/usr/bin/true" : "/bin/sh"; }, enumerable: true });
        const once = rules.argvSnapshot(switching, true);
        assertEqual(JSON.stringify(once.argv) + " " + reads, "[\"/usr/bin/true\",\"x\"] 1", "an accessor element: read once, the copy keeps what it said");
        // A Proxy whose length and words change at each read
        const asked = { length: 0, word: 0 };
        const proxy = new Proxy(["/usr/bin/true", "a", "b"], {
            get(target, key) {
                if (key === "length")
                    return ++asked.length === 1 ? 1 : 3;
                if (key === "0")
                    return ++asked.word === 1 ? "/usr/bin/true" : "/bin/sh";
                return target[key];
            }
        });
        const proxied = rules.argvSnapshot(proxy, true);
        assertEqual(JSON.stringify(proxied.argv) + " " + asked.length + " " + asked.word, "[\"/usr/bin/true\"] 1 1",
                    "a Proxy: length and each word read once");
        assert(rules.argvSnapshot({ 0: "ls", length: 1 }, true).problem !== "", "arrays only: an array-like object refused");
        assertEqual(rules.argvSnapshot({ 0: "ls", length: 1 }, false).argv?.[0], "ls", "list-like allowed: copied (a QML list<string> is no array)");
        assertEqual(JSON.stringify(rules.argvSnapshot(qmlWords, false).argv) + " " + rules.argvSnapshot(qmlWords, true).argv,
                    "[\"ls\",\"-l\"] null", "a QML list<string>: copied where list-likes are allowed, refused where only arrays are");
        assert(rules.argvSnapshot([new String("ls")], true).problem.startsWith("word 1"), "a String object, not a primitive string: refused");
        assert(rules.argvSnapshot({ length: 1e12 }, false).problem.includes("words"), "a huge length: refused, not walked");
        assert(rules.argvSnapshot({ length: 1.5 }, false).problem !== "", "a length that is no whole number: refused");
        const throwing = ["ls"];
        Object.defineProperty(throwing, 0, { get() { throw new Error("no"); } });
        assertEqual(rules.argvSnapshot(throwing, true).problem + " " + rules.argvSnapshot(throwing, true).words, "the command could not be read null",
                    "a read that throws: refused, no copy");
        const emptyProgram = rules.argvSnapshot(["", "up"], true);
        assertEqual(String(emptyProgram.argv) + " " + JSON.stringify(emptyProgram.words), "null [\"\",\"up\"]", "a problem with the words: no argv, the copy in words");
        // Options: each field read once
        const optionReads = {};
        const counted = {};
        for (const name of ["timeoutMs", "killAfterMs", "maxOutputBytes", "keepOutput", "outputAfterCancel", "environment", "onStdout", "onStderr", "onLine", "done"]) {
            optionReads[name] = 0;
            Object.defineProperty(counted, name, { get() { optionReads[name]++; return undefined; }, enumerable: true });
        }
        rules.options(counted);
        assert(Object.keys(optionReads).every(name => optionReads[name] === 1), "options: every field read once: " + JSON.stringify(optionReads));
        let envReads = 0;
        const environment = {};
        Object.defineProperty(environment, "A", { get() { return ++envReads === 1 ? "1" : 5; }, enumerable: true });
        const withEnvironment = rules.options({ environment: environment });
        assertEqual(withEnvironment.problem + "|" + JSON.stringify(withEnvironment.environment), "|{\"A\":\"1\"}",
                    "an environment value read once: the copy checked is the one kept");
        const done = () => {};
        assert(rules.options({ done: done, onLine: 5 }).callbacks.done === done && rules.options({ done: done, onLine: 5 }).callbacks.onLine === null,
               "callbacks as read: done even when the options are wrong, the others not");

        // --- the options ---
        const defaults = rules.options(undefined);
        assertEqual(JSON.stringify(defaults), JSON.stringify({ problem: "", timeoutMs: 30000, killAfterMs: 3000, keepOutput: true, outputAfterCancel: false, maxOutputBytes: 1048576, environment: {},
                                                       callbacks: { onStdout: null, onStderr: null, onLine: null, done: null } }),
                    "none given: 30 s, KILL 3 s after, the output kept, none after a cancel, 1 MiB");
        assertEqual(rules.options({ outputAfterCancel: true }).outputAfterCancel + " " + rules.options({ outputAfterCancel: false }).outputAfterCancel, "true false",
                    "outputAfterCancel taken as given");
        assert(rules.options({ outputAfterCancel: 1 }).problem !== "", "outputAfterCancel not true or false: a problem");
        assertEqual(JSON.stringify(rules.options(null)), JSON.stringify(defaults), "null: the same");
        const given = rules.options({ timeoutMs: 0, killAfterMs: 250.4, keepOutput: false, maxOutputBytes: 10, environment: { A: "1", B: null }, done: () => {} });
        assertEqual(given.problem + "|" + given.timeoutMs + "|" + given.killAfterMs + "|" + given.keepOutput + "|" + given.maxOutputBytes + "|" + JSON.stringify(given.environment),
                    "|0|250|false|10|{\"A\":\"1\",\"B\":null}", "given ones taken, 0 as no limit");
        assert(rules.options({ timeoutMs: -1 }).problem !== "", "a negative limit: a problem, not the default");
        assert(rules.options({ timeoutMs: "30" }).problem !== "", "a limit as text: a problem");
        assert(rules.options({ timeoutMs: Infinity }).problem !== "", "an endless limit is written 0");
        assert(rules.options({ killAfterMs: NaN }).problem !== "", "killAfterMs not a number: a problem");
        assert(rules.options({ maxOutputBytes: -5 }).problem !== "", "a negative cap: a problem");
        assert(rules.options({ keepOutput: "no" }).problem !== "", "keepOutput as text: a problem");
        assert(rules.options({ done: "callback" }).problem !== "", "a callback that is no function: a problem");
        assert(rules.options({ onLine: 5 }).problem !== "", "… any of them");
        assert(rules.options("fast").problem !== "" && rules.options([]).problem !== "", "options that are no object: a problem");
        assert(rules.options({ environment: { A: 1 } }).problem !== "", "an environment value that is a number: a problem");
        assert(rules.options({ environment: { "A=B": "x" } }).problem !== "", "an environment name with '=': a problem");
        assert(rules.options({ environment: ["A=1"] }).problem !== "", "an environment as a list: a problem");
        assertEqual(JSON.stringify(rules.mergedEnvironment({ A: "runner", B: "runner" }, { B: "run", C: "run" })),
                    "{\"A\":\"runner\",\"B\":\"run\",\"C\":\"run\"}", "the runner's environment, the run's on top");
        assertEqual(JSON.stringify(rules.mergedEnvironment("PATH=/x", { C: "run" })), "{\"C\":\"run\"}", "a runner's environment that is none: left out");

        // --- the command line ---
        assertEqual(rules.seconds(30000) + " " + rules.seconds(800) + " " + rules.seconds(1) + " " + rules.seconds(3600000), "30 0.8 0.001 3600",
                    "durations in seconds, as `timeout` reads them");
        const tools = { timeout: "/usr/bin/timeout", setpriv: "/usr/bin/setpriv" };
        assertEqual(JSON.stringify(rules.commandLine(["tailscale", "file", "cp", "--", "a b"], tools, 30000, 3000)),
                    JSON.stringify(["/usr/bin/timeout", "-k", "3", "30", "/usr/bin/setpriv", "--pdeathsig", "KILL", "--", "tailscale", "file", "cp", "--", "a b"]),
                    "with a limit: inside timeout -k, which the command dies with (setpriv --pdeathsig), the words untouched");
        assertEqual(JSON.stringify(rules.commandLine(["-n", "x"], tools, 500, 0).slice(0, 4)),
                    JSON.stringify(["/usr/bin/timeout", "-k", "0.001", "0.5"]), "a kill-after of 0 would switch timeout's KILL off: 1 ms");
        assertEqual(JSON.stringify(rules.commandLine(["ls", "--", "-l"], tools, 0, 3000)), JSON.stringify(["/usr/bin/setpriv", "--pdeathsig", "KILL", "--", "ls", "--", "-l"]),
                    "no limit: behind setpriv alone, which the shell is then the parent of — the command dies with the shell");
        assertEqual(JSON.stringify(rules.commandLine(["ls"], { timeout: "", setpriv: "/usr/bin/setpriv" }, 30000, 3000)), JSON.stringify(["/usr/bin/setpriv", "--pdeathsig", "KILL", "--", "ls"]),
                    "a limit but no timeout found: behind setpriv alone, the watchdog keeps the limit");
        assertEqual(JSON.stringify(rules.commandLine(["ls"], { timeout: "/usr/bin/timeout", setpriv: "" }, 0, 3000)), "[\"ls\"]", "no limit, no setpriv found: the command as it is");
        assertEqual(JSON.stringify(rules.commandLine(["ls"], { timeout: "/usr/bin/timeout", setpriv: "" }, 30000, 3000)), "[\"ls\"]",
                    "no setpriv found: the command as it is — never inside a timeout it would outlive");
        assert(!rules.wraps(undefined, 30000) && !rules.wraps({}, 30000) && !rules.wraps({ timeout: "/usr/bin/timeout" }, 30000)
               && !rules.wraps(tools, 0) && rules.wraps(tools, 1), "wrapped: a limit and both programs");
        assert(rules.guards(tools) && rules.guards({ setpriv: "/usr/bin/setpriv" }) && !rules.guards({ timeout: "/usr/bin/timeout", setpriv: "" }) && !rules.guards(undefined),
               "guarded (setpriv in front): whenever setpriv was found");
        assertEqual(rules.wrapperTools.map(tool => tool.name).join(), "timeout,setpriv", "the two programs looked for");
        assert(rules.wrapperTools.every(tool => tool.probe.length > 0 && tool.candidates === undefined),
               "… each with a probe, and no directory of its own: found on PATH and judged (ModuleRules.programVerdict)");

        // --- a run's life ---
        const waiting = rules.fresh(1000, 300);
        let stepped = rules.step(waiting, { type: "launch", wrapped: true });
        assertEqual(stepped.state.phase + " " + _types(stepped.effects), "running start timer:watchdog:2300", "launched inside timeout: started, the watchdog after the limit, timeout's KILL and a margin");
        assert(waiting.phase === "waiting", "a step leaves the state it was given alone");
        const wrapped = stepped.state;
        stepped = rules.step(waiting, { type: "launch", wrapped: false });
        assertEqual(stepped.state.wrapped + " " + _types(stepped.effects), "false start timer:watchdog:1000", "launched bare: the watchdog at the limit");
        const bare = stepped.state;
        assertEqual(String(stepped.state.guarded), "false", "… not guarded where the launch says so");
        stepped = rules.step(rules.fresh(0, 300), { type: "launch", wrapped: true, guarded: true });
        assertEqual(stepped.state.wrapped + " " + stepped.state.guarded + " " + _types(stepped.effects), "false true start", "no limit: never wrapped, no watchdog; guarded when setpriv is in front");
        const unlimited = stepped.state;
        assertEqual(String(rules.step(waiting, { type: "launch", wrapped: true }).state.guarded), "true", "wrapped: guarded too");
        assert(rules.step(wrapped, { type: "launch", wrapped: true }).ignored !== "", "launched twice: ignored");

        stepped = rules.step(waiting, { type: "cancel" });
        assertEqual(stepped.state.phase + " " + stepped.state.cancelled + " " + _types(stepped.effects), "done true mute answer", "cancelled while waiting: answered at once, nothing started");
        assert(rules.step(stepped.state, { type: "launch", wrapped: true }).ignored !== "", "… and never launched after");

        stepped = rules.step(bare, { type: "cancel" });
        assertEqual(stepped.state.phase + " " + _types(stepped.effects), "ending mute stop:watchdog signal:15 timer:kill:300", "cancelled while running, bare: mute first, TERM, KILL after killAfterMs");
        const cancelledBare = stepped.state;
        stepped = rules.step(wrapped, { type: "cancel" });
        assertEqual(_types(stepped.effects), "mute stop:watchdog signal:15 timer:kill:1300", "… inside timeout: its own KILL comes first, the runner's a margin later");
        assert(rules.step(cancelledBare, { type: "cancel" }).ignored !== "", "cancelled twice: ignored");
        // outputAfterCancel: the same steps, never muted
        const talkative = rules.step(rules.fresh(1000, 300, true), { type: "launch", wrapped: false }).state;
        stepped = rules.step(talkative, { type: "cancel" });
        assertEqual(stepped.state.phase + " " + stepped.state.cancelled + " " + _types(stepped.effects), "ending true stop:watchdog signal:15 timer:kill:300",
                    "outputAfterCancel, cancelled while running: TERM and KILL as ever, not muted");
        assertEqual(_types(rules.step(rules.step(talkative, { type: "watchdog" }).state, { type: "cancel" }).effects), "", "… cancelled while being ended by the limit: not muted");
        stepped = rules.step(rules.fresh(1000, 300, true), { type: "cancel" });
        assertEqual(stepped.state.phase + " " + _types(stepped.effects), "done answer", "… cancelled while waiting: answered at once");
        const talkativeDone = _after(talkative, [{ type: "exited", code: 0 }, { type: "stopped" }]);
        stepped = rules.step(talkativeDone, { type: "cancel", queued: true });
        assertEqual(stepped.state.cancelled + " " + _types(stepped.effects), "true ", "… cancelled while its answer waits: cancelled, not muted");
        assertEqual(rules.fresh(1000, 300).outputAfterCancel + " " + rules.fresh(1000, 300, "yes").outputAfterCancel, "false false", "fresh: outputAfterCancel only when true");
        stepped = rules.step(cancelledBare, { type: "kill" });
        assertEqual(stepped.state.phase + " " + _types(stepped.effects), "ending signal:9", "the kill timer: KILL");
        assert(rules.step(bare, { type: "kill" }).ignored !== "", "a kill timer on a run not told to end: ignored");

        stepped = rules.step(bare, { type: "watchdog" });
        assertEqual(stepped.state.phase + " " + stepped.state.timedOut + " " + _types(stepped.effects), "ending true signal:15 timer:kill:300", "the watchdog, bare: TERM, KILL after killAfterMs");
        const timedOutBare = stepped.state;
        stepped = rules.step(wrapped, { type: "watchdog" });
        assertEqual(stepped.state.timedOut + " " + _types(stepped.effects), "true signal:9", "the watchdog inside timeout (which hangs): KILL");
        assert(rules.step(cancelledBare, { type: "watchdog" }).ignored !== "", "a watchdog after a cancel: ignored");
        stepped = rules.step(timedOutBare, { type: "cancel" });
        assertEqual(stepped.state.cancelled + " " + stepped.state.timedOut + " " + _types(stepped.effects), "true true mute", "cancelled while being ended by the limit: muted, both said");

        stepped = rules.step(bare, { type: "exited", code: 3, crashed: false });
        assertEqual(stepped.state.phase + " " + stepped.state.code + " " + stepped.effects.length, "running 3 0", "an exit: remembered, the answer waits for the process to be gone");
        assert(rules.step(stepped.state, { type: "exited", code: 4 }).ignored !== "", "a second exit: ignored");
        stepped = rules.step(stepped.state, { type: "stopped" });
        assertEqual(stepped.state.phase + " " + _types(stepped.effects), "done stop:watchdog stop:kill answer", "the process gone: timers stopped, answered");
        for (const type of ["cancel", "watchdog", "kill", "exited", "stopped", "launch"])
            assert(rules.step(stepped.state, { type: type }).ignored !== "", "after the answer, " + type + ": ignored");
        const answered = stepped.state;
        stepped = rules.step(answered, { type: "cancel", queued: true });
        assertEqual(stepped.state.phase + " " + stepped.state.cancelled + " " + _types(stepped.effects), "done true mute",
                    "cancelled while its answer still waits to be handed over: that answer says cancelled, no second one");
        assert(rules.step(stepped.state, { type: "cancel", queued: true }).ignored !== "", "… cancelled twice: ignored");
        assert(rules.step(answered, { type: "cancel", queued: false }).ignored !== "", "a cancel after the answer was handed over: ignored");
        const refused = Object.assign({}, waiting, { phase: "done" });
        assertEqual(rules.step(refused, { type: "cancel", queued: true }).state.cancelled + " " + rules.step(refused, { type: "cancel", queued: true }).state.launched,
                    "true false", "a refused run cancelled before its answer: cancelled, never started");
        const unstartable = rules.result(_after(bare, [{ type: "stopped" }, { type: "cancel", queued: true }]), { stdout: "", stderr: "", truncated: false, durationMs: 1 });
        assertEqual(unstartable.failedToStart + " " + unstartable.cancelled + " " + unstartable.ok, "true true false", "a program that cannot start, cancelled before its answer: both said");
        assert(rules.step(waiting, { type: "stopped" }).ignored !== "" && rules.step(waiting, { type: "exited", code: 0 }).ignored !== "", "an exit of a run never started: ignored");
        assert(rules.step(bare, { type: "explode" }).ignored !== "" && rules.step(null, { type: "cancel" }).ignored !== "", "an unknown event, no state: ignored");

        // --- the answer ---
        const facts = (durationMs, more) => Object.assign({ stdout: "out", stderr: "err", truncated: false, durationMs: durationMs }, more ?? {});
        const exit = (code, crashed) => ({ type: "exited", code: code, crashed: crashed === true });
        let result = rules.result(_after(bare, [exit(0), { type: "stopped" }]), facts(12.4));
        assertEqual(JSON.stringify(result), JSON.stringify({ ok: true, code: 0, stdout: "out", stderr: "err", timedOut: false, cancelled: false,
                                                                 failedToStart: false, truncated: false, durationMs: 12, error: "" }), "exit 0: ok");
        assert(Object.isFrozen(result), "… frozen");
        result = rules.result(_after(bare, [exit(3), { type: "stopped" }]), facts(12, { truncated: true }));
        assertEqual(result.ok + " " + result.code + " " + result.truncated, "false 3 true", "exit 3: not ok, the code, the cut said");
        result = rules.result(_after(bare, [{ type: "stopped" }]), facts(1));
        assertEqual(result.ok + " " + result.code + " " + result.failedToStart, "false -1 true", "gone without an exit: it could not start");
        result = rules.result(_after(wrapped, [exit(127), { type: "stopped" }]), facts(1));
        assertEqual(result.failedToStart + " " + result.code, "true 127", "127 from timeout: it could not start the command");
        assert(rules.result(_after(wrapped, [exit(126), { type: "stopped" }]), facts(1)).failedToStart, "… 126 too");
        assert(!rules.result(_after(bare, [exit(127), { type: "stopped" }]), facts(1)).failedToStart, "127 from a bare command is its own exit status");
        const setprivSaid = { lastStderr: "setpriv: failed to execute x: No such file or directory" };
        result = rules.result(_after(unlimited, [exit(127), { type: "stopped" }]), facts(1, setprivSaid));
        assertEqual(result.failedToStart + " " + result.code, "true 127", "127 from setpriv alone (no limit), its message last on stderr: it could not start the command");
        assert(rules.result(_after(unlimited, [exit(126), { type: "stopped" }]), facts(1, setprivSaid)).failedToStart, "… 126 too");
        result = rules.result(_after(unlimited, [exit(126), { type: "stopped" }]), facts(1, { lastStderr: "Error executing command as another user: Request dismissed" }));
        assertEqual(result.failedToStart + " " + result.code, "false 126", "126 behind setpriv alone, without its message: the command's own (pkexec's dismissed prompt)");
        assert(!rules.result(_after(unlimited, [exit(127), { type: "stopped" }]), facts(1)).failedToStart, "… 127 with nothing on stderr too");
        assert(!rules.result(_after(unlimited, [{ type: "cancel" }, exit(127), { type: "stopped" }]), facts(1, setprivSaid)).failedToStart, "… and never once cancelled");
        result = rules.result(_after(bare, [exit(9, true), { type: "stopped" }]), facts(5));
        assertEqual(result.ok + " " + result.code + " " + result.failedToStart, "false -1 false", "ended by a signal: no exit status, not ok");

        result = rules.result(_after(wrapped, [exit(124), { type: "stopped" }]), facts(1000));
        assertEqual(result.timedOut + " " + result.ok + " " + result.code, "true false 124", "124 from timeout after the limit: timed out");
        assert(!rules.result(_after(wrapped, [exit(124), { type: "stopped" }]), facts(999)).timedOut, "124 before the limit is the command's own");
        assert(!rules.result(_after(bare, [exit(124), { type: "stopped" }]), facts(5000)).timedOut, "124 from a bare command is its own");
        assert(rules.result(_after(wrapped, [exit(9, true), { type: "stopped" }]), facts(1300)).timedOut, "ended by timeout's KILL after the limit: timed out");
        assert(!rules.result(_after(wrapped, [exit(9, true), { type: "stopped" }]), facts(200)).timedOut, "killed before the limit: not a time-out");
        result = rules.result(_after(bare, [{ type: "watchdog" }, exit(15, true), { type: "stopped" }]), facts(1000));
        assertEqual(result.timedOut + " " + result.cancelled + " " + result.failedToStart + " " + result.ok, "true false false false", "ended by the runner's watchdog: timed out");
        result = rules.result(_after(bare, [{ type: "watchdog" }, exit(0), { type: "stopped" }]), facts(1000));
        assertEqual(result.timedOut + " " + result.ok, "true false", "… not ok even when the command then exits 0");

        result = rules.result(_after(bare, [{ type: "cancel" }, exit(15, true), { type: "stopped" }]), facts(40));
        assertEqual(result.cancelled + " " + result.timedOut + " " + result.failedToStart + " " + result.ok, "true false false false", "cancelled while running");
        result = rules.result(_after(wrapped, [{ type: "cancel" }, exit(124), { type: "stopped" }]), facts(5000));
        assertEqual(result.cancelled + " " + result.timedOut, "true false", "cancelled, however it then ends: not a time-out");
        result = rules.result(_after(bare, [{ type: "cancel" }, exit(0), { type: "stopped" }]), facts(40));
        assertEqual(result.cancelled + " " + result.ok, "true false", "cancelled, and the command exits 0: still not ok");
        result = rules.result(_after(waiting, [{ type: "cancel" }]), facts(0, { stdout: "", stderr: "" }));
        assertEqual(result.cancelled + " " + result.failedToStart + " " + result.code + " " + result.durationMs, "true false -1 0", "cancelled while waiting: never started, which is no failure to start");

        result = rules.refusal("the command is empty");
        assertEqual(result.ok + " " + result.code + " " + result.error + " " + Object.isFrozen(result), "false -1 the command is empty true", "a refusal: the reason in `error`, nothing else set");
        assertEqual(Object.keys(result).join(), Object.keys(rules.result(_after(bare, [exit(0), { type: "stopped" }]), facts(1))).join(), "… with the fields of any answer");
        result = rules.refusal("the command is empty", true);
        assertEqual(result.cancelled + " " + result.ok + " " + result.error, "true false the command is empty", "a refusal cancelled before it was handed over: cancelled, the reason kept");

        // --- the output ---
        assertEqual(JSON.stringify(rules.kept("abc", "de", 10)), "{\"text\":\"abcde\",\"truncated\":false}", "kept: under the cap");
        assertEqual(JSON.stringify(rules.kept("abc", "defgh", 5)), "{\"text\":\"abcde\",\"truncated\":true}", "… cut at the cap");
        assertEqual(JSON.stringify(rules.kept("abcde", "f", 5)), "{\"text\":\"abcde\",\"truncated\":true}", "… full: nothing added");
        assertEqual(JSON.stringify(rules.kept("", "abc", 3)), "{\"text\":\"abc\",\"truncated\":false}", "… exactly the cap is not a cut");

        assertEqual(JSON.stringify(rules.linesOf("one")) + JSON.stringify(rules.linesOf("")), "[\"one\"][\"\"]", "a piece of the parser's: one line, an empty one too");
        assertEqual(JSON.stringify(rules.linesOf("\nc")) + JSON.stringify(rules.linesOf("\n")), "[\"\",\"c\"][\"\",\"\"]", "… with the empty line the parser kept back in front");
        assertEqual(JSON.stringify(rules.keptLine("", 0, "one", 100)), "{\"text\":\"one\",\"truncated\":false}", "the first line kept: as it is");
        assertEqual(rules.keptLine("one", 1, "two", 100).text, "one\ntwo", "… the next after a line break, none after the last");
        assertEqual(rules.keptLine("", 1, "two", 100).text, "\ntwo", "… after an empty first line too");
        assertEqual(JSON.stringify(rules.keptLine("one", 1, "two", 5)), "{\"text\":\"one\\nt\",\"truncated\":true}", "… cut at the cap, the line break counted");
    }
}
