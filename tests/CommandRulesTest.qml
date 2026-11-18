import QtQuick
import qs.singletons

// The command runner's decisions (singletons/CommandRules.qml): what may be run, the
// command line with `timeout`, a run's life, the output's cuts, the answer
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

        // --- the options ---
        const defaults = rules.options(undefined);
        assertEqual(JSON.stringify(defaults), JSON.stringify({ problem: "", timeoutMs: 30000, killAfterMs: 3000, keepOutput: true, maxOutputBytes: 1048576, environment: {} }),
                    "none given: 30 s, KILL 3 s after, the output kept, 1 MiB");
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
        assertEqual(JSON.stringify(rules.commandLine(["tailscale", "file", "cp", "--", "a b"], "/usr/bin/timeout", 30000, 3000)),
                    JSON.stringify(["/usr/bin/timeout", "-k", "3", "30", "tailscale", "file", "cp", "--", "a b"]), "with a limit: inside timeout -k, the words untouched");
        assertEqual(JSON.stringify(rules.commandLine(["-n", "x"], "/usr/bin/timeout", 500, 0)),
                    JSON.stringify(["/usr/bin/timeout", "-k", "0.001", "0.5", "-n", "x"]), "a kill-after of 0 would switch timeout's KILL off: 1 ms");
        assertEqual(JSON.stringify(rules.commandLine(["ls"], "/usr/bin/timeout", 0, 3000)), "[\"ls\"]", "no limit: the command as it is");
        assertEqual(JSON.stringify(rules.commandLine(["ls"], "", 30000, 3000)), "[\"ls\"]", "no timeout found: the command as it is");
        assert(!rules.wraps(undefined, 30000) && !rules.wraps("", 30000) && !rules.wraps("/usr/bin/timeout", 0) && rules.wraps("/usr/bin/timeout", 1), "wrapped: a limit and a program");
        assert(rules.timeoutCandidates.every(path => path.startsWith("/") && !path.startsWith("/home") && !path.includes("/.")), "timeout is looked for in system directories only");

        // --- a run's life ---
        const waiting = rules.fresh(1000, 300);
        let stepped = rules.step(waiting, { type: "launch", wrapped: true });
        assertEqual(stepped.state.phase + " " + _types(stepped.effects), "running start timer:watchdog:2300", "launched inside timeout: started, the watchdog after the limit, timeout's KILL and a margin");
        assert(waiting.phase === "waiting", "a step leaves the state it was given alone");
        const wrapped = stepped.state;
        stepped = rules.step(waiting, { type: "launch", wrapped: false });
        assertEqual(stepped.state.wrapped + " " + _types(stepped.effects), "false start timer:watchdog:1000", "launched bare: the watchdog at the limit");
        const bare = stepped.state;
        stepped = rules.step(rules.fresh(0, 300), { type: "launch", wrapped: true });
        assertEqual(stepped.state.wrapped + " " + _types(stepped.effects), "false start", "no limit: never wrapped, no watchdog");
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

        // --- the output ---
        assertEqual(JSON.stringify(rules.kept("abc", "de", 10)), "{\"text\":\"abcde\",\"truncated\":false}", "kept: under the cap");
        assertEqual(JSON.stringify(rules.kept("abc", "defgh", 5)), "{\"text\":\"abcde\",\"truncated\":true}", "… cut at the cap");
        assertEqual(JSON.stringify(rules.kept("abcde", "f", 5)), "{\"text\":\"abcde\",\"truncated\":true}", "… full: nothing added");
        assertEqual(JSON.stringify(rules.kept("", "abc", 3)), "{\"text\":\"abc\",\"truncated\":false}", "… exactly the cap is not a cut");

        let split = rules.splitLines(rules.freshLines(), "one\ntwo\npar", 100);
        assertEqual(JSON.stringify(split.lines) + " " + split.pending.rest, "[\"one\",\"two\"] par", "whole lines, the unfinished one kept back");
        split = rules.splitLines(split.pending, "tial\n\nlast", 100);
        assertEqual(JSON.stringify(split.lines) + " " + split.pending.rest, "[\"partial\",\"\"] last", "a line over two chunks put together; an empty line is a line");
        assertEqual(JSON.stringify(rules.lastLines(split.pending)), "[\"last\"]", "the end without a newline: one more line");
        split = rules.splitLines(split.pending, "\n", 100);
        assertEqual(JSON.stringify(split.lines) + " " + rules.lastLines(split.pending).length, "[\"last\"] 0", "the end with a newline: none");
        assertEqual(rules.splitLines(rules.freshLines(), "", 100).lines.length, 0, "an empty chunk: nothing");
        split = rules.splitLines(rules.freshLines(), "abcdefgh", 5);
        assertEqual(JSON.stringify(split.lines) + " " + split.truncated + " " + split.pending.skipping, "[\"abcde\"] true true", "a line over the cap: handed over cut, at once");
        split = rules.splitLines(split.pending, "ijk", 5);
        assertEqual(split.lines.length + " " + rules.lastLines(split.pending).length, "0 0", "… its rest dropped, also at the end");
        split = rules.splitLines(split.pending, "lmn\nnext\n", 5);
        assertEqual(JSON.stringify(split.lines) + " " + split.pending.skipping, "[\"next\"] false", "… until its newline; the next line is whole again");
        split = rules.splitLines(rules.freshLines(), "abcde\nxy\n", 5);
        assertEqual(JSON.stringify(split.lines) + " " + split.truncated, "[\"abcde\",\"xy\"] false", "a line of exactly the cap is not cut");
    }
}
