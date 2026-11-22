import QtQuick
import Quickshell
import qs.singletons

// The I/O that belongs to one lock: a PAM adapter per method and the methods script's
// current run. Lockscreen creates one when a lock begins and destroys it once the lock has
// ended (after that step's effects ran), so destruction is the cleanup: every
// conversation's PAM helper and a script still running are killed with it, and nothing of
// one lock can reach the next — the old long-lived LockAuth needed a hand-kept reset list
// for that, and missed entries in it.
//
// Whatever a dying adapter still reports carries ids of the lock that ended, which the
// rules ignore; `retired` silences it anyway, so the log stays readable.
Scope {
    id: root

    signal event(var event)
    signal logLine(string level, string message)

    property bool retired: false

    // { method name: PamMethod }
    property var _methods: ({})
    property var _detector: null

    function pam(method) {
        const adapter = _methods[method];
        if (adapter === undefined)
            logLine("error", "no PAM adapter for the method " + method);
        return adapter ?? null;
    }

    // A newer run supersedes the one running: that one is killed (destroyed), and its
    // answer could only have carried an older generation anyway
    function detect(generation) {
        if (_detector !== null) {
            _detector.cancelled = true;
            _detector.destroy();
        }
        _detector = _detectorComponent.createObject(root, { generation: generation });
        if (_detector === null) {
            logLine("error", "could not create the methods script's runner");
            root._report({ type: "methodsFailed", generation: generation, reason: "the runner could not be created" });
            return;
        }
        _detector.event.connect(root._report);
        _detector.logLine.connect(root._log);
    }

    function retire() {
        retired = true;
        if (_detector !== null)
            _detector.cancelled = true;
    }

    function _report(event) {
        if (!retired)
            root.event(event);
    }

    function _log(level, message) {
        if (!retired)
            root.logLine(level, message);
    }

    Component {
        id: _detectorComponent
        MethodDetector {}
    }

    Component {
        id: _pamComponent
        PamMethod {}
    }

    Component.onCompleted: {
        const names = ["password"].concat(LockRules.passiveMethods.map(method => method.name));
        const methods = {};
        for (const name of names) {
            const adapter = _pamComponent.createObject(root, { method: name });
            adapter.event.connect(root._report);
            adapter.logLine.connect(root._log);
            methods[name] = adapter;
        }
        _methods = methods;
    }
}
