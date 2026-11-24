//@ pragma UseQApplication
import QtQuick
import Quickshell
import qs.singletons
// Imported so that Quickshell takes the kit into the tree it resolves `qs.…` against: it
// follows the imports of the files it loads at the start, not of a file created later
import qs.mockups.kit

// The one root entry of the mockups (development only): loads the mockup H2S_MOCKUP names
// against this tree, so that its `import qs.…` lines reach the real singletons and
// components. Mockup code and the protocol: mockups/kit/MockupWindow.qml.
//
//   H2S_MOCKUP=<kind>/<name>   mockups/<kind>/<name>/Mockup.qml; the kind is components,
//                              views or planning, the name lowercase letters, digits and "-"
//   H2S_MOCKUP_BASE            "tests/fixtures/mockups" loads the runners' fixture mockups
//                              instead of mockups/; nothing else is taken
//   H2S_MOCKUP_SHOT=1          headless: every scene in turn, a MOCKUP-SHOT line each,
//                              stepped by `ipc call mockup next`; then MOCKUP-DONE, exit 0
//   H2S_MOCKUP_SHOT_LIMIT_MS   how long the shots may take in all (60000 by default), a
//                              guard against a hang: then MOCKUP-ERROR
//   H2S_MOCKUP_SCENE=<scene>   on screen: opens that scene
//
// Any error prints MOCKUP-ERROR <text> and exits with status 2.
//
// The process is isolated from the session it runs in (Isolation: no module loads, no
// notification server, nothing sent), the configuration is read-only, the tree's files are
// not watched (a reload would start the scenes again), and animations are instant.
//
// Several mockups can run at once on one display: they share the config path, so a tool
// addresses one with `qs ipc --id <instance id>` (the id `qs list` shows, also in the
// "Saving logs to …/by-id/<id>/" line) or `--pid`, after asking each `ipc call mockup name`.
ShellRoot {
    id: root

    // First of all, before any singleton that reaches the session is made
    readonly property bool _isolated: { Isolation.active = true; return true; }
    readonly property bool _configReadOnly: { Config.readOnly = true; return true; }
    readonly property bool _noReload: { Quickshell.watchFiles = false; return true; }
    readonly property bool _instant: { Theme.instantAnimations = true; return true; }

    readonly property var _bases: ["mockups", "tests/fixtures/mockups"]
    property var _window: null

    function _fail(text) {
        console.error("MOCKUP-ERROR " + text);
        _exit(2);
    }

    // Not from inside the load: Quickshell handles the engine's exit only once the
    // configuration has loaded
    function _exit(code) {
        Qt.callLater(() => Qt.exit(code));
    }

    Component.onCompleted: {
        const name = Quickshell.env("H2S_MOCKUP") ?? "";
        const base = Quickshell.env("H2S_MOCKUP_BASE") || "mockups";
        const shooting = Quickshell.env("H2S_MOCKUP_SHOT") === "1";
        if (!/^(components|views|planning)\/[a-z0-9-]+$/.test(name)) {
            _fail("H2S_MOCKUP is '" + name + "': <kind>/<name>, the kind components, views or planning, the name lowercase letters, digits and '-'");
            return;
        }
        if (!_bases.includes(base)) {
            _fail("H2S_MOCKUP_BASE is '" + base + "': " + _bases.join(" or "));
            return;
        }
        const component = Qt.createComponent(Qt.resolvedUrl(base + "/" + name + "/Mockup.qml"), Component.PreferSynchronous);
        if (component.status !== Component.Ready) {
            _fail(name + ": " + component.errorString().replace(/\s+/g, " ").trim());
            return;
        }
        // Hidden until its root is known to be a MockupWindow: nothing else is ever shown
        const window = component.createObject(root, { visible: false });
        if (!window) {
            _fail(name + ": " + component.errorString().replace(/\s+/g, " ").trim());
            return;
        }
        if (!(window instanceof MockupWindow)) {
            window.destroy();
            _fail(name + ": the root of Mockup.qml is not a MockupWindow (qs.mockups.kit)");
            return;
        }
        _window = window;
        window.mockupName = name;
        window.shooting = shooting;
        const limit = Number(Quickshell.env("H2S_MOCKUP_SHOT_LIMIT_MS") || 60000);
        if (!(limit > 0)) {
            _fail("H2S_MOCKUP_SHOT_LIMIT_MS is '" + Quickshell.env("H2S_MOCKUP_SHOT_LIMIT_MS") + "': a number of milliseconds");
            return;
        }
        window.shotLimitMs = limit;
        window.finished.connect(() => {
            console.info("MOCKUP-DONE");
            root._exit(0);
        });
        window.failed.connect(text => _fail(name + ": " + text));
        const error = window.start(shooting ? "" : (Quickshell.env("H2S_MOCKUP_SCENE") ?? ""));
        if (error !== "") {
            window.destroy();
            _fail(name + ": " + error);
            return;
        }
        window.visible = true;
    }
}
