import QtQuick
import qs.singletons

// Apply and Undo of the PAM rules on Arch: one run as administrator per service, the fixed
// script PamApplyRules.applyScript run by the system's /bin/sh — nothing is loaded from a
// file. Apply follows a passed trial (the user's click on Apply started both); Undo is a
// click of its own. What may run and what the answer means are PamApplyRules'; this only
// queues the run and hands the answer over. One run at a time.
//
// `start` is what queues the run: null for the shell's runs as administrator
// (PrivilegedRuns.startShell, which says who asks and what for), and then only the system's
// places (PamApplyRules.livePaths); a suite's stand-in (which runs the same words as the
// user) only with places outside /etc, /usr and /var (PamApplyRules.pathsRefusal).
QtObject {
    id: root

    // After each started run: PamApplyRules.applyReply's outcome
    signal finished(var outcome)

    // (request { what, argv }, done(result)) → nothing; done once with PrivilegedRules' result
    property var start: null
    property var paths: PamApplyRules.livePaths
    property string shell: "/bin/sh"
    readonly property bool busy: _busy

    property bool _busy: false

    // Apply one service's new rules. `request`: PamApplyRules.applyArgv's (service, built,
    // currentText, vendorText, trial). → { started, refusal (null or { code, text }) }
    function apply(request) {
        return _run(PamApplyRules.applyArgv(shell, request, paths, start === null), PamApplyRules.what("apply", String(request?.service ?? "")));
    }

    // Put a backup back. `request`: PamApplyRules.undoArgv's (service, backup, currentSha256)
    function undo(request) {
        return _run(PamApplyRules.undoArgv(shell, request, paths, start === null), PamApplyRules.what("undo", String(request?.service ?? "")));
    }

    function _run(plan, what) {
        if (_busy)
            return { started: false, refusal: PamApplyRules.refusal("busy") };
        if (plan.refusal !== null)
            return { started: false, refusal: plan.refusal };
        _busy = true;
        const queue = start ?? ((request, done) => PrivilegedRuns.startShell(request, done));
        queue({ what: what, argv: plan.argv }, result => {
            root._busy = false;
            root.finished(PamApplyRules.applyReply(result, plan.expected));
        });
        return { started: true, refusal: null };
    }
}
