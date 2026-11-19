import QtQuick
import QtTest as QT
import Quickshell
import qs.singletons

// The file chooser's real path (singletons/FileChooser.qml): a real dialog in a real window
// of the shell — in the runner's private headless compositor (tests/run-unit.sh), never on
// the user's screen. The dialog is Qt Quick's own there (no platform theme), driven from code:
// it opens inside the shell's one-pixel window, in the directory asked for, and answers a
// choice and a cancel; a second call while it is open is busy; a lock closes it (cancelled)
// and refuses the next; the module turned off closes it with no answer. After each, the
// dialog and its window are gone. Asynchronous: the window is mapped by the compositor.
TestCase {
    id: suite
    suiteName: "FileChooser"
    asynchronous: true

    readonly property string _directory: Quickshell.shellDir + "/tests/fixtures/device-address-reading"

    // A module's handle as FileChooser sees it
    property QtObject owner: QtObject {
        property string moduleId: "chooser-test"
        property bool active: true
    }

    // The suites to wait for before a dialog opens (tests.qml: the other asynchronous ones)
    property var waitFor: []
    property var _answers: []
    property var _call: null
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

    function _shown() {
        return FileChooser._dialog !== null && FileChooser._dialog.visible === true;
    }

    function _gone() {
        return FileChooser._dialog === null && FileChooser._window === null && !FileChooser.open;
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
        _then("the other asynchronous suites are done", () => waitFor.every(other => other.done), () => _run(), 55000);
        _clock.start();
    }

    function _run() {
        assert(!Modules.host.testMode, "the unit suites run outside module test mode: the real dialog");
        assert(!FileChooser.open, "nothing open at the start");

        // --- a file: opened in the shell's window, in the directory asked for, then chosen ---
        _call = _choose({ mode: "open", title: "Pick\none", startDirectory: _directory + "/" });
        assert(_call.open, "the call's handle: open");
        assert(FileChooser.open, "FileChooser.open");
        _then("the dialog is shown", () => _shown(), () => {
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
        _then("Return reaches it", () => _press(Qt.Key_Return), () => {});
        _then("chosen", () => _answers.length === 1, () => {
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
            _call = _choose({ mode: "openMany" });
            _choose({ mode: "folder" });
        });
        _then("the second call is answered busy", () => _answers.length === 1 && _shown(), () => {
            assertEqual(JSON.stringify(_answers[0]), "{\"paths\":[],\"cancelled\":false,\"blocked\":\"busy\",\"error\":\"\"}",
                        "a second chooser while one is open: blocked busy, the first stays");
            assertEqual(FileChooser._dialog.fileMode, 1, "openMany: several files (FileDialog.OpenFiles)");
        });
        _then("Escape reaches it", () => _press(Qt.Key_Escape), () => {});
        _then("cancelled", () => _answers.length === 2, () => {
            assertEqual(JSON.stringify(_answers[1]), "{\"paths\":[],\"cancelled\":true,\"blocked\":\"\",\"error\":\"\"}", "Escape: cancelled");
        });
        _then("gone after the cancel", () => _gone(), () => {
            _answers = [];
            // --- a folder; then a lock while it is open ---
            _choose({ mode: "folder", startDirectory: _directory });
        });
        _then("the folder dialog is shown", () => _shown(), () => {
            assertEqual(String(FileChooser._dialog.currentFolder), "file://" + _directory, "a folder dialog, in startDirectory");
            assert(FileChooser._dialog.selectedFolder !== undefined && FileChooser._dialog.fileMode === undefined, "… a FolderDialog");
            Profiles.screenLocked = true;
        });
        _then("the lock cancels it", () => _answers.length === 1, () => {
            assertEqual(JSON.stringify(_answers[0]), "{\"paths\":[],\"cancelled\":true,\"blocked\":\"\",\"error\":\"\"}", "a lock while open: cancelled");
            _choose({});
        });
        _then("refused while locked", () => _answers.length === 2 && _gone(), () => {
            assertEqual(_answers[1].blocked, "locked", "locked: blocked, nothing opened");
            Profiles.screenLocked = false;
            _answers = [];
            // --- the module turned off while it is open ---
            _choose({});
        });
        _then("shown again", () => _shown(), () => {
            owner.active = false;
            FileChooser.ownerGone(owner);
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
