pragma Singleton

import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Dialogs

// The file chooser modules open (module API 1.17: module.chooseFiles, api/ModuleHandle.qml;
// the decisions are FileChooserRules'). One at a time for the whole shell, hosted by the
// shell — not by the caller's window, so a popup can ask and close.
//
// The dialog is the system's: QtQuick.Dialogs' FileDialog / FolderDialog, which Qt's platform
// theme turns into the portal's or GTK's where the user's theme says so, else Qt Quick's own.
// Qt Quick's own opens only with a visible window of the shell as its parent, so a window of
// one transparent pixel that takes no input is shown while a dialog is open, and the dialog
// is made inside it. The dialog is closed before it is destroyed: destroyed while open, Qt
// Quick's own leaves its window behind.
//
// - The module turned off (ownerGone): its dialog is closed, `done` is never called.
// - The session locked: nothing opens (`blocked: "locked"`); a lock while one is open closes
//   it, answered as the same `blocked: "locked"` — not `cancelled`, which is the user's. A
//   portal's window belongs to another process and stays on screen; its answer is dropped
//   all the same.
// - The shell going (a reload, the end): the dialog is closed at once, `done` is not called —
//   destroyed while open, Qt Quick's own would stay on screen.
// - In module test mode no dialog is made: each call is recorded (`testCalls`) and waits for
//   the test kit's answer (tests/ModuleTestKit.qml: answerChooser, cancelChooser), and the
//   lock is the kit's (`testLocked`).
Singleton {
    id: root

    readonly property bool _testMode: Modules.host.testMode
    // Module test mode: the session locked, as the test kit says
    property bool testLocked: false
    readonly property bool locked: _testMode ? testLocked : Profiles.screenLocked
    // A chooser is open (anyone's)
    readonly property bool open: _current !== null
    // Module test mode: the calls that opened, oldest first, frozen { moduleId, mode, title,
    // startDirectory } as the shell took them (`title` as the dialog would show it); at most 200 kept
    property var testCalls: []

    // The open call: { id, handle, mode, title, startDirectory, done, test }
    property var _current: null
    property int _lastId: 0
    // The real dialog and the window it is made in, while open
    property var _window: null
    property var _dialog: null
    // Answers waiting to be handed over, after the call that made them has returned
    property var _outbox: []

    // A module's call (module.chooseFiles). `handle`: the module's handle (moduleId, active);
    // `home`: where a chooser starts when the options name no directory. → { open (bool),
    // cancel() }. `done(result)` is called once, never inside this call, never while the
    // module is off (a call made then is not answered at all).
    function choose(handle, options, done, home) {
        const call = {
            id: ++_lastId, handle: handle, mode: "open", title: "", startDirectory: "",
            done: typeof done === "function" ? done : null, test: _testMode, answered: false
        };
        const callHandle = {
            get open() {
                return !call.answered;
            },
            cancel: function () {
                if (!call.answered && root._current === call)
                    root._finish(FileChooserRules.result({ cancelled: true }));
            }
        };
        const refusal = FileChooserRules.refusal({ active: handle?.active === true, locked: locked, busy: _current !== null });
        if (refusal === "off") {
            call.answered = true;
            return callHandle;
        }
        const parsed = FileChooserRules.options(options, home);
        if (parsed.problem !== "") {
            console.warn("[FileChooser] " + String(handle.moduleId) + ": a chooser refused — " + parsed.problem.slice(0, 300));
            _answer(call, FileChooserRules.result({ error: parsed.problem }));
            return callHandle;
        }
        if (refusal !== "") {
            _answer(call, FileChooserRules.result({ blocked: refusal }));
            return callHandle;
        }
        call.mode = parsed.mode;
        call.title = FileChooserRules.shownTitle(parsed.title, handle?.name);
        call.startDirectory = parsed.startDirectory;
        _current = call;
        if (call.test) {
            testCalls = testCalls.concat([Object.freeze({
                moduleId: String(handle.moduleId), mode: call.mode, title: call.title, startDirectory: call.startDirectory
            })]).slice(-200);
        } else {
            _window = _windowComponent.createObject(root);
            if (!_window)
                _finish(FileChooserRules.result({ error: "the dialog could not be opened" }));
            else
                _openingLimit.restart();
        }
        return callHandle;
    }

    // The module is off: its open chooser closes, unanswered
    function ownerGone(handle) {
        if (_current !== null && _current.handle === handle) {
            _current.answered = true;
            _current = null;
            _closeDialog();
        }
        _outbox = _outbox.filter(entry => entry.call.handle !== handle);
    }

    // ---- Module test mode (tests/ModuleTestKit.qml) ----

    // "" when the open recorded call is module `moduleId`'s, else why it cannot be answered
    function _testProblem(moduleId) {
        if (_current === null || !_current.test)
            return "no chooser is open";
        const owner = String(_current.handle?.moduleId ?? "");
        if (owner !== String(moduleId ?? ""))
            return "the open chooser is module " + ModuleRules.show(owner) + "'s, not " + ModuleRules.show(moduleId);
        return "";
    }

    // Answers module `moduleId`'s open recorded call with these paths → "" or why not
    // (nothing answered). Never throws into the suite.
    function testAnswer(moduleId, paths) {
        try {
            const problem = _testProblem(moduleId);
            if (problem !== "")
                return problem;
            const checked = FileChooserRules.testAnswer(paths, _current.mode);
            if (checked.problem !== "")
                return checked.problem;
            _finish(checked.result);
            return "";
        } catch (error) {
            return "the answer could not be taken: " + error;
        }
    }

    // Cancels module `moduleId`'s open recorded call, as the user closing the dialog → "" or
    // why not
    function testCancel(moduleId) {
        const problem = _testProblem(moduleId);
        if (problem !== "")
            return problem;
        _finish(FileChooserRules.result({ cancelled: true }));
        return "";
    }

    function testClear() {
        testCalls = [];
    }

    // Before each suite (tests-modules.qml): a recorded call another suite left open is
    // dropped unanswered, and the session is unlocked
    function testReset() {
        if (_current !== null && _current.test) {
            _current.answered = true;
            _current = null;
        }
        testLocked = false;
    }

    // ---- Inside ----

    // The open call, its dialog and its window, in a JavaScript object the shutdown's closure
    // holds: Qt may drop the singleton's properties before its destruction runs
    readonly property var _open: ({ call: null, dialog: null, window: null })
    on_CurrentChanged: _open.call = _current
    on_DialogChanged: _open.dialog = _dialog
    on_WindowChanged: _open.window = _window

    // The shell is going (at the destruction; a suite calls it): the open call ends
    // unanswered, and its dialog is closed and its window hidden now, not after the event
    // loop turns. A closure over what it needs, never over the singleton's own members
    property var _shutDown: null
    Component.onCompleted: {
        const open = _open;
        const openingLimit = _openingLimit;
        const deliver = _deliver;
        const shutDown = () => {
            openingLimit.stop();
            deliver.stop();
            if (open.call !== null)
                open.call.answered = true;
            const dialog = open.dialog;
            const window = open.window;
            open.call = open.dialog = open.window = null;
            // Writes only (each reaches nothing once Qt dropped the properties)
            root._outbox = [];
            root._current = null;
            root._dialog = null;
            root._window = null;
            try {
                if (dialog?.visible)
                    dialog.close();
            } catch (error) {}
            dialog?.destroy();
            if (window) {
                window.visible = false;
                window.destroy();
            }
        };
        _shutDown = shutDown;
        Component.destruction.connect(shutDown);
    }

    onLockedChanged: {
        if (locked && _current !== null)
            _finish(FileChooserRules.result({ blocked: "locked" }));
    }

    // The open call ends with `result`
    function _finish(result) {
        const call = _current;
        if (call === null)
            return;
        _current = null;
        _openingLimit.stop();
        _closeDialog();
        _answer(call, result);
    }

    function _answer(call, result) {
        call.answered = true;
        _outbox = _outbox.concat([{ call: call, result: result }]);
        _deliver.start();
    }

    // Closed first, then destroyed once the signal that ended it has returned, and its
    // window hidden before it goes: a window destroyed while shown has Qt Quick's dialog warn
    // that it found no window to open in
    function _closeDialog() {
        const dialog = _dialog;
        const window = _window;
        _dialog = null;
        _window = null;
        if (dialog !== null) {
            try {
                if (dialog.visible)
                    dialog.close();
            } catch (error) {}
        }
        if (dialog !== null || window !== null)
            Qt.callLater(() => {
                dialog?.destroy();
                if (window) {
                    window.visible = false;
                    window.destroy();
                }
            });
    }

    // A window the compositor never shows would hold the one chooser for good
    property Timer _openingLimit: Timer {
        interval: 10000
        onTriggered: {
            if (root._current !== null && !root._current.test && root._dialog === null) {
                console.warn("[FileChooser] the dialog's window was not shown within 10 s");
                root._finish(FileChooserRules.result({ error: "the dialog could not be opened" }));
            }
        }
    }

    property Timer _deliver: Timer {
        interval: 0
        onTriggered: {
            const waiting = root._outbox;
            root._outbox = [];
            for (const entry of waiting) {
                if (entry.call.done === null || entry.call.handle?.active !== true)
                    continue;
                try {
                    entry.call.done(entry.result);
                } catch (error) {
                    console.warn("[FileChooser] " + String(entry.call.handle.moduleId) + ": its done() threw: " + error);
                }
            }
        }
    }

    // The window is shown first; the dialog is made inside it once the compositor has it
    function _openDialog(window) {
        const call = _current;
        if (call === null || call.test || window !== _window || _dialog !== null)
            return;
        const component = call.mode === "folder" ? _folderComponent : _fileComponent;
        // The window the dialog belongs to, named rather than found from its parent item
        const properties = { title: call.title, parentWindow: window.contentItem.Window.window };
        const folder = FileChooserRules.folderUrl(call.startDirectory);
        if (folder !== "")
            properties.currentFolder = folder;
        if (call.mode !== "folder")
            properties.fileMode = call.mode === "openMany" ? FileDialog.OpenFiles : FileDialog.OpenFile;
        const dialog = component.createObject(window.contentItem, properties);
        if (!dialog) {
            _finish(FileChooserRules.result({ error: "the dialog could not be opened" }));
            return;
        }
        _dialog = dialog;
        _openingLimit.stop();
        dialog.open();
        if (!dialog.visible) {
            console.warn("[FileChooser] the dialog did not open");
            _finish(FileChooserRules.result({ error: "the dialog could not be opened" }));
        }
    }

    function _accepted(dialog, urls) {
        if (dialog !== _dialog || _current === null)
            return;
        _finish(FileChooserRules.accepted(urls, _current.mode));
    }

    function _rejected(dialog) {
        if (dialog !== _dialog || _current === null)
            return;
        _finish(FileChooserRules.result({ cancelled: true }));
    }

    property Component _windowComponent: Component {
        PanelWindow {
            id: chooserWindow

            implicitWidth: 1
            implicitHeight: 1
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "h2s-shell-chooser"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            anchors.top: true
            anchors.left: true
            // Takes no clicks: they reach whatever is under the pixel
            mask: Region {}

            onBackingWindowVisibleChanged: {
                if (backingWindowVisible)
                    root._openDialog(chooserWindow);
            }
            Component.onCompleted: {
                if (backingWindowVisible)
                    root._openDialog(chooserWindow);
            }
        }
    }

    property Component _fileComponent: Component {
        FileDialog {
            id: fileDialog

            onAccepted: root._accepted(fileDialog, fileMode === FileDialog.OpenFiles ? selectedFiles : [selectedFile])
            onRejected: root._rejected(fileDialog)
        }
    }

    property Component _folderComponent: Component {
        FolderDialog {
            id: folderDialog

            onAccepted: root._accepted(folderDialog, [FileChooserRules.folderChosen(selectedFolder, currentFolder)])
            onRejected: root._rejected(folderDialog)
        }
    }
}
