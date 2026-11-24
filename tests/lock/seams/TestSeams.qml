pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.singletons.io as Io

// The test tree's TestSeams: copied over singletons/TestSeams.qml (whose properties are
// constants) when a test tree is assembled — the lock bed's copy of the checkout
// (tests/lock/run.sh). Only such a tree reads
// the test seams: the environment variables by which the tests change the shell's timings,
// tools, directories and stand-ins. TestSeamRules (copied beside it) lists them, with what
// each is for, and decides what each says. Lockscreen, CapsLockLed, Modules and VpnManager
// read them here, by the same property names as the production file's — TestSeamsShapeTest
// checks the two files agree. Read once, at the first use; when any is in force, one line
// in the log names them (`[TestSeams] test bed: …`), and `qs ipc call modules list` and
// the lock screen's `state` carry the list. And the `locktest` IPCs live here, below.
//
// Used by the lock screen: it imports nothing of the module system, and nothing that
// would wait.
Singleton {
    id: root

    readonly property var _read: {
        const environment = {};
        for (const name of TestSeamRules.names)
            environment[name] = Quickshell.env(name) ?? "";
        return TestSeamRules.read(environment);
    }

    readonly property string lockTools: _read.lockTools
    readonly property string systemPamDirectory: _read.systemPamDirectory
    readonly property string ledsDirectory: _read.ledsDirectory
    readonly property var timings: _read.timings
    readonly property string timingsProblem: _read.timingsProblem
    readonly property bool reloadIpc: _read.reloadIpc
    readonly property int moduleGuardMs: _read.moduleGuardMs
    readonly property string moduleCheckPath: _read.moduleCheckPath
    readonly property int moduleCheckMs: _read.moduleCheckMs
    readonly property bool moduleNotify: _read.moduleNotify
    readonly property bool fakeVpnProvider: _read.fakeVpnProvider
    readonly property string distribution: _read.distribution
    readonly property string distributionHold: _read.distributionHold
    readonly property bool settingRangesOff: _read.settingRangesOff
    // Module test mode (ModuleHost.testMode): on in every test tree, whatever the
    // environment holds — it is the tree, not a variable, that makes a run a test
    readonly property bool moduleTestMode: true
    // The names of the seams in force, and whether there is any
    readonly property var inForce: _read.inForce
    readonly property bool active: inForce.length > 0

    Component.onCompleted: {
        if (active)
            console.warn("[TestSeams] test bed: " + inForce.join(", "));
        if (_read.ignored.length > 0)
            console.warn("[TestSeams] set, but not used (a value the shell cannot use): " + _read.ignored.join(", "));
    }

    // A reload while locked, for the lock bed (tests/lock/tests/reload-*.sh): nothing in the
    // shell calls Quickshell.reload(), and file changes do not reload while locked (nor at all
    // out of development mode), so the
    // test asks for one here. Only with H2S_LOCK_TEST_RELOAD=1 (stack_start --reload-seam).
    // Built when the lock screen first reads a seam, which is at its start.
    IpcHandler {
        target: "locktest"
        enabled: root.reloadIpc

        function reload(hard: bool): string {
            Qt.callLater(() => Quickshell.reload(hard));
            return hard ? "hard reload" : "reload";
        }

        // One progress notification of the shell's own sender, on its real path — gdbus to
        // the shell's own server on the bed's private bus (tests/lock/tests/notifier-progress.sh):
        //   progress send '{"summary", "body", "progress", "toast", "actions": ["id", …]}'
        //   progress update '{"summary"?, "progress"?, "state"?, "announce"?}'
        //   progress close ''
        //   progress state ''  → { id, state, open, calls, events }
        // ("send", not "show": the CLI takes "show" for its own subcommand.) Each answers the state. A test tree's Notifier only records (module test mode), so
        // the handle is made here as Notifier.send makes it, with recordOnly off; its
        // callbacks add to `events` ("action:<id>", "dismissed").
        function progress(operation: string, argument: string): string {
            return root._progress(operation, argument);
        }
    }

    // The notifications the server holds, for the lock bed's notification scenarios
    // (tests/lock/tests/notifications.sh and others): only a test tree answers, so no process
    // of the user reads held notifications from the shell. On in every test tree, as module
    // test mode is.
    IpcHandler {
        target: "locktest.notifications"

        // The notifications the server holds, in its order: each one's id, summary,
        // progress as its card shows it (NotificationRules.progress), and its toast —
        // whether it is on screen, where ("waiting", "shown", "moved" or "none") in which
        // queue ("critical", "staying", "ordinary"), and for how long, in ms (0: it stays;
        // ToastRules.timing)
        function notificationState(): string {
            return JSON.stringify(Notifications.notifications.values.map(notification => {
                const place = Toasts.toastPlace(notification.id);
                return {
                    id: notification.id, summary: notification.summary, body: notification.body,
                    progress: NotificationRules.progress(notification.hints),
                    toast: { shown: place.place === "shown" || place.place === "moved", place: place.place, queue: place.queue,
                             duration: Toasts.toastDurations[notification.id] ?? null }
                };
            }));
        }
    }

    property var _progressHandle: null
    property int _progressHandles: 0
    property var _progressEvents: []
    property var _progressRunner: null
    property Component _progressHandleComponent: Component {
        Io.NotificationHandle {}
    }
    property Component _progressRunnerComponent: Component {
        Io.CommandRunner {}
    }

    function _progress(operation, argument) {
        let given = {};
        try {
            given = argument !== "" ? JSON.parse(argument) : {};
        } catch (error) {
            return JSON.stringify({ error: "not JSON" });
        }
        const handle = _progressHandle;
        if (operation === "send") {
            if (_progressRunner === null)
                _progressRunner = _progressRunnerComponent.createObject(root);
            _progressEvents = [];
            const actions = (given.actions ?? []).map(id => ({
                id: id, label: id, onTriggered: () => root._progressEvents = root._progressEvents.concat(["action:" + id])
            }));
            const options = Object.assign({}, given, { actions: actions });
            _progressHandle = _progressHandleComponent.createObject(root, {
                number: ++_progressHandles, recordOnly: false, runner: _progressRunner, server: Notifications,
                wanted: Notifier.progressContent(given.summary ?? "", options, Notifier.progressRun, "seam" + _progressHandles),
                callbacks: { actions: actions, onDismissed: () => root._progressEvents = root._progressEvents.concat(["dismissed"]) }
            });
        } else if (handle === null) {
            return JSON.stringify({ error: "no handle" });
        } else if (operation === "update") {
            handle.update(given);
        } else if (operation === "close") {
            handle.close();
        } else if (operation !== "state") {
            return JSON.stringify({ error: "unknown operation" });
        }
        const current = _progressHandle;
        return JSON.stringify({ id: current.id, state: current.state, open: current.open, calls: current.calls, events: _progressEvents });
    }
}
