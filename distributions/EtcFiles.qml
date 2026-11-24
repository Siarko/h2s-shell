import QtQuick
import Quickshell
import qs.singletons
import qs.singletons.io

// Writing system files where /etc is the machine's own (Arch, and any such distribution):
// one run as administrator per change — the user's click started it, polkit asks for the
// password — its root step read from the shell's tree (scripts/root/) at the click and its
// text run by the system's /bin/sh, never run by path; a file read again as the user
// (scripts/pam-files.sh) when the run did not say it was done, since a run cut short may still
// have changed it. One run at a time per EtcFiles.
//
// Two parts:
// - run(job): the run itself, for any root step of the shell's (PAM's, the remembered
//   authorization's): queued, answered once, the files read again after a failure;
// - read / write / remove / undo: the shell's own files of EtcFilesRules.files, one per
//   change kind, each change kept as a backup that Undo puts back (scripts/root/etc-files.sh).
//
// `start` is what queues the run: null for the shell's runs as administrator
// (PrivilegedRuns.startShell, which says who asks and what for), and then only the system's
// places (`base` ""); a suite's stand-in (which runs the same words as the user) only under a
// scratch `base` outside /etc, /usr and /var (EtcFilesRules.baseRefusal).
QtObject {
    id: root

    // (request { what, argv }, done(result)) → nothing; done once with PrivilegedRules' result
    property var start: null
    // The folder the files' places are under: "" for the system's (a suite: a scratch folder)
    property string base: ""
    property string shell: "/bin/sh"
    property var filesCommand: [Quickshell.shellDir + "/scripts/pam-files.sh"]
    // Where the root step's files are (scripts/root/ of the shell's tree), read at each run
    property string scriptsDirectory: Quickshell.shellDir + "/" + RootScriptRules.directory
    readonly property bool busy: _busy

    property bool _busy: false
    // Per kind, the last change this EtcFiles made that Undo can put back (a reply's outcome)
    property var _last: ({})

    // ---- The run ----

    // One root step: `job` { what (the prompt's reason), argv, reply (PrivilegedRules' result
    // → outcome, with `ok`), readBack (the paths to read again when not ok; [] for none),
    // after (answers by path, outcome → nothing: puts what was read into the outcome), done
    // (outcome → nothing, once) } → "" when started, "busy" (one under way) or "start" (it
    // could not be queued: nothing will answer)
    function run(job) {
        if (_busy)
            return "busy";
        _busy = true;
        return _queue(job);
    }

    function _queue(job) {
        const queue = start ?? ((request, done) => PrivilegedRuns.startShell(request, done));
        // The queue's answer is taken once: a second call, or one after the queue threw, is
        // dropped
        let answered = false;
        const finish = outcome => {
            root._busy = false;
            job.done(outcome);
        };
        try {
            queue({ what: job.what, argv: job.argv }, result => {
                if (answered)
                    return;
                answered = true;
                let outcome;
                try {
                    outcome = job.reply(result);
                } catch (error) {
                    console.warn("[EtcFiles] the run's answer could not be read: " + error);
                    outcome = { ok: false, quiet: false, error: "the answer could not be read" };
                }
                const paths = Array.from(job.readBack ?? []);
                if (outcome.ok || paths.length === 0) {
                    finish(outcome);
                    return;
                }
                root._readFiles(paths, answers => {
                    try {
                        job.after?.(answers, outcome);
                    } finally {
                        finish(outcome);
                    }
                });
            });
        } catch (error) {
            console.warn("[EtcFiles] the run could not be started: " + error);
            // Answered before it threw: that answer stands (and was handed over)
            if (answered)
                return "";
            // Nothing will answer: not left busy for good
            answered = true;
            _busy = false;
            return "start";
        }
        return "";
    }

    // The files as the user reads them → answers by path (PamStackRules.filesAnswer's)
    function _readFiles(paths, done) {
        const lines = [];
        _runner.start(Array.from(filesCommand).concat(paths), {
            timeoutMs: 6000,
            killAfterMs: 1000,
            maxOutputBytes: 1048576,
            keepOutput: false,
            onLine: (line, stream) => {
                if (stream === "stdout")
                    lines.push(line);
            },
            done: result => done(PamStackRules.filesAnswer(lines, result, paths).answers)
        });
    }

    // ---- The shell's own files ----

    // The kind's file as it is now, read as the user → done(EtcFilesRules.inForce's answer);
    // always answered later, once; "unknown" for a kind it does not know
    function read(kind, done) {
        if (!EtcFilesRules.knows(kind)) {
            Qt.callLater(() => done(EtcFilesRules.inForce(null, kind)));
            return;
        }
        const path = EtcFilesRules.fileOf(kind, base);
        // A runner of its own per read: reads may overlap a run's
        const runner = _runnerComponent.createObject(root);
        const lines = [];
        runner.start(Array.from(filesCommand).concat([path]), {
            timeoutMs: 6000,
            killAfterMs: 1000,
            maxOutputBytes: 1048576,
            keepOutput: false,
            onLine: (line, stream) => {
                if (stream === "stdout")
                    lines.push(line);
            },
            done: result => {
                const answer = PamStackRules.filesAnswer(lines, result, [path]).answers[path];
                Qt.callLater(() => runner.destroy());
                done(EtcFilesRules.inForce(answer, kind));
            }
        });
    }

    // Write `text` as the kind's file. `handlers` { current (read's answer the user saw, its
    // text deciding; left out: read now), replace (true: replace a file that is not exactly
    // the shell's, the user told),
    // done (outcome → nothing: EtcFilesRules.reply's, with `file` afterFailure's when not ok,
    // or a refusal found after the read { ok: false, refused, error }) } → { started,
    // refusal (null or { code, text }) }
    function write(kind, text, handlers) {
        return _change("write", { kind, text, replace: handlers?.replace === true }, handlers);
    }

    // Remove the kind's file (the system's own setting in force again). `handlers` as write's
    function remove(kind, handlers) {
        return _change("remove", { kind, replace: handlers?.replace === true }, handlers);
    }

    // Put back what the kind's file was before a change. `handlers` { from (the outcome of the
    // change undone; left out: this EtcFiles' last one of the kind), done } → as write
    function undo(kind, handlers) {
        if (_busy)
            return { started: false, refusal: EtcFilesRules.refusal("busy") };
        const from = handlers?.from ?? _last[kind] ?? null;
        const plan = EtcFilesRules.undoArgv(shell, { kind, from }, base, start === null, _scripts.read());
        if (plan.refusal !== null)
            return { started: false, refusal: plan.refusal };
        _busy = true;
        return _launch(plan, kind, handlers?.done);
    }

    function _change(mode, request, handlers) {
        if (_busy)
            return { started: false, refusal: EtcFilesRules.refusal("busy") };
        const scripts = _scripts.read();
        const plan = request => mode === "remove" ? EtcFilesRules.removeArgv(shell, request, base, start === null, scripts)
                                                  : EtcFilesRules.writeArgv(shell, request, base, start === null, scripts);
        // What can be refused before the file is read, with a stand-in for it
        const early = plan(Object.assign({}, request, { current: { state: "absent", sha256: "absent" } }));
        if (early.refusal !== null && ["arguments", "kind", "paths", "script", "text"].includes(early.refusal.code))
            return { started: false, refusal: early.refusal };
        const done = handlers?.done;
        if (handlers?.current !== undefined) {
            const given = plan(Object.assign({}, request, { current: handlers.current }));
            if (given.refusal !== null)
                return { started: false, refusal: given.refusal };
            _busy = true;
            return _launch(given, request.kind, done);
        }
        _busy = true;
        read(request.kind, current => {
            const planned = plan(Object.assign({}, request, { current }));
            if (planned.refusal !== null) {
                root._busy = false;
                done?.({ ok: false, quiet: false, mode, kind: request.kind, refused: planned.refusal.code, error: planned.refusal.text,
                         file: "unchanged", current });
                return;
            }
            const outcome = root._launch(planned, request.kind, done);
            if (!outcome.started)
                done?.({ ok: false, quiet: false, mode, kind: request.kind, refused: outcome.refusal.code, error: outcome.refusal.text,
                         file: "unchanged", current });
        });
        return { started: true, refusal: null };
    }

    // The run of a plan, `_busy` already set
    function _launch(plan, kind, done) {
        const path = EtcFilesRules.fileOf(kind, base);
        const code = _queue({
            what: EtcFilesRules.what(plan.expected.mode, kind),
            argv: plan.argv,
            reply: result => EtcFilesRules.reply(result, plan.expected),
            readBack: [path],
            after: (answers, outcome) => outcome.file = EtcFilesRules.afterFailure(EtcFilesRules.inForce(answers[path], kind), plan.expected),
            done: outcome => {
                if (outcome.ok) {
                    const last = Object.assign({}, root._last);
                    last[kind] = outcome;
                    root._last = last;
                }
                done?.(outcome);
            }
        });
        if (code !== "")
            return { started: false, refusal: EtcFilesRules.refusal(code) };
        return { started: true, refusal: null };
    }

    property CommandRunner _runner: CommandRunner {}
    property Component _runnerComponent: Component {
        CommandRunner {}
    }
    property RootScriptFiles _scripts: RootScriptFiles {
        names: EtcFilesRules.scriptFiles
        directory: root.scriptsDirectory
    }
}
