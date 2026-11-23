import QtQuick
import Quickshell
import qs.distributions
import qs.singletons

// Install, Remove and Undo of the remembered administrator authorization on Arch: one run as
// administrator each, the root step's files (RememberInstallRules.scriptFiles, in scripts/root/)
// read from the shell's tree at the click and their text run by the system's /bin/sh — never
// run by path. Each is a click of its own. What may run and what
// the answer means are RememberInstallRules'; this only queues the run, reads the two files
// again (as the user, scripts/pam-files.sh) when the run did not say it was done — a run cut
// short may still have changed them — and hands the outcome over. One run at a time.
//
// `start` is what queues the run: null for the shell's runs as administrator
// (PrivilegedRuns.startShell, which says who asks and what for), and then only the system's
// places (RememberInstallRules.livePaths); a suite's stand-in (which runs the same words as
// the user) only with places under a scratch folder outside /etc, /usr and /var
// (RememberInstallRules.pathsRefusal).
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
    // Where the root step's files are (scripts/root/ of the shell's tree), read at each run
    property string scriptsDirectory: Quickshell.shellDir + "/" + RootScriptRules.directory
    readonly property bool busy: _files.busy

    // Install, or Install again. `request`: RememberInstallRules.installArgv's (facts,
    // minutes, rule, confs, replace). → { started, refusal (null or { code, text }) }
    function install(request) {
        return _run(RememberInstallRules.installArgv(shell, request, paths, start === null, _scripts.read()), RememberInstallRules.what("install"));
    }

    // `request`: RememberInstallRules.removeArgv's (facts, rule, confs, replace)
    function remove(request) {
        return _run(RememberInstallRules.removeArgv(shell, request, paths, start === null, _scripts.read()), RememberInstallRules.what("remove"));
    }

    // `request`: RememberInstallRules.undoArgv's (stamp, rule, conf: a reply's)
    function undo(request) {
        return _run(RememberInstallRules.undoArgv(shell, request, paths, start === null, _scripts.read()), RememberInstallRules.what("undo"));
    }

    // What a request would change, without running it: `mode` "install" or "remove" →
    // { refusal (null or { code, text }), rule, conf (true: that file would change) }
    function plan(mode, request) {
        const planned = mode === "remove" ? RememberInstallRules.removeArgv(shell, request, paths, start === null, _scripts.read())
                                          : RememberInstallRules.installArgv(shell, request, paths, start === null, _scripts.read());
        if (planned.refusal !== null)
            return { refusal: planned.refusal, rule: false, conf: false };
        const expected = planned.expected;
        return { refusal: null, rule: expected.before.rule !== expected.after.rule, conf: expected.before.conf !== expected.after.conf };
    }

    function _run(plan, what) {
        if (_files.busy)
            return { started: false, refusal: RememberInstallRules.refusal("busy") };
        if (plan.refusal !== null)
            return { started: false, refusal: plan.refusal };
        const rule = paths.rules + "/" + RememberInstallRules.ruleName;
        const conf = paths.conf + "/" + RememberInstallRules.confName;
        const code = _files.run({
            what: what,
            argv: plan.argv,
            reply: result => RememberInstallRules.reply(result, plan.expected),
            readBack: [rule, conf],
            after: (answers, outcome) => outcome.files = RememberInstallRules.afterFailure({ rule: answers[rule], conf: answers[conf] }, plan.expected),
            done: outcome => root.finished(outcome)
        });
        return code === "" ? { started: true, refusal: null } : { started: false, refusal: RememberInstallRules.refusal(code) };
    }

    // The run itself, and the two files read again after a failure
    property EtcFiles _files: EtcFiles {
        start: root.start
        shell: root.shell
        filesCommand: root.filesCommand
    }
    property RootScriptFiles _scripts: RootScriptFiles {
        names: RememberInstallRules.scriptFiles
        directory: root.scriptsDirectory
    }
}
