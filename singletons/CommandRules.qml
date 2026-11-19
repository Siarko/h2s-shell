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

    // The programs put around a run, in this order, and the arguments each must run with,
    // exit 0, to count. CommandTools takes each from PATH, and only a match that only root
    // can change (ModuleRules.programVerdict): what ends a run is not taken from a place
    // the user can write. `timeout` (coreutils) ends a command with a time limit;
    // `setpriv` (util-linux) is there for its --pdeathsig alone, in front of a run with a
    // limit and of one that asks to end with the shell (commandLine).
    readonly property var wrapperTools: [
        { name: "timeout", probe: ["--version"] },
        { name: "setpriv", probe: ["--pdeathsig", "KILL", "--version"] }
    ]

    readonly property var _callbackNames: ["onStdout", "onStderr", "onLine", "done"]

    // A command has at most this many words
    readonly property int maxWords: 100000

    // The command a caller handed over, read once: → { argv, words, problem }. `argv` is a
    // fresh plain array of primitive strings, the only thing checked and run after this (null
    // when `problem` is not ""); `words` the same copy whenever every word could be read,
    // whatever they are (null when the value is no list, too long, or a read threw), for a
    // caller that tells some problems apart on it. `length` and each element are read
    // exactly once, so an accessor, a getter on `length` or a Proxy cannot show one command
    // to the checks and another at the start. `arraysOnly`: a real array (Array.isArray) and nothing else; otherwise a
    // list-like value too (a QML list<string>, which is no array). Refused: not a list,
    // empty, more than maxWords words, a word that is not a primitive string or holds a NUL
    // character (which would cut the word short), the first word empty, a read that threw.
    function argvSnapshot(value, arraysOnly) {
        let copy = null;
        const refuse = problem => ({ argv: null, words: copy, problem: problem });
        try {
            if (value === null || typeof value !== "object")
                return refuse("the command is not a list of words");
            if (arraysOnly === true && !Array.isArray(value))
                return refuse("the command is not an array of words");
            // Reflect.get: a plain `value.length` has been seen to ask a Proxy twice (the
            // engine's property cache, primed by another kind of object, reads again)
            const length = Reflect.get(value, "length");
            if (typeof length !== "number" || !Number.isInteger(length) || length < 0)
                return refuse("the command is not a list of words");
            if (length === 0)
                return refuse("the command is empty");
            if (length > maxWords)
                return refuse("the command has more than " + maxWords + " words");
            const read = [];
            for (let i = 0; i < length; i++)
                read.push(Reflect.get(value, i));
            copy = read;
            for (let i = 0; i < copy.length; i++) {
                if (typeof copy[i] !== "string")
                    return refuse("word " + (i + 1) + " of the command is not a string");
                if (copy[i].includes("\u0000"))
                    return refuse("word " + (i + 1) + " of the command holds a NUL character");
            }
            if (copy[0] === "")
                return refuse("the command's program is empty");
            return { argv: copy, words: copy, problem: "" };
        } catch (error) {
            copy = null;
            return refuse("the command could not be read");
        }
    }

    // "" when `argv` can be run (argvSnapshot's problem, list-like values accepted). For a
    // value already copied: code that checks a caller's value and then runs it takes the
    // snapshot and runs that.
    function argvProblem(argv) {
        return argvSnapshot(argv, false).problem;
    }

    // Some of an options object's fields, each read exactly once, into a plain object: what
    // is checked is what is used (a getter is not asked twice). Undefined for a field not
    // there; a read that throws reads as undefined.
    function readOnce(given, names) {
        const read = {};
        for (const name of names) {
            try {
                read[name] = Reflect.get(given, name);
            } catch (error) {
                read[name] = undefined;
            }
        }
        return read;
    }

    function _wholeNumber(value, least) {
        return typeof value === "number" && isFinite(value) && value >= least;
    }

    // → { problem, timeoutMs, killAfterMs, keepOutput, outputAfterCancel, endWithShell,
    // maxOutputBytes, environment, callbacks }: what was given, with the defaults for what was not, every field read once
    // (`callbacks`: { onStdout, onStderr, onLine, done } as read, each a function or null —
    // `done` even when `problem` is set, as an answer is owed). `problem` is "" when
    // everything given is of its kind; a wrong one is never replaced by a default silently.
    function options(given) {
        const result = {
            problem: "", timeoutMs: defaultTimeoutMs, killAfterMs: defaultKillAfterMs,
            keepOutput: true, outputAfterCancel: false, endWithShell: false, maxOutputBytes: defaultMaxOutputBytes, environment: {},
            callbacks: { onStdout: null, onStderr: null, onLine: null, done: null }
        };
        if (given === undefined || given === null)
            return result;
        if (typeof given !== "object" || Array.isArray(given)) {
            result.problem = "the options are not an object";
            return result;
        }
        const read = readOnce(given, ["timeoutMs", "killAfterMs", "maxOutputBytes", "keepOutput", "outputAfterCancel", "endWithShell", "environment"].concat(_callbackNames));
        const has = name => read[name] !== undefined && read[name] !== null;
        if (has("timeoutMs")) {
            if (!_wholeNumber(read.timeoutMs, 0))
                result.problem = "timeoutMs is not a number of milliseconds, 0 or more";
            else
                result.timeoutMs = Math.round(read.timeoutMs);
        }
        if (has("killAfterMs")) {
            if (!_wholeNumber(read.killAfterMs, 0))
                result.problem = "killAfterMs is not a number of milliseconds, 0 or more";
            else
                result.killAfterMs = Math.round(read.killAfterMs);
        }
        if (has("maxOutputBytes")) {
            if (!_wholeNumber(read.maxOutputBytes, 0))
                result.problem = "maxOutputBytes is not a number, 0 or more";
            else
                result.maxOutputBytes = Math.round(read.maxOutputBytes);
        }
        if (has("keepOutput")) {
            if (typeof read.keepOutput !== "boolean")
                result.problem = "keepOutput is not true or false";
            else
                result.keepOutput = read.keepOutput;
        }
        if (has("outputAfterCancel")) {
            if (typeof read.outputAfterCancel !== "boolean")
                result.problem = "outputAfterCancel is not true or false";
            else
                result.outputAfterCancel = read.outputAfterCancel;
        }
        if (has("endWithShell")) {
            if (typeof read.endWithShell !== "boolean")
                result.problem = "endWithShell is not true or false";
            else
                result.endWithShell = read.endWithShell;
        }
        if (has("environment")) {
            const snapshot = environmentSnapshot(read.environment);
            if (snapshot.problem !== "")
                result.problem = snapshot.problem;
            else
                result.environment = snapshot.environment;
        }
        for (const name of _callbackNames) {
            if (has(name) && typeof read[name] !== "function")
                result.problem = name + " is not a function";
        }
        for (const name of _callbackNames)
            result.callbacks[name] = typeof read[name] === "function" && (result.problem === "" || name === "done") ? read[name] : null;
        return result;
    }

    // An environment as given → { problem, environment }: copied first (each value read
    // once), then the copy checked (environmentProblem); `environment` is the copy, or {}
    // when there is a problem
    function environmentSnapshot(given) {
        let copy = given;
        try {
            if (typeof copy === "object" && copy !== null && !Array.isArray(copy))
                copy = Object.assign({}, copy);
        } catch (error) {
            copy = "unreadable";
        }
        const problem = environmentProblem(copy);
        return { problem: problem, environment: problem === "" && copy !== undefined && copy !== null ? copy : {} };
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
        return _found(tools?.timeout) && _found(tools?.setpriv) && timeoutMs > 0;
    }

    // Whether `setpriv` stands in front of a run (`tools` as for wraps): inside `timeout`
    // (wraps), and for a run that asks to end with the shell (`endWithShell`) whenever
    // `setpriv` was found, with a limit or without. Any other run without a limit is
    // started bare: what it starts may be meant to outlive the shell (a program a launcher
    // opens), and nothing is put around pkexec.
    function guards(tools, timeoutMs, endWithShell) {
        return wraps(tools, timeoutMs) || (endWithShell === true && _found(tools?.setpriv));
    }

    // Whether a run waits for the look-up of `timeout` and `setpriv` before it is started:
    // only one that takes them (a limit, or `endWithShell`). Any other starts at once.
    function waitsForTools(timeoutMs, endWithShell) {
        return timeoutMs > 0 || endWithShell === true;
    }

    function _found(path) {
        return typeof path === "string" && path !== "";
    }

    // The words actually started. With a limit:
    //   timeout -k <kill after> <limit> setpriv --pdeathsig KILL -- <argv…>
    // asked to end with the shell (`endWithShell`) without a limit, or with `timeout` missing:
    //   setpriv --pdeathsig KILL -- <argv…>
    // and any other run as it is.
    // `setpriv` only asks the kernel to send the command a KILL when its parent dies, and
    // then becomes the command. Inside `timeout` that parent is `timeout`, which ends the
    // command at the limit, also when the shell is gone: the shell's own end kills its
    // child, `timeout`, with a KILL that cannot be passed on, and without `setpriv` the
    // command would go on without a limit. Without `timeout` the parent is the shell
    // itself, so a run that asked for it ends with the shell (a crash, a restart) instead
    // of running for ever. (The kernel drops that request when the command is a setuid
    // program, and what the command starts itself does not inherit it.) `timeout` stops
    // reading options at the limit and `setpriv` at "--", so the command's own words are
    // never taken for theirs. A kill-after of 0 would switch `timeout`'s KILL off: 1 ms.
    // Without `setpriv` the command is started as it is.
    function commandLine(argv, tools, timeoutMs, killAfterMs, endWithShell) {
        const words = Array.from(argv);
        if (!guards(tools, timeoutMs, endWithShell))
            return words;
        const guarded = [tools.setpriv, "--pdeathsig", "KILL", "--"].concat(words);
        if (!wraps(tools, timeoutMs))
            return guarded;
        return [tools.timeout, "-k", seconds(Math.max(killAfterMs, 1)), seconds(timeoutMs)].concat(guarded);
    }

    // ---- A run's life ----
    //
    // waiting (for the look-up of `timeout` and `setpriv`, when the run takes them:
    // waitsForTools) → running →
    // ending (told to stop: by cancel() or by the runner's own time limit) → done. A
    // wrapped run is ended by `timeout` itself (its limit, and after a TERM its own KILL);
    // the runner's timers for it are a backstop. `outputAfterCancel`: a cancel does not
    // mute the run — what it still prints is handed over and kept, the answer says
    // `cancelled` all the same.

    function fresh(timeoutMs, killAfterMs, outputAfterCancel, endWithShell) {
        return {
            phase: "waiting", launched: false, wrapped: false, guarded: false, timeoutMs: timeoutMs, killAfterMs: killAfterMs,
            outputAfterCancel: outputAfterCancel === true, endWithShell: endWithShell === true,
            timedOut: false, cancelled: false, exited: false, code: -1, crashed: false
        };
    }

    // → { state, effects, ignored }. `ignored` is "" when the event was taken, else why not
    // (the state is then the object passed in, no effects). Events: launch { wrapped,
    // guarded (`setpriv` in front: guards) },
    // cancel, watchdog (the runner's time limit), kill (its kill timer), exited { code,
    // crashed }, stopped (the process is gone, with or without an exit), and cancel {
    // queued: true } for a run that is done but whose answer still waits to be handed over
    // (a refused run, or a program reported as unable to start inside start()): that answer
    // goes out as cancelled, so a cancel is never followed by `cancelled: false`. Effects, in order:
    // start | timer { name, ms } | stop { name } | signal { signal } | mute (no chunk or
    // line callback from here; left out for a run with `outputAfterCancel`) | answer.
    function step(state, event) {
        const phase = state?.phase;
        const type = event?.type;
        const ignored = why => ({ state: state, effects: [], ignored: why });
        const next = (changes, effects) => ({ state: Object.assign({}, state, changes), effects: effects, ignored: "" });
        if (typeof phase !== "string")
            return ignored("no state");
        const mute = state.outputAfterCancel === true ? [] : [{ type: "mute" }];
        if (phase === "done") {
            if (type !== "cancel" || event.queued !== true)
                return ignored("done");
            return state.cancelled ? ignored("cancelled before") : next({ cancelled: true }, mute);
        }
        const live = phase === "running" || phase === "ending";
        switch (type) {
        case "launch": {
            if (phase !== "waiting")
                return ignored("started before");
            const wrapped = event.wrapped === true && state.timeoutMs > 0;
            const effects = [{ type: "start" }];
            if (state.timeoutMs > 0)
                effects.push({ type: "timer", name: "watchdog", ms: state.timeoutMs + (wrapped ? state.killAfterMs + backstopMs : 0) });
            return next({ phase: "running", launched: true, wrapped: wrapped, guarded: wrapped || (event.guarded === true && state.endWithShell) }, effects);
        }
        case "cancel":
            if (phase === "waiting")
                return next({ phase: "done", cancelled: true }, mute.concat([{ type: "answer" }]));
            if (phase === "ending")
                return state.cancelled ? ignored("cancelled before") : next({ cancelled: true }, mute);
            return next({ phase: "ending", cancelled: true }, mute.concat([
                { type: "stop", name: "watchdog" }, { type: "signal", signal: 15 },
                { type: "timer", name: "kill", ms: state.killAfterMs + (state.wrapped ? backstopMs : 0) }
            ]));
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

    // `state` at the end; `facts`: { stdout, stderr, truncated, durationMs, lastStderr (the
    // last line read on stderr, whether or not the output is kept) }. Frozen.
    //   failedToStart  the process ended without an exit status (Quickshell reports a
    //                  program that cannot start so) — or, inside `timeout`, with 126 or
    //                  127, the two codes it and `setpriv` give for a command not run (a
    //                  command that exits with one of them itself reads the same). Behind
    //                  `setpriv` alone (a run with `endWithShell`) the codes are not
    //                  enough, as a command may well exit with them itself, so there the
    //                  last stderr line must also be setpriv's own ("setpriv: …", its
    //                  name is not translated)
    //   timedOut       the runner's own limit ended it, or `timeout` did: the run took at
    //                  least the limit and ended with 124, or by the KILL that follows
    //   code           the exit status; -1 without one (never started, or ended by a signal)
    function result(state, facts) {
        const code = state.exited && !state.crashed ? state.code : -1;
        const setprivFailed = state.guarded && String(facts.lastStderr ?? "").startsWith("setpriv: ");
        const failedToStart = state.launched
            && (!state.exited || ((state.wrapped || setprivFailed) && !state.cancelled && !state.timedOut && (code === 126 || code === 127)));
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

    // The answer to a run that was never started: what was asked could not be run.
    // `cancelled`: the run was cancelled before that answer was handed over.
    function refusal(problem, cancelled) {
        return Object.freeze({
            ok: false, code: -1, stdout: "", stderr: "", timedOut: false, cancelled: cancelled === true,
            failedToStart: false, truncated: false, durationMs: 0, error: problem
        });
    }
}
