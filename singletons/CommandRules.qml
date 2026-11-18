pragma Singleton

import Quickshell
import QtQuick

// The decisions of the command runner (singletons/io/CommandRunner.qml), pure: what a run
// is asked with, the command it becomes, how its life goes (step), what its output is cut
// to, and the answer. The runner only starts processes, keeps timers and calls these.
Singleton {
    id: root

    readonly property int defaultTimeoutMs: 30000
    readonly property int defaultKillAfterMs: 3000
    readonly property int defaultMaxOutputBytes: 1048576

    // How much later than `timeout`'s own KILL the runner's timers fire for a run that
    // `timeout` wraps: they are only there for a `timeout` that does not do its work
    readonly property int backstopMs: 1000

    // Where coreutils' `timeout` is looked for, in this order: system directories only
    // (NixOS, Arch), never PATH — the program that ends a run is not taken from a place the
    // user can write
    readonly property var timeoutCandidates: ["/run/current-system/sw/bin/timeout", "/usr/bin/timeout"]

    readonly property var _callbackNames: ["onStdout", "onStderr", "onLine", "done"]

    // "" when `argv` can be run: a non-empty list of strings, the first one not empty,
    // none with a NUL character (which would cut the word short)
    function argvProblem(argv) {
        if (argv === null || typeof argv !== "object" || typeof argv.length !== "number")
            return "the command is not a list of words";
        if (argv.length === 0)
            return "the command is empty";
        for (let i = 0; i < argv.length; i++) {
            if (typeof argv[i] !== "string")
                return "word " + (i + 1) + " of the command is not a string";
            if (argv[i].includes("\u0000"))
                return "word " + (i + 1) + " of the command holds a NUL character";
        }
        if (argv[0] === "")
            return "the command's program is empty";
        return "";
    }

    function _wholeNumber(value, least) {
        return typeof value === "number" && isFinite(value) && value >= least;
    }

    // → { problem, timeoutMs, killAfterMs, keepOutput, maxOutputBytes, environment }: what
    // was given, with the defaults for what was not. `problem` is "" when everything given
    // is of its kind; a wrong one is never replaced by a default silently.
    function options(given) {
        const result = {
            problem: "", timeoutMs: defaultTimeoutMs, killAfterMs: defaultKillAfterMs,
            keepOutput: true, maxOutputBytes: defaultMaxOutputBytes, environment: {}
        };
        if (given === undefined || given === null)
            return result;
        if (typeof given !== "object" || Array.isArray(given)) {
            result.problem = "the options are not an object";
            return result;
        }
        const has = name => given[name] !== undefined && given[name] !== null;
        if (has("timeoutMs")) {
            if (!_wholeNumber(given.timeoutMs, 0))
                result.problem = "timeoutMs is not a number of milliseconds, 0 or more";
            else
                result.timeoutMs = Math.round(given.timeoutMs);
        }
        if (has("killAfterMs")) {
            if (!_wholeNumber(given.killAfterMs, 0))
                result.problem = "killAfterMs is not a number of milliseconds, 0 or more";
            else
                result.killAfterMs = Math.round(given.killAfterMs);
        }
        if (has("maxOutputBytes")) {
            if (!_wholeNumber(given.maxOutputBytes, 0))
                result.problem = "maxOutputBytes is not a number, 0 or more";
            else
                result.maxOutputBytes = Math.round(given.maxOutputBytes);
        }
        if (has("keepOutput")) {
            if (typeof given.keepOutput !== "boolean")
                result.problem = "keepOutput is not true or false";
            else
                result.keepOutput = given.keepOutput;
        }
        if (has("environment")) {
            const problem = environmentProblem(given.environment);
            if (problem !== "")
                result.problem = problem;
            else
                result.environment = Object.assign({}, given.environment);
        }
        for (const name of _callbackNames) {
            if (has(name) && typeof given[name] !== "function")
                result.problem = name + " is not a function";
        }
        return result;
    }

    // "" for { NAME: "value" } — or null as a value, which takes the variable away
    function environmentProblem(environment) {
        if (environment === undefined || environment === null)
            return "";
        if (typeof environment !== "object" || Array.isArray(environment))
            return "the environment is not an object of names and values";
        for (const name of Object.keys(environment)) {
            const value = environment[name];
            if (name === "" || name.includes("=") || name.includes("\u0000"))
                return "the environment has a name that cannot be one";
            if (value !== null && (typeof value !== "string" || value.includes("\u0000")))
                return "the environment's " + name + " is not a string";
        }
        return "";
    }

    // The runner's own environment with a run's on top
    function mergedEnvironment(runnerEnvironment, runEnvironment) {
        const base = environmentProblem(runnerEnvironment) === "" ? runnerEnvironment : {};
        return Object.assign({}, base ?? {}, runEnvironment ?? {});
    }

    // Milliseconds as `timeout` reads a duration: seconds, at most three decimals
    function seconds(milliseconds) {
        return String(Number((milliseconds / 1000).toFixed(3)));
    }

    // Whether a run is put inside `timeout`: it has a time limit and the program was found
    function wraps(timeoutProgram, timeoutMs) {
        return typeof timeoutProgram === "string" && timeoutProgram !== "" && timeoutMs > 0;
    }

    // The words actually started. With a limit: `timeout -k <kill after> <limit> <argv…>`;
    // `timeout` stops reading options at the limit, so the command's own words are never
    // taken for its options. A kill-after of 0 would switch its KILL off: 1 ms then.
    function commandLine(argv, timeoutProgram, timeoutMs, killAfterMs) {
        const words = Array.from(argv);
        if (!wraps(timeoutProgram, timeoutMs))
            return words;
        return [timeoutProgram, "-k", seconds(Math.max(killAfterMs, 1)), seconds(timeoutMs)].concat(words);
    }

    // ---- A run's life ----
    //
    // waiting (for the look-up of `timeout`) → running → ending (told to stop: by cancel()
    // or by the runner's own time limit) → done. A wrapped run is ended by `timeout` itself
    // (its limit, and after a TERM its own KILL); the runner's timers for it are a backstop.

    function fresh(timeoutMs, killAfterMs) {
        return {
            phase: "waiting", launched: false, wrapped: false, timeoutMs: timeoutMs, killAfterMs: killAfterMs,
            timedOut: false, cancelled: false, exited: false, code: -1, crashed: false
        };
    }

    // → { state, effects, ignored }. `ignored` is "" when the event was taken, else why not
    // (the state is then the object passed in, no effects). Events: launch { wrapped },
    // cancel, watchdog (the runner's time limit), kill (its kill timer), exited { code,
    // crashed }, stopped (the process is gone, with or without an exit). Effects, in order:
    // start | timer { name, ms } | stop { name } | signal { signal } | mute (no chunk or
    // line callback from here) | answer.
    function step(state, event) {
        const phase = state?.phase;
        const type = event?.type;
        const ignored = why => ({ state: state, effects: [], ignored: why });
        const next = (changes, effects) => ({ state: Object.assign({}, state, changes), effects: effects, ignored: "" });
        if (typeof phase !== "string")
            return ignored("no state");
        if (phase === "done")
            return ignored("done");
        const live = phase === "running" || phase === "ending";
        switch (type) {
        case "launch": {
            if (phase !== "waiting")
                return ignored("started before");
            const wrapped = event.wrapped === true && state.timeoutMs > 0;
            const effects = [{ type: "start" }];
            if (state.timeoutMs > 0)
                effects.push({ type: "timer", name: "watchdog", ms: state.timeoutMs + (wrapped ? state.killAfterMs + backstopMs : 0) });
            return next({ phase: "running", launched: true, wrapped: wrapped }, effects);
        }
        case "cancel":
            if (phase === "waiting")
                return next({ phase: "done", cancelled: true }, [{ type: "mute" }, { type: "answer" }]);
            if (phase === "ending")
                return state.cancelled ? ignored("cancelled before") : next({ cancelled: true }, [{ type: "mute" }]);
            return next({ phase: "ending", cancelled: true }, [
                { type: "mute" }, { type: "stop", name: "watchdog" }, { type: "signal", signal: 15 },
                { type: "timer", name: "kill", ms: state.killAfterMs + (state.wrapped ? backstopMs : 0) }
            ]);
        case "watchdog":
            if (phase !== "running")
                return ignored("not running");
            // A wrapped run that is still there after `timeout`'s limit and KILL: `timeout`
            // itself hangs, nothing gentler is left
            if (state.wrapped)
                return next({ phase: "ending", timedOut: true }, [{ type: "signal", signal: 9 }]);
            return next({ phase: "ending", timedOut: true }, [
                { type: "signal", signal: 15 }, { type: "timer", name: "kill", ms: state.killAfterMs }
            ]);
        case "kill":
            if (phase !== "ending")
                return ignored("not ending");
            return next({}, [{ type: "signal", signal: 9 }]);
        case "exited":
            if (!live || state.exited)
                return ignored(live ? "exited before" : "not started");
            return next({ exited: true, code: typeof event.code === "number" ? event.code : -1, crashed: event.crashed === true }, []);
        case "stopped":
            if (!live)
                return ignored("not started");
            return next({ phase: "done" }, [{ type: "stop", name: "watchdog" }, { type: "stop", name: "kill" }, { type: "answer" }]);
        }
        return ignored("unknown event");
    }

    // ---- Output ----

    // What is kept of a stream after `chunk`: → { text, truncated }, never longer than
    // `limit` (counted in characters as read, which for ASCII are the bytes)
    function kept(text, chunk, limit) {
        const room = limit - text.length;
        if (chunk.length <= room)
            return { text: text + chunk, truncated: false };
        return { text: room > 0 ? text + chunk.slice(0, room) : text, truncated: true };
    }

    function freshLines() {
        return { rest: "", skipping: false };
    }

    // The whole lines `chunk` completes, after what earlier chunks left unfinished:
    // → { lines, pending, truncated }, `pending` the state for the next chunk. A line
    // longer than `limit` is handed over cut to it once, and the rest of it dropped.
    function splitLines(pending, chunk, limit) {
        const lines = [];
        let truncated = false;
        let rest = pending.rest;
        let skipping = pending.skipping;
        let from = 0;
        while (from <= chunk.length) {
            const at = chunk.indexOf("\n", from);
            const piece = chunk.slice(from, at === -1 ? chunk.length : at);
            if (!skipping) {
                const line = kept(rest, piece, limit);
                rest = line.text;
                if (line.truncated) {
                    lines.push(rest);
                    rest = "";
                    skipping = true;
                    truncated = true;
                }
            }
            if (at === -1)
                break;
            if (!skipping)
                lines.push(rest);
            rest = "";
            skipping = false;
            from = at + 1;
        }
        return { lines: lines, pending: { rest: rest, skipping: skipping }, truncated: truncated };
    }

    // The line a stream ends with when it did not end in a newline: [] or [line]
    function lastLines(pending) {
        return pending.rest !== "" && !pending.skipping ? [pending.rest] : [];
    }

    // ---- The answer ----

    // `state` at the end; `facts`: { stdout, stderr, truncated, durationMs }. Frozen.
    //   failedToStart  the process ended without an exit status (Quickshell reports a
    //                  program that cannot start so) — or, inside `timeout`, with 126 or
    //                  127, the two codes `timeout` gives for a command it could not run
    //                  (a command that exits with one of them itself reads the same)
    //   timedOut       the runner's own limit ended it, or `timeout` did: the run took at
    //                  least the limit and ended with 124, or by the KILL that follows
    //   code           the exit status; -1 without one (never started, or ended by a signal)
    function result(state, facts) {
        const code = state.exited && !state.crashed ? state.code : -1;
        const failedToStart = state.launched
            && (!state.exited || (state.wrapped && !state.cancelled && !state.timedOut && (code === 126 || code === 127)));
        const limitReached = state.wrapped && state.exited && facts.durationMs >= state.timeoutMs
            && (state.crashed || state.code === 124);
        const timedOut = state.timedOut || (limitReached && !state.cancelled);
        return Object.freeze({
            ok: state.exited && !state.crashed && state.code === 0 && !timedOut && !state.cancelled && !failedToStart,
            code: code,
            stdout: facts.stdout ?? "",
            stderr: facts.stderr ?? "",
            timedOut: timedOut,
            cancelled: state.cancelled,
            failedToStart: failedToStart,
            truncated: facts.truncated === true,
            durationMs: Math.max(0, Math.round(facts.durationMs ?? 0)),
            error: ""
        });
    }

    // The answer to a run that was never started: what was asked could not be run
    function refusal(problem) {
        return Object.freeze({
            ok: false, code: -1, stdout: "", stderr: "", timedOut: false, cancelled: false,
            failedToStart: false, truncated: false, durationMs: 0, error: problem
        });
    }
}
