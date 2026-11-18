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

    // The programs put around a run with a time limit, in this order, and the arguments
    // each must run with, exit 0, to count. CommandTools takes each from PATH, and only a
    // match that only root can change (ModuleRules.programVerdict): what ends a run is not
    // taken from a place the user can write. `timeout` (coreutils) ends the command;
    // `setpriv` (util-linux) is there for its --pdeathsig alone (commandLine).
    readonly property var wrapperTools: [
        { name: "timeout", probe: ["--version"] },
        { name: "setpriv", probe: ["--pdeathsig", "KILL", "--version"] }
    ]

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

    // Whether a run is put inside `timeout`: it has a time limit and both programs were
    // found (`tools`: { timeout, setpriv }). Without `setpriv` it is not: the shell's end
    // would then leave the command running, with nothing to end it.
    function wraps(tools, timeoutMs) {
        const found = path => typeof path === "string" && path !== "";
        return found(tools?.timeout) && found(tools?.setpriv) && timeoutMs > 0;
    }

    // The words actually started. With a limit:
    //   timeout -k <kill after> <limit> setpriv --pdeathsig KILL -- <argv…>
    // `timeout` ends the command at the limit, also when the shell is gone. `setpriv` only
    // asks the kernel to send the command a KILL when its parent — `timeout` — dies, and
    // then becomes the command: the shell's own end kills its child, `timeout`, with a
    // KILL that cannot be passed on, and the command would go on without a limit. (The
    // kernel drops that request when the command is a setuid program.) `timeout` stops
    // reading options at the limit and `setpriv` at "--", so the command's own words are
    // never taken for theirs. A kill-after of 0 would switch `timeout`'s KILL off: 1 ms.
    function commandLine(argv, tools, timeoutMs, killAfterMs) {
        const words = Array.from(argv);
        if (!wraps(tools, timeoutMs))
            return words;
        return [tools.timeout, "-k", seconds(Math.max(killAfterMs, 1)), seconds(timeoutMs),
                tools.setpriv, "--pdeathsig", "KILL", "--"].concat(words);
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

    // What is kept of a stream after `more`: → { text, truncated }, never longer than
    // `limit` (counted in characters, which for ASCII are the bytes)
    function kept(text, more, limit) {
        const room = limit - text.length;
        if (more.length <= room)
            return { text: text + more, truncated: false };
        return { text: room > 0 ? text + more.slice(0, room) : text, truncated: true };
    }

    // The lines in one piece of a stream as Quickshell's line parser hands it over. A piece
    // is one line — but after a line the parser does not see a line break that follows at
    // once: an empty line is kept back and comes as a line break in front of the next
    // piece ("\nc": an empty line, then "c"). At the stream's end what it kept back comes
    // as the piece "\n", which reads here as two empty lines where one was written: an
    // output that ends in an empty line shows one more.
    function linesOf(piece) {
        return piece.split("\n");
    }

    // A stream's kept text after one more line: the lines joined by line breaks, so the
    // last one has none whether or not the command wrote one. `count`: lines kept before.
    function keptLine(text, count, line, limit) {
        return kept(text, (count > 0 ? "\n" : "") + line, limit);
    }

    // ---- The answer ----

    // `state` at the end; `facts`: { stdout, stderr, truncated, durationMs }. Frozen.
    //   failedToStart  the process ended without an exit status (Quickshell reports a
    //                  program that cannot start so) — or, inside `timeout`, with 126 or
    //                  127, the two codes it and `setpriv` give for a command not run
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
