import QtQuick
import QtTest as QT
import Quickshell
import Quickshell.Wayland
import qs.singletons

// The file chooser's real path (singletons/FileChooser.qml): a real dialog in a real window
// of the shell — in the runner's private headless compositor (tests/run-unit.sh), never on
// the user's screen. The dialog is Qt Quick's own there (no platform theme), driven from code:
// it opens inside the shell's one-pixel window, in the directory asked for, and answers a
// choice and a cancel; a second call while it is open is busy; a folder dialog's Open with
// nothing picked; a lock closes it (cancelled) and refuses the next; the shell going and the
// module turned off close it with no answer. After each, the dialog, the shell's window and
// the dialog's own window are gone — the last as the compositor lists its windows
// (ToplevelManager), each dialog by its title. Asynchronous: windows are mapped by the
// compositor.
TestCase {
    id: suite
    suiteName: "FileChooser"
    asynchronous: true

    readonly property string _directory: Quickshell.shellDir + "/tests/fixtures/device-address-reading"
    readonly property string _folders: Quickshell.shellDir + "/tests/fixtures/file-chooser/folders"
    readonly property string _noFolders: Quickshell.shellDir + "/tests/fixtures/file-chooser/no-folders"

    // A module's handle as FileChooser sees it
    property QtObject owner: QtObject {
        property string moduleId: "chooser-test"
        property string name: "Chooser\ntest"
        property bool active: true
    }

    // The suites to wait for before a dialog opens (tests.qml: the other asynchronous ones),
    // and for how long at most (tests.qml: its limit less ownTimeMs) — then this suite fails
    // without opening a dialog
    property var waitFor: []
    property int waitLimitMs: 60000
    // What this suite needs once it starts, at most
    readonly property int ownTimeMs: 25000
    property var _answers: []
    property var _call: null
    // The open dialog, the shell's window it was made in, and its title, kept while it is
    // shown: guarded, they become null once destroyed
    property QtObject _seenDialog: null
    property QtObject _seenWindow: null
    property string _seenTitle: ""
    property Item _driverHolder: Item {
        QT.TestCase {
            id: driver
            name: "FileChooserDriver"
            when: false
        }
    }

    function _choose(options) {
        return FileChooser.choose(owner, options, result => suite._answers = suite._answers.concat([result]), "/nonexistent-home");
    }

    // A key to the window that has the keyboard → false while none has it yet (a dialog just
    // mapped gets it from the compositor a moment later)
    function _press(key) {
        try {
            driver.keyClick(key);
            return true;
        } catch (error) {
            return false;
        }
    }

    // `key` pressed until `answered()` holds, again every half second: a key sent before the
    // dialog's window has the keyboard (the compositor hands it over a moment after mapping it)
    // goes to the window that had it, and is lost
    property real _lastPress: 0
    function _pressUntil(key, answered) {
        if (answered())
            return true;
        if (Date.now() - _lastPress >= 500 && _press(key))
            _lastPress = Date.now();
        return false;
    }

    // The compositor lists a window with this title (the dialog's own)
    function _listed(title) {
        return ToplevelManager.toplevels.values.some(toplevel => toplevel.title === title);
    }

    // The dialog titled `title` is shown, and the compositor has its window; it is kept
    // for _gone()
    function _shown(title) {
        if (FileChooser._dialog === null || FileChooser._dialog.visible !== true || !_listed(title))
            return false;
        _seenDialog = FileChooser._dialog;
        _seenWindow = FileChooser._window;
        _seenTitle = title;
        return true;
    }

    // Nothing open, the dialog and the shell's window destroyed, and the dialog's own window
    // no longer listed by the compositor
    function _gone() {
        return FileChooser._dialog === null && FileChooser._window === null && !FileChooser.open
            && _seenDialog === null && _seenWindow === null && !_listed(_seenTitle);
    }

    // ---- A tiny scheduler: each step waits for its condition (or its deadline), then runs ----
    property var _steps: []

    function _then(description, condition, action, deadlineMs) {
        _steps.push({ description: description, condition: condition, action: action, deadlineMs: deadlineMs ?? 8000 });
    }

    property Timer _clock: Timer {
        interval: 25
        repeat: true
        property int waited: 0
        onTriggered: {
            const step = suite._steps[0];
            if (!step) {
                stop();
                suite._end();
                return;
            }
            waited += interval;
            let ready = false;
            try {
                ready = step.condition();
            } catch (error) {}
            if (!ready && waited < step.deadlineMs)
                return;
            waited = 0;
            suite._steps.shift();
            if (!ready)
                suite.fail("timed out waiting: " + step.description);
            try {
                step.action();
            } catch (error) {
                suite.fail("threw in \"" + step.description + "\": " + error);
            }
        }
    }

    function _end() {
        Profiles.screenLocked = false;
        if (FileChooser.open)
            FileChooser.ownerGone(owner);
        finish();
    }

    function runAsync() {
        _then("the other asynchronous suites are done", () => waitFor.every(other => other.done), () => {
            const pending = waitFor.filter(other => !other.done);
            if (pending.length > 0) {
                // Not opened: a dialog now could take keys another suite sends
                fail("not run: " + pending.map(other => other.suiteName).join(", ") + " still running");
                _steps = [];
                return;
            }
            _run();
        }, waitLimitMs);
        _clock.start();
    }

    function _run() {
        assert(!Modules.host.testMode, "the unit suites run outside module test mode: the real dialog");
        assert(!FileChooser.open, "nothing open at the start");

        // --- a file: opened in the shell's window, in the directory asked for, then chosen ---
        _call = _choose({ mode: "open", title: "Pick\none", startDirectory: _directory + "/" });
        assert(_call.open, "the call's handle: open");
        assert(FileChooser.open, "FileChooser.open");
        _then("the dialog is shown", () => _shown("Pick one"), () => {
            const dialog = FileChooser._dialog;
            assert(FileChooser._window.backingWindowVisible, "inside the shell's window, mapped");
            assertEqual(dialog.title, "Pick one", "its title, on one line");
            assertEqual(String(dialog.currentFolder), "file://" + _directory, "it starts in startDirectory");
            assertEqual(dialog.fileMode, 0, "one file (FileDialog.OpenFile)");
            assertEqual(_answers.length, 0, "no answer yet");
        });
        // Real keys, to the dialog's window (it has the keyboard): Down until "ip" is the
        // current file — once the folder is listed — then Return
        _then("the file \"ip\" is current", () => {
            if (String(FileChooser._dialog.currentFile).endsWith("/ip"))
                return true;
            _press(Qt.Key_Down);
            return false;
        }, () => {});
        _then("chosen", () => _pressUntil(Qt.Key_Return, () => _answers.length === 1), () => {
            const answer = _answers[0];
            assert(!answer.cancelled && answer.blocked === "" && answer.error === "" && answer.paths.length === 1,
                   "accepted: one path, nothing else said: " + JSON.stringify(answer));
            assertEqual(answer.paths[0], _directory + "/ip", "… the file chosen, as an absolute path, not a URL");
            assert(Object.isFrozen(answer) && Object.isFrozen(answer.paths), "… frozen");
            assert(!_call.open, "the call's handle: no longer open");
        });
        _then("the dialog and its window are gone", () => _gone(), () => {
            _answers = [];
            // --- busy, then a cancel ---
            _call = _choose({ mode: "openMany", title: "Chooser two" });
            _choose({ mode: "folder" });
        });
        _then("the second call is answered busy", () => _answers.length === 1 && _shown("Chooser two"), () => {
            assertEqual(JSON.stringify(_answers[0]), "{\"paths\":[],\"cancelled\":false,\"blocked\":\"busy\",\"error\":\"\"}",
                        "a second chooser while one is open: blocked busy, the first stays");
            assertEqual(FileChooser._dialog.fileMode, 1, "openMany: several files (FileDialog.OpenFiles)");
        });
        _then("cancelled", () => _pressUntil(Qt.Key_Escape, () => _answers.length === 2), () => {
            assertEqual(JSON.stringify(_answers[1]), "{\"paths\":[],\"cancelled\":true,\"blocked\":\"\",\"error\":\"\"}", "Escape: cancelled");
        });
        _then("gone after the cancel", () => _gone(), () => {
            _answers = [];
            // --- a folder dialog's Open with nothing picked: in a folder with sub-folders the
            // first is selected as it opens (Qt Quick's own; api/Api.qml says so) ---
            _choose({ mode: "folder", title: "Folder three", startDirectory: _folders });
        });
        _then("the folder dialog with sub-folders lists them", () => _shown("Folder three") && String(FileChooser._dialog.selectedFolder) !== "", () => {
            assertEqual(String(FileChooser._dialog.selectedFolder), "file://" + _folders + "/alpha", "… the first sub-folder selected, nothing picked");
            FileChooser._dialog.accept();
        });
        _then("Open with sub-folders", () => _answers.length === 1, () => {
            assertEqual(JSON.stringify(_answers[0].paths), JSON.stringify([_folders + "/alpha"]), "Open, nothing picked: the first sub-folder");
        });
        _then("gone after Open", () => _gone(), () => {
            _answers = [];
            _choose({ mode: "folder", title: "Folder four", startDirectory: _noFolders });
        });
        _then("the folder dialog without sub-folders is shown", () => _shown("Folder four"), () => {
            assertEqual(String(FileChooser._dialog.selectedFolder), "", "no sub-folders: none selected");
            FileChooser._dialog.accept();
        });
        _then("Open without sub-folders", () => _answers.length === 1, () => {
            assertEqual(JSON.stringify(_answers[0]), JSON.stringify({ paths: [_noFolders], cancelled: false, blocked: "", error: "" }),
                        "Open, nothing selected: the folder shown");
        });
        _then("gone after the second Open", () => _gone(), () => {
            _answers = [];
            // --- a folder; then a lock while it is open ---
            _choose({ mode: "folder", title: "Folder five", startDirectory: _directory });
        });
        _then("the folder dialog is shown", () => _shown("Folder five"), () => {
            assertEqual(String(FileChooser._dialog.currentFolder), "file://" + _directory, "a folder dialog, in startDirectory");
            assert(FileChooser._dialog.selectedFolder !== undefined && FileChooser._dialog.fileMode === undefined, "… a FolderDialog");
            Profiles.screenLocked = true;
            assert(_seenDialog !== null && !_seenDialog.visible, "a lock: the dialog closed at once, before it is destroyed (else its window stays)");
        });
        _then("the lock closes it", () => _answers.length === 1, () => {
            assertEqual(JSON.stringify(_answers[0]), "{\"paths\":[],\"cancelled\":false,\"blocked\":\"locked\",\"error\":\"\"}",
                        "a lock while open: blocked locked, not cancelled (that is the user's)");
            _choose({});
        });
        _then("refused while locked", () => _answers.length === 2 && _gone(), () => {
            assertEqual(_answers[1].blocked, "locked", "locked: blocked, nothing opened");
            Profiles.screenLocked = false;
            _answers = [];
            // --- the shell going while it is open (FileChooser's Component.onDestruction); no
            // title: the module's name shows ---
            _choose({});
        });
        _then("shown before the shell goes", () => _shown("Chooser test"), () => {
            assertEqual(FileChooser._dialog.title, "Chooser test", "no title: the module's name, on one line");
            FileChooser._shutDown();
            assert(!FileChooser.open, "the shell going: nothing open");
            assert(_seenDialog === null || !_seenDialog.visible, "… the dialog closed at once, not after the event loop turns");
        });
        _then("closed as the shell goes", () => _gone() && !FileChooser._deliver.running, () => {
            assertEqual(_answers.length, 0, "the shell going: done never called");
            // --- the module turned off while it is open ---
            _choose({ title: "Chooser seven" });
        });
        _then("shown again", () => _shown("Chooser seven"), () => {
            owner.active = false;
            FileChooser.ownerGone(owner);
            assert(_seenDialog !== null && !_seenDialog.visible, "the module off: the dialog closed at once, before it is destroyed");
        });
        _then("closed with the module", () => _gone() && !FileChooser._deliver.running, () => {
            assertEqual(_answers.length, 0, "the module off: closed, done never called");
            _choose({});
        });
        _then("a call while off", () => !FileChooser._deliver.running, () => {
            assert(_gone(), "… a call while off opens nothing");
            assertEqual(_answers.length, 0, "… and is not answered");
            owner.active = true;
        });
    }
}
