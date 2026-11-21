import QtQuick
import Quickshell
import Quickshell.Io

// The order of singletons/Lockscreen.qml's direct children, pinned. On a reload Quickshell
// hands the new singleton's children their old instances by position, not by id or type:
// _carried (a PersistentProperties) must come before the WlSessionLock, so that its
// `reloaded` sets the new lock's `locked` before Quickshell realizes it (otherwise the
// reload unlocks), and the objects after a removed or added child each get another one's
// old instance. Nothing in QML can make that independent of order.
//
// So a change to the children — one added, removed or moved — changes the list below on
// purpose, and its review checks the reload path (lock bed: reload-while-locked,
// reload-hard, reload-explicit, reload-window, restart-crash-finger for the PAM helper
// sweep at the end, whose `done` is carried over by position too).
//
// The children are read from the file's text by its indentation (the tree's style: four
// spaces per level): a line `    Type {` is a child of the root; each is named by its `id`,
// else its IPC `target`, else by its type alone.
TestCase {
    id: suite
    suiteName: "LockscreenShape"

    property var _file: FileView {
        path: Quickshell.shellDir + "/singletons/Lockscreen.qml"
        blockLoading: true
    }

    readonly property var pinned: [
        "PersistentProperties _carried",
        "Component _scopeComponent",
        "Component _timerComponent",
        "WlSessionLock _sessionLock",
        "FileView _marker",
        "Process _markerProbe",
        "Timer _restoreRetry",
        "Timer _markerUnlockDelay",
        "Process _restoreProbe",
        "Process _fallbackProbe",
        "Process _fallbackDirectProbe",
        "LogindMonitor _logind",
        "SleepInhibitor _inhibitor",
        "IdleWatch _screensaverMonitor",
        "Timer",
        "IdleWatch",
        "IpcHandler lockscreen",
        "CapsLockLed _capsLed",
        "PersistentProperties _helperSweepOnce",
        "Process _helperSweep",
        "FileView _lockRestarts"
    ]

    // The root's direct children of a QML text, in order, as "Type name"
    function children(text) {
        const lines = text.split("\n");
        const found = [];
        let current = null;
        for (const line of lines) {
            const child = /^    ([A-Z][A-Za-z0-9_.]*)\s*\{(.*)$/.exec(line);
            if (child !== null) {
                current = { type: child[1], name: "" };
                found.push(current);
                const inline = /\bid:\s*(\w+)/.exec(child[2]);
                if (inline !== null)
                    current.name = inline[1];
                continue;
            }
            if (/^    \S/.test(line) || /^\S/.test(line)) {
                current = null;
                continue;
            }
            if (current === null || current.name !== "")
                continue;
            const id = /^        id:\s*(\w+)/.exec(line);
            const target = /^        target:\s*"([^"]+)"/.exec(line);
            if (id !== null)
                current.name = id[1];
            else if (target !== null && current.target === undefined)
                current.target = target[1];
        }
        return found.map(child => (child.type + " " + (child.name || child.target || "")).trim());
    }

    function run() {
        const text = _file.text();
        assert(/^Singleton \{$/m.test(text), "Lockscreen.qml read, its root a Singleton");
        const found = children(text);
        assertEqual(found.join(" | "), pinned.join(" | "), "the root's children, in the pinned order (a reload matches them by position)");
        assert(found.indexOf("PersistentProperties _carried") < found.indexOf("WlSessionLock _sessionLock"),
               "_carried before the WlSessionLock");

        // The reading itself: a child added in the middle, and one written on one line
        const probe = "Singleton {\n    Timer {\n        id: _a\n        property var x: Item {\n            id: _inner\n        }\n    }\n"
                      + "    Foo { id: _b }\n    IpcHandler {\n        target: \"t\"\n    }\n    Bar {\n    }\n}\n";
        assertEqual(children(probe).join(" | "), "Timer _a | Foo _b | IpcHandler t | Bar", "the reading: ids, a one-line child, a target, a bare type");
    }
}
