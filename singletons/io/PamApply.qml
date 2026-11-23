import QtQuick
import Quickshell
import qs.singletons

// Apply and Undo of the PAM rules on Arch: one run as administrator per service, the root
// step's files (PamApplyRules.scriptFiles, in scripts/root/) read from the shell's tree at the
// click and their text run by the system's /bin/sh — never run by path. Apply follows a passed trial (the user's click on Apply started both); Undo is a
// click of its own. What may run and what the answer means are PamApplyRules'; this only
// queues the run, reads the service's file again (as the user, scripts/pam-files.sh) when the
// run did not say it was done — a run cut short may still have changed it — and hands the
// outcome over. One run at a time.
//
// `start` is what queues the run: null for the shell's runs as administrator
// (PrivilegedRuns.startShell, which says who asks and what for), and then only the system's
// places (PamApplyRules.livePaths); a suite's stand-in (which runs the same words as the
// user) only with places under a scratch folder outside /etc, /usr and /var
// (PamApplyRules.pathsRefusal).
QtObject {
    id: root

    // After each started run: PamApplyRules.applyReply's outcome; when not ok, its `file`
    // is PamApplyRules.afterFailure's answer for the file read again
    signal finished(var outcome)

    // (request { what, argv }, done(result)) → nothing; done once with PrivilegedRules' result
    property var start: null
    property var paths: PamApplyRules.livePaths
    property string shell: "/bin/sh"
    property var filesCommand: [Quickshell.shellDir + "/scripts/pam-files.sh"]
    // Where the root step's files are (scripts/root/ of the shell's tree), read at each run
    property string scriptsDirectory: Quickshell.shellDir + "/" + RootScriptRules.directory
    readonly property bool busy: _busy

    property bool _busy: false

    // Apply one service's new rules. `request`: PamApplyRules.applyArgv's (service, built,
    // currentText, vendorText, trial). → { started, refusal (null or { code, text }) }
    function apply(request) {
        return _run(PamApplyRules.applyArgv(shell, request, paths, start === null, _scripts.read()), PamApplyRules.what("apply", String(request?.service ?? "")));
    }

    // Put a backup back. `request`: PamApplyRules.undoArgv's (service, backup, currentSha256)
    function undo(request) {
        return _run(PamApplyRules.undoArgv(shell, request, paths, start === null, _scripts.read()), PamApplyRules.what("undo", String(request?.service ?? "")));
    }

    function _run(plan, what) {
        if (_busy)
            return { started: false, refusal: PamApplyRules.refusal("busy") };
        if (plan.refusal !== null)
            return { started: false, refusal: plan.refusal };
        _busy = true;
        const queue = start ?? ((request, done) => PrivilegedRuns.startShell(request, done));
        queue({ what: what, argv: plan.argv }, result => {
            const outcome = PamApplyRules.applyReply(result, plan.expected);
            if (outcome.ok) {
                root._busy = false;
                root.finished(outcome);
                return;
            }
            root._readAgain(plan.expected, outcome);
        });
        return { started: true, refusal: null };
    }

    function _readAgain(expected, outcome) {
        const path = paths.system + "/" + expected.service;
        const lines = [];
        _runner.start(Array.from(filesCommand).concat([path]), {
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
                outcome.file = PamApplyRules.afterFailure(answer, expected);
                root._busy = false;
                root.finished(outcome);
            }
        });
    }

    property CommandRunner _runner: CommandRunner {}
    property RootScriptFiles _scripts: RootScriptFiles {
        names: PamApplyRules.scriptFiles
        directory: root.scriptsDirectory
    }
}
