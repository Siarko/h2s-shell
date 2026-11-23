import QtQuick
import Quickshell
import qs.singletons

// Install, Remove and Undo of the remembered administrator authorization on Arch: one run as
// administrator each, the fixed script RememberInstallRules.applyScript run by the system's
// /bin/sh — nothing is loaded from a file. Each is a click of its own. What may run and what
// the answer means are RememberInstallRules'; this only queues the run, reads the two files
// again (as the user, scripts/pam-files.sh) when the run did not say it was done — a run cut
// short may still have changed them — and hands the outcome over. One run at a time.
//
// `start` is what queues the run: null for the shell's runs as administrator
// (PrivilegedRuns.startShell, which says who asks and what for), and then only the system's
// places (RememberInstallRules.livePaths); a suite's stand-in (which runs the same words as
// the user) only with places outside /etc, /usr and /var (RememberInstallRules.pathsRefusal).
QtObject {
    id: root

    // After each started run: RememberInstallRules.reply's outcome; when not ok, its `files`
    // is RememberInstallRules.afterFailure's answer for the files read again
    signal finished(var outcome)

    // (request { what, argv }, done(result)) → nothing; done once with PrivilegedRules' result
    property var start: null
    property var paths: RememberInstallRules.livePaths
    property string shell: "/bin/sh"
    property var filesCommand: [Quickshell.shellDir + "/scripts/pam-files.sh"]
    readonly property bool busy: _busy

    property bool _busy: false

    // Install, or Install again. `request`: RememberInstallRules.installArgv's (facts,
    // minutes, rule, confs, replace). → { started, refusal (null or { code, text }) }
    function install(request) {
        return _run(RememberInstallRules.installArgv(shell, request, paths, start === null), RememberInstallRules.what("install"));
    }

    // `request`: RememberInstallRules.removeArgv's (facts, rule, confs, replace)
    function remove(request) {
        return _run(RememberInstallRules.removeArgv(shell, request, paths, start === null), RememberInstallRules.what("remove"));
    }

    // `request`: RememberInstallRules.undoArgv's (stamp, rule, conf: a reply's)
    function undo(request) {
        return _run(RememberInstallRules.undoArgv(shell, request, paths, start === null), RememberInstallRules.what("undo"));
    }

    function _run(plan, what) {
        if (_busy)
            return { started: false, refusal: RememberInstallRules.refusal("busy") };
        if (plan.refusal !== null)
            return { started: false, refusal: plan.refusal };
        _busy = true;
        const queue = start ?? ((request, done) => PrivilegedRuns.startShell(request, done));
        try {
            queue({ what: what, argv: plan.argv }, result => {
                const outcome = RememberInstallRules.reply(result, plan.expected);
                if (outcome.ok) {
                    root._busy = false;
                    root.finished(outcome);
                    return;
                }
                root._readAgain(plan.expected, outcome);
            });
        } catch (error) {
            // Nothing will answer: not left busy for good
            console.warn("[RememberInstall] the run could not be started: " + error);
            _busy = false;
            return { started: false, refusal: RememberInstallRules.refusal("start") };
        }
        return { started: true, refusal: null };
    }

    function _readAgain(expected, outcome) {
        const rule = paths.rules + "/" + RememberInstallRules.ruleName;
        const conf = paths.conf + "/" + RememberInstallRules.confName;
        const lines = [];
        _runner.start(Array.from(filesCommand).concat([rule, conf]), {
            timeoutMs: 6000,
            killAfterMs: 1000,
            maxOutputBytes: 1048576,
            keepOutput: false,
            onLine: (line, stream) => {
                if (stream === "stdout")
                    lines.push(line);
            },
            done: result => {
                const answers = PamStackRules.filesAnswer(lines, result, [rule, conf]).answers;
                outcome.files = RememberInstallRules.afterFailure({ rule: answers[rule], conf: answers[conf] }, expected);
                root._busy = false;
                root.finished(outcome);
            }
        });
    }

    property CommandRunner _runner: CommandRunner {}
}
