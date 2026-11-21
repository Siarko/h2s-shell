pragma Singleton

import Quickshell
import QtQuick

// The decisions of running a command as administrator (singletons/PrivilegedRuns.qml, the
// one queue; a module's `module.privileged`, api/ModuleHandle.qml; the old
// api/PrivilegedAction.qml) — pure, so tests/PrivilegedRulesTest.qml checks them without a
// process: what a run is asked with, why one is refused before pkexec runs, the words handed
// to pkexec, where pkexec is, the answer, and the queue's life (queueStep).
Singleton {
    id: root

    // A run's time limit (options.timeoutMs) must lie in this range: 1 s to 1 h. It is kept
    // by the `timeout` inside pkexec, so it starts when the command starts as root: the wait
    // for the password is not part of it
    readonly property int minTimeoutMs: 1000
    readonly property int maxTimeoutMs: 3600000
    // How long after TERM the command gets KILL: `timeout -k` inside pkexec, and how long a
    // cancelled run may take to exit before the next run may start
    readonly property int killAfterMs: 3000
    // With the shell's own polkit agent: how long a started run keeps the head of the queue
    // when no password request comes (no request: a polkit rule let it run, or it was never
    // going to ask)
    readonly property int headQuietMs: 2000
    // With another agent the shell sees no request: a run keeps the head until it ends, at
    // most this long
    readonly property int headStrictMs: 120000
    // `what` is kept to this many characters (the prompt cuts it shorter where it shows it)
    readonly property int whatMaxLength: 200
    readonly property var blockedReasons: ["locked", "no-purpose", "unprintable", "undeclared"]

    // Where the shell looks for pkexec: NixOS's setuid wrappers first (the store's copy is
    // not setuid and cannot work), then the system's directories (Arch: /usr/bin)
    readonly property string pkexecSearchPath: "/run/wrappers/bin:" + ModuleRules.probeToolPath

    readonly property var _callbackNames: ["onStdout", "onStderr", "onLine", "done"]

    // ---- Text ----

    // Unicode's control (Cc) and format (Cf) characters, its line and paragraph separators
    // (Zl, Zp: U+2028, U+2029, which Qt breaks a line at even in plain text), and lone
    // surrogates: what cannot be shown as it is (a line break, a right-to-left override, a
    // zero-width joiner)
    function unprintableCode(code) {
        if (code <= 0x1f || (code >= 0x7f && code <= 0x9f))
            return true;
        if (code >= 0xd800 && code <= 0xdfff)
            return true;
        const ranges = [
            [0x00ad, 0x00ad], [0x0600, 0x0605], [0x061c, 0x061c], [0x06dd, 0x06dd], [0x070f, 0x070f],
            [0x0890, 0x0891], [0x08e2, 0x08e2], [0x180e, 0x180e], [0x200b, 0x200f], [0x2028, 0x202e],
            [0x2060, 0x2064], [0x2066, 0x206f], [0xfeff, 0xfeff], [0xfff9, 0xfffb], [0x110bd, 0x110bd],
            [0x110cd, 0x110cd], [0x13430, 0x1343f], [0x1bca0, 0x1bca3], [0x1d173, 0x1d17a],
            [0xe0001, 0xe0001], [0xe0020, 0xe007f]
        ];
        return ranges.some(range => code >= range[0] && code <= range[1]);
    }

    // A text's characters by code point, a surrogate pair kept whole (Array.from splits
    // one in this engine). Not a string: none
    function characters(text) {
        if (typeof text !== "string")
            return [];
        const result = [];
        for (let i = 0; i < text.length; i++) {
            const code = text.charCodeAt(i);
            if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length) {
                const next = text.charCodeAt(i + 1);
                if (next >= 0xdc00 && next <= 0xdfff) {
                    result.push(text.substr(i, 2));
                    i++;
                    continue;
                }
            }
            result.push(text[i]);
        }
        return result;
    }

    // Whether a text holds a control, format or separator character
    function unprintable(text) {
        for (const character of String(text))
            if (unprintableCode(character.codePointAt(0)))
                return true;
        return false;
    }

    // `what`, cleaned: white space folded to single spaces, control and format characters
    // dropped, trimmed, at most whatMaxLength characters. Not a string: ""
    function cleanWhat(value) {
        if (typeof value !== "string")
            return "";
        const kept = characters(value.replace(/\s+/g, " "))
            .filter(character => !unprintableCode(character.codePointAt(0))).join("");
        // By code point: an emoji counts once and is never cut in half
        return characters(kept.trim()).slice(0, whatMaxLength).join("").trim();
    }

    // ---- What a run is asked with ----

    // → { problem, what (cleaned), timeoutMs, notifyFailures, environment, callbacks }, every
    // field read once (CommandRules.readOnce): what is checked is what is used. `callbacks`:
    // { onStdout, onStderr, onLine, done } as read, each a function or null — `done` even when
    // `problem` is set, as an answer is owed. `problem` is "" when every option given is of
    // its kind and the two needed ones are there; `what` may still be empty (refusal:
    // "no-purpose"). `environment` (API 1.14, CommandRunner's shape, a plain copy) is taken
    // only in module test mode (`testMode`), for the stand-in pkexec and the command it runs:
    // outside it a run never takes an environment its module chose, and one given is a problem
    function options(given, testMode) {
        const result = { problem: "", what: "", timeoutMs: 0, notifyFailures: true, environment: {},
                         callbacks: { onStdout: null, onStderr: null, onLine: null, done: null } };
        if (given === undefined || given === null || typeof given !== "object" || Array.isArray(given)) {
            result.problem = "the options are not an object (what and timeoutMs are needed)";
            return result;
        }
        const read = CommandRules.readOnce(given, ["what", "timeoutMs", "notifyFailures", "environment"].concat(_callbackNames));
        result.what = cleanWhat(read.what);
        const limit = read.timeoutMs;
        if (typeof limit !== "number" || !isFinite(limit))
            result.problem = "timeoutMs is needed: the run's time limit, " + minTimeoutMs + " to " + maxTimeoutMs + " ms";
        else if (limit < minTimeoutMs || limit > maxTimeoutMs)
            result.problem = "timeoutMs must be " + minTimeoutMs + " to " + maxTimeoutMs + " ms (1 s to 1 h)";
        else
            result.timeoutMs = Math.round(limit);
        const notify = read.notifyFailures;
        if (notify !== undefined && notify !== null) {
            if (typeof notify !== "boolean")
                result.problem = "notifyFailures is not true or false";
            else
                result.notifyFailures = notify;
        }
        if (read.environment !== undefined && read.environment !== null) {
            if (testMode !== true) {
                result.problem = "environment is taken in module test mode only";
            } else {
                const snapshot = CommandRules.environmentSnapshot(read.environment);
                if (snapshot.problem !== "")
                    result.problem = snapshot.problem;
                else
                    result.environment = snapshot.environment;
            }
        }
        for (const name of _callbackNames) {
            if (read[name] !== undefined && read[name] !== null && typeof read[name] !== "function")
                result.problem = name + " is not a function";
        }
        for (const name of _callbackNames)
            result.callbacks[name] = typeof read[name] === "function" && (result.problem === "" || name === "done") ? read[name] : null;
        return result;
    }

    // ---- The manifest's declaration (module API 1.36) ----

    // What a module may run as administrator, from its manifest's `privileged` block
    // (ModuleManifestRules.readPrivileged: { why, programs } or null), the user's
    // acknowledgements (ModuleInstallRules.needsConfirmation's list: undefined while none is
    // recorded — every module found counts as acknowledged as it is), its id, and its programs
    // as its handle has them ({ <name>: { path } }; null: not looked at).
    // → { problem: "" | why nothing may run, paths: [the declared programs' absolute paths] }
    //   no block: refused; a list that is no object, or an acknowledgement for the id that does
    //   not say privileged: true: refused (not approved); else the paths of the declared
    //   programs that were found and are trusted (module.programs' `trusted`).
    // A guard against a module's mistakes and a statement for the user, not a sandbox: a
    // module runs in the shell's process and can start programs by other means.
    function declaration(privileged, acknowledgements, moduleId, programs) {
        const none = problem => ({ problem: problem, paths: [] });
        if (!ModuleRules.isObject(privileged) || !Array.isArray(privileged.programs))
            return none("asks for administrator rights; module.json does not declare it (privileged)");
        if (acknowledgements !== undefined) {
            const list = ModuleRules.isObject(acknowledgements) ? acknowledgements : {};
            const given = typeof moduleId === "string" && ModuleRules.has(list, moduleId) ? list[moduleId] : null;
            if (!ModuleRules.isObject(given) || given.privileged !== true)
                return none("asks for administrator rights; the user has not approved its declaration");
        }
        // Only a program only root can change: one the user can write, run as root, would let
        // any of the user's processes become root
        const paths = [];
        for (const name of privileged.programs) {
            const verdict = ModuleRules.isObject(programs) && typeof name === "string" && ModuleRules.has(programs, name) ? programs[name] : null;
            const path = verdict?.path;
            if (verdict?.trusted === true && typeof path === "string" && path.startsWith("/") && !paths.includes(path))
                paths.push(path);
        }
        return { problem: "", paths: paths };
    }

    // Why `program` (a run's argv[0]) may not run as administrator under `declared`
    // (declaration()'s answer; anything else: nothing declared) — "" when it may
    function declaredProblem(declared, program) {
        if (!ModuleRules.isObject(declared) || typeof declared.problem !== "string" || !Array.isArray(declared.paths))
            return "asks for administrator rights; module.json does not declare it (privileged)";
        if (declared.problem !== "")
            return declared.problem;
        if (typeof program !== "string" || !declared.paths.includes(program))
            return "runs " + JSON.stringify(String(program).slice(0, 200)) + " as administrator; module.json's privileged.programs does not name it";
        return "";
    }

    // The old PrivilegedAction's run (1.36): `moduleId` the module whose code is on the call's
    // stack ("" when none is seen), `declared` its declaration(), `program` the command's
    // first word. "" when it may go on. A run the shell cannot trace to a module is refused:
    // nothing would say who asks
    function legacyDeclarationProblem(moduleId, declared, program) {
        if (typeof moduleId !== "string" || moduleId === "")
            return "a run as administrator from code the shell cannot trace to a module is refused";
        return declaredProblem(declared, program);
    }

    // Why a run is refused before pkexec runs, or null when it may be queued. These checks
    // catch a module's mistakes and keep the command printable as it is (no word it could
    // not show), with a purpose, and argv[0] a path, never a name that root's PATH would
    // resolve. They do not stop a hostile module: modules run in the shell's process and
    // could start pkexec themselves. Against a module that is not the project's, the user's
    // protection is the password prompt and knowing what they install. Whether argv[0] is
    // trusted (module.programs[name].trusted) is not checked: the module must pass only a
    // trusted program.
    // `request`:
    //   argv (the caller's copy, CommandRules.argvSnapshot's `words`: what is judged here is
    //   what runs), options (options() of what was given), active (the module is on), locked (the
    //   session), available and unavailableReason (module.privileged's), declaration
    //   (declaration()'s answer; missing: nothing declared)
    // → { blocked ("" | a blockedReasons word), notFound (bool), error }. In this order: what
    // was asked wrongly (error), a program that cannot be found (notFound: argv[0] is "", the
    // path a missing program has, or not an absolute path), the module off, nothing declared,
    // not approved, or argv[0] not among the declared programs (undeclared), the session
    // locked, no purpose, a word that cannot be shown, pkexec or timeout missing (error).
    // Whether argv[0] is there and an executable file is looked at when the run's turn comes
    // (the queue's "checking": notFound).
    function refusal(request) {
        const refuse = (blocked, error, notFound) => ({ blocked: blocked, notFound: notFound === true, error: error });
        const options = request?.options ?? { problem: "the options are not an object" };
        if (options.problem)
            return refuse("", options.problem);
        const argv = request.argv;
        const problem = CommandRules.argvProblem(argv);
        if (problem !== "" && Array.isArray(argv) && argv.length > 0 && argv[0] === ""
                && CommandRules.argvProblem(["x"].concat(argv.slice(1))) === "")
            return refuse("", "the program was not found", true);
        if (problem !== "")
            return refuse("", problem);
        if (!argv[0].startsWith("/"))
            return refuse("", ModuleRules.show(argv[0].slice(0, 200)) + " is not an absolute path (a program's path, as module.programs has it)", true);
        if (request.active !== true)
            return refuse("", "the module is off");
        const undeclared = declaredProblem(request.declaration, argv[0]);
        if (undeclared !== "")
            return refuse("undeclared", undeclared);
        if (request.locked === true)
            return refuse("locked", "the session is locked");
        if (options.what === "")
            return refuse("no-purpose", "what is empty: a few words saying what the run does are needed");
        for (let i = 0; i < argv.length; i++) {
            if (unprintable(argv[i]))
                return refuse("unprintable", "word " + (i + 1) + " of the command holds a control, format or line separator character, so it could not be shown as it is");
        }
        if (request.available !== true)
            return refuse("", String(request.unavailableReason || "running as administrator is not available"));
        return null;
    }

    // ---- What runs ----

    // The words handed to pkexec's caller:
    //   <pkexec> <timeout> -k <kill after> <limit> <argv…>
    // The shell's own trusted `timeout` runs inside pkexec, as root: it ends the command at
    // its limit (TERM, KILL `killAfterMs` later) whatever happens to the shell — gone, or
    // cancel() called once the command runs as root, when the shell can no longer signal
    // it. Nothing is put around pkexec itself: `setpriv --pdeathsig`, which the plain runs
    // use, is dropped by the kernel at the exec of a setuid program. pkexec needs absolute
    // paths, and `timeout` stops reading options at the limit, so the command's own words
    // are never taken for its.
    function pkexecArgv(pkexec, timeout, timeoutMs, killAfter, argv) {
        return [String(pkexec), String(timeout), "-k", CommandRules.seconds(Math.max(killAfter, 1)), CommandRules.seconds(timeoutMs)]
            .concat(Array.from(argv));
    }

    // A real file's mode (octal text, as the probe prints it) with the setuid bit, owned by
    // root
    function setuidRoot(verdict) {
        const mode = typeof verdict?.mode === "string" && /^[0-7]{1,5}$/.test(verdict.mode) ? parseInt(verdict.mode, 8) : -1;
        return verdict?.owner === "0" && mode >= 0 && (mode & 0o4000) !== 0;
    }

    // The program look-up's lines (ModuleRules.programProbeScript, "all", on
    // pkexecSearchPath, for "pkexec") → { path, reason }: the first match that is trusted
    // (ModuleRules.programVerdict) and setuid root; path "" and why, when none is
    function pkexecChoice(lines) {
        const probe = ModuleRules.programProbe(lines, ["pkexec"]);
        if (!probe.answered.includes("pkexec"))
            return { path: "", reason: "the look-up for pkexec did not answer" };
        const verdicts = probe.names.pkexec.map(candidate => ModuleRules.programVerdict(candidate, probe.user));
        if (verdicts.length === 0)
            return { path: "", reason: "pkexec is not installed" };
        const chosen = verdicts.find(verdict => verdict.trusted && setuidRoot(verdict));
        if (chosen)
            return { path: chosen.path, reason: "" };
        const trusted = verdicts.find(verdict => verdict.trusted);
        return { path: "", reason: trusted ? "pkexec (" + trusted.path + ") is not setuid root" : "no pkexec that only root can change" };
    }

    // module.privileged's `available`: → { available, reason, pkexec, timeout }. `facts`:
    //   testMode, standIn (the module's <testPrograms>/pkexec, "" none), pkexecKnown, pkexec,
    //   pkexecReason (PrivilegedRuns' look-up), timeoutKnown, timeout (CommandTools')
    // In module test mode pkexec is the module's stand-in and nothing else, never one on PATH.
    function availability(facts) {
        const no = reason => ({ available: false, reason: reason, pkexec: "", timeout: "" });
        let pkexec = "";
        if (facts?.testMode === true) {
            if (typeof facts.standIn !== "string" || facts.standIn === "")
                return no("test mode: the module has no stand-in pkexec (pkexec among its programs, in its testPrograms)");
            pkexec = facts.standIn;
        } else {
            if (facts?.pkexecKnown !== true)
                return no("pkexec is still being looked for");
            if (typeof facts.pkexec !== "string" || facts.pkexec === "")
                return no(String(facts.pkexecReason || "no pkexec found"));
            pkexec = facts.pkexec;
        }
        if (facts.timeoutKnown !== true)
            return no("timeout is still being looked for");
        if (typeof facts.timeout !== "string" || facts.timeout === "")
            return no("no trusted timeout (coreutils) on PATH: a run as administrator needs it to end at its limit");
        return { available: true, reason: "", pkexec: pkexec, timeout: facts.timeout };
    }

    // Whether the shell's own prompt answers polkit's requests (PolkitRules.state): then
    // the shell sees a request begin and end
    function shellAnswers(agentState) {
        return agentState === "active" || agentState === "conflict";
    }

    // The notification sent just before a run's pkexec starts, when the shell's own prompt
    // does not answer (`shellAgent` false: another agent, none, or not known yet) and so
    // cannot say who asks: who runs what, from the run's announcement
    // (PolkitRules.announcement: "Module: …", "Authorization: …", "" for an old run), as
    // plain text. Not whether a password is wanted: the shell cannot know if that agent will
    // ask. → { summary, options } for Notifier.send, or null (the shell's prompt answers, or
    // no announcement)
    function launchNotice(announcement, shellAgent) {
        if (shellAgent === true || typeof announcement?.summary !== "string" || announcement.summary === "")
            return null;
        return { summary: announcement.summary, options: { body: String(announcement.body ?? ""), format: "plain" } };
    }

    // ---- The old PrivilegedAction ----

    // Whether a PrivilegedAction's elevating words name pkexec by its bare name ("pkexec",
    // its default) outside module test mode: then the shell's trusted, setuid pkexec
    // (PrivilegedRuns.pkexec) runs in its place, never one that PATH finds first. In test
    // mode the elevating program is the test-mode gate's, untouched.
    function legacySystemPkexec(elevating, testMode) {
        return testMode !== true && Array.isArray(elevating) && elevating[0] === "pkexec";
    }

    // Whether a PrivilegedAction's run, its program looked at, waits before its turn may go
    // on to pkexec: it names the trusted pkexec (`systemPkexec`, legacySystemPkexec) and the
    // look-up of that pkexec (PrivilegedRuns) has not answered. It waits still in the check
    // step, so a lock ends it like any run being checked, no deadline of the head runs, and
    // which agent answers is read once it goes on. The look-up has a time limit of its own.
    function legacyCheckWaits(systemPkexec, known) {
        return systemPkexec === true && known !== true;
    }

    // The words a PrivilegedAction's run starts with. `argv`: the elevating words, then the
    // command; `systemPkexec` (legacySystemPkexec); `known`, `pkexec`, `reason`: the look-up
    // of the trusted pkexec (PrivilegedRuns). → { argv, problem (not available: the run
    // fails, nothing started) }. The look-up not answered is a problem too: a run never
    // starts a pkexec that was not looked for (the wait is legacyCheckWaits', before this).
    function legacyLaunch(argv, systemPkexec, known, pkexec, reason) {
        if (systemPkexec !== true)
            return { argv: Array.from(argv), problem: "" };
        if (known !== true)
            return { argv: [], problem: "running as administrator is not available: pkexec is still being looked for" };
        if (typeof pkexec !== "string" || pkexec === "")
            return { argv: [], problem: "running as administrator is not available: " + String(reason || "no pkexec found") };
        return { argv: [pkexec].concat(Array.from(argv).slice(1)), problem: "" };
    }

    // ---- The answer ----

    function _result(fields) {
        return Object.freeze(Object.assign({
            ok: false, code: -1, stdout: "", stderr: "", dismissed: false, refused: false, notFound: false,
            timedOut: false, cancelled: false, blocked: "", error: ""
        }, fields));
    }

    // A refusal (refusal()) as the answer. A run refused for the lock is `dismissed` too:
    // nothing asked, the user clicks again once unlocked
    function refusedResult(refused) {
        return _result({ blocked: refused.blocked ?? "", dismissed: refused.blocked === "locked",
                         notFound: refused.notFound === true, error: String(refused.error ?? "") });
    }

    function lockedResult() {
        return refusedResult({ blocked: "locked", error: "the session is locked" });
    }

    function notFoundResult(program) {
        return _result({ notFound: true, error: String(program).slice(0, 200) + " is not there, or not an executable file" });
    }

    function cancelledResult() {
        return _result({ cancelled: true });
    }

    // A run that pkexec started, from the command runner's result (`run`) and the run's limit:
    //   dismissed  pkexec exited 126: the prompt dismissed or the password not accepted
    //   refused    pkexec exited 127: not authorised, or no agent answered
    //   timedOut   the shell's `timeout` ended it (124; 137 after its KILL) after at least the
    //              limit
    // A command that itself exits 124, 126, 127 or 137 reads the same (pkexec and `timeout`
    // pass the command's status through), and so does `timeout`'s own status: 125 (it
    // failed: a plain failure), 126 (the command could not be run: read as dismissed), 127
    // (the command not found: read as refused). The status alone cannot tell them apart;
    // the program is looked at just before pkexec starts (the queue's "checking"), so the
    // last is rare.
    function runResult(run, timeoutMs) {
        const code = typeof run?.code === "number" ? run.code : -1;
        const cancelled = run?.cancelled === true;
        const timedOut = !cancelled && (code === 124 || code === 137) && (run?.durationMs ?? 0) >= timeoutMs;
        return _result({
            ok: run?.ok === true && code === 0 && !cancelled,
            code: code,
            stdout: String(run?.stdout ?? ""),
            stderr: String(run?.stderr ?? ""),
            dismissed: !cancelled && code === 126,
            refused: !cancelled && code === 127,
            timedOut: timedOut,
            cancelled: cancelled,
            error: run?.failedToStart === true ? "pkexec could not be started" : String(run?.error ?? "")
        });
    }

    // The "<what> failed" notification for a result, or null: a run that did not succeed and
    // was not dismissed, refused (the polkit agent tells that: Authentication.reportDenied),
    // cancelled or blocked. `queued`: the run was taken into the queue; one refused before
    // (asked wrongly: the module's mistake, said in its result) is told only when its
    // program was not found, which the user can mend
    function failureNotice(result, what, timeoutMs, queued) {
        if (!result || result.ok || result.dismissed || result.refused || result.cancelled || result.blocked !== "")
            return null;
        if (queued !== true && !result.notFound)
            return null;
        const lastLine = String(result.stderr ?? "").split("\n").map(line => line.trim()).filter(line => line !== "").pop() ?? "";
        const body = result.timedOut ? "It did not end within " + CommandRules.seconds(timeoutMs) + " s"
            : result.error !== "" ? result.error
            : lastLine !== "" ? lastLine.slice(0, 300)
            : "Exit code " + result.code;
        return { summary: String(what) + " failed", body: body };
    }

    // ---- The queue ----
    //
    // One queue for the whole shell: only one password question at a time. A run, once
    // queued, goes
    //   waiting → checking (its program looked at: there, an executable file) → asking
    //   (pkexec started; its question can still come) → running (it may still run; the next
    //   one may ask) → gone (answered)
    // and when cancelled after it started, through "ending" (TERM sent; answered when it
    // exits, or `killAfterMs` later — after a KILL a process run as root may still be
    // there). The HEAD is the run checking or asking, or one ending that was asking
    // (`holds`): while there is one, no other run starts. The head lets go
    //   - with the shell's prompt (shellAgent): when its own polkit request (the one
    //     PolkitRules.announces ties to it) was seen and no request is open any more, or
    //     after headQuietMs with none. The agent shows one request at a time, so the head's
    //     own may wait behind another program's: while another request is open before its
    //     own was seen, the headQuietMs wait does not run (it starts again when that request
    //     ends), up to headStrictMs from the launch; once its own was seen, another request
    //     shown after it keeps the head until that one ends too, again up to headStrictMs
    //     from the launch. Only its own open request holds it without a bound;
    //   - with another agent: when it ends, or after headStrictMs;
    //   - when it exits, or (ending) when it exits or killAfterMs has passed: so a
    //     cancelled run's request, still on its way, is never shown with the next run.
    // Locked: no run starts, and those waiting or checking are answered "locked". A run's
    // owner gone (the module turned off, a PrivilegedAction destroyed): its runs leave, and
    // the started ones are cancelled, with no answer at all.
    //
    // state = { locked, jobs: [{ id, owner, phase, holds, shellAgent, requestSeen,
    // otherOpen (another request open before its own was seen), launchedAt (ms), deadline
    // (ms; 0: none), silent }] }, in the order they were queued.

    function queueStart(locked) {
        return { locked: locked === true, jobs: [] };
    }

    // The run holding the head, or null
    function queueHead(state) {
        return (state?.jobs ?? []).find(job => job.phase === "checking" || job.phase === "asking"
                                        || (job.phase === "ending" && job.holds)) ?? null;
    }

    // The earliest deadline of a run (ms), 0 when none has one: when to send "tick"
    function nextDeadline(state) {
        let next = 0;
        for (const job of state?.jobs ?? []) {
            if (job.deadline > 0 && (next === 0 || job.deadline < next))
                next = job.deadline;
        }
        return next;
    }

    // → { state, effects }. Every event has `now` (ms, on a monotonic clock: PrivilegedRuns
    // takes Quickshell's ElapsedTimer, never the wall clock). Events:
    //   add { id, owner }             a run asked for (refusals were made before)
    //   checked { id, found, shellAgent }   its program was looked at; which agent answers
    //   request { open, own }         a request is open now (any program's), and whether it
    //                                 is the head's own (PolkitRules.announces)
    //   tick                          a deadline may have passed
    //   exited { id }                 its pkexec is gone (the runner answered)
    //   cancel { id, killAfterMs }    cancel() was called
    //   ownerGone { owner, killAfterMs }   the module turned off, the owner destroyed
    //   lock { locked }               the session locked or unlocked
    // Effects, in order: check { id } (look at its program) | launch { id } (start pkexec) |
    // signal { id } (cancel the started process) | answer { id, kind: "result" |
    // "cancelled" | "locked" | "notFound" } | forget { id } (drop it: no answer at all).
    function queueStep(state, event) {
        const jobs = (state?.jobs ?? []).map(job => Object.assign({}, job));
        let locked = state?.locked === true;
        const effects = [];
        const now = typeof event?.now === "number" ? event.now : 0;
        const killAfter = typeof event?.killAfterMs === "number" && event.killAfterMs >= 0 ? event.killAfterMs : killAfterMs;
        const find = id => jobs.find(job => job.id === id) ?? null;
        const end = (job, kind) => {
            jobs.splice(jobs.indexOf(job), 1);
            effects.push(job.silent ? { type: "forget", id: job.id } : { type: "answer", id: job.id, kind: kind });
        };
        const stop = job => {
            job.holds = job.phase === "asking";
            job.phase = "ending";
            job.deadline = now + killAfter;
            effects.push({ type: "signal", id: job.id });
        };
        switch (event?.type) {
        case "add":
            if (find(event.id))
                break;
            if (locked) {
                effects.push({ type: "answer", id: event.id, kind: "locked" });
                break;
            }
            jobs.push({ id: event.id, owner: event.owner ?? "", phase: "waiting", holds: false, shellAgent: false,
                        requestSeen: false, otherOpen: false, launchedAt: 0, deadline: 0, silent: false });
            break;
        case "checked": {
            const job = find(event.id);
            if (!job || job.phase !== "checking")
                break;
            if (event.found !== true) {
                end(job, "notFound");
                break;
            }
            job.phase = "asking";
            job.shellAgent = event.shellAgent === true;
            job.requestSeen = false;
            job.otherOpen = false;
            job.launchedAt = now;
            job.deadline = now + (job.shellAgent ? headQuietMs : headStrictMs);
            effects.push({ type: "launch", id: job.id });
            break;
        }
        case "request": {
            const head = queueHead({ jobs: jobs });
            if (!head || head.phase !== "asking" || !head.shellAgent)
                break;
            const open = event.open === true || event.own === true;
            if (head.requestSeen) {
                // Its own seen: held while any request is open, let go when none is. Its own
                // open request holds without a bound (the user is answering it); another
                // one — or one it cannot be told from (the flow replaced) — at most
                // headStrictMs from the launch, as before its own was seen
                if (!open) {
                    head.phase = "running";
                    head.deadline = 0;
                } else {
                    head.deadline = event.own === true ? 0 : head.launchedAt + headStrictMs;
                }
            } else if (event.own === true) {
                head.requestSeen = true;
                head.otherOpen = false;
                head.deadline = 0;
            } else if (open) {
                // Another program's in front: its own may wait behind it
                head.otherOpen = true;
                head.deadline = head.launchedAt + headStrictMs;
            } else if (head.otherOpen) {
                head.otherOpen = false;
                head.deadline = Math.min(now + headQuietMs, head.launchedAt + headStrictMs);
            }
            break;
        }
        case "tick":
            for (const job of jobs.slice()) {
                if (job.deadline <= 0 || now < job.deadline)
                    continue;
                if (job.phase === "asking") {
                    job.phase = "running";
                    job.deadline = 0;
                } else if (job.phase === "ending") {
                    end(job, "cancelled");
                }
            }
            break;
        case "exited": {
            const job = find(event.id);
            if (!job)
                break;
            if (job.phase === "asking" || job.phase === "running")
                end(job, "result");
            else if (job.phase === "ending")
                end(job, "cancelled");
            break;
        }
        case "cancel": {
            const job = find(event.id);
            if (!job)
                break;
            if (job.phase === "waiting" || job.phase === "checking")
                end(job, "cancelled");
            else if (job.phase === "asking" || job.phase === "running")
                stop(job);
            break;
        }
        case "ownerGone":
            for (const job of jobs.slice()) {
                if (job.owner !== event.owner || event.owner === undefined || event.owner === "")
                    continue;
                job.silent = true;
                if (job.phase === "waiting" || job.phase === "checking")
                    end(job, "");
                else if (job.phase === "asking" || job.phase === "running")
                    stop(job);
            }
            break;
        case "lock":
            locked = event.locked === true;
            if (locked) {
                for (const job of jobs.slice()) {
                    if (job.phase === "waiting" || job.phase === "checking")
                        end(job, "locked");
                }
            }
            break;
        }
        if (!locked && queueHead({ jobs: jobs }) === null) {
            const next = jobs.find(job => job.phase === "waiting");
            if (next) {
                next.phase = "checking";
                effects.push({ type: "check", id: next.id });
            }
        }
        return { state: { locked: locked, jobs: jobs }, effects: effects };
    }
}
