import QtQuick
import Quickshell
import qs.singletons

// Another program's session lock, as far as it can be seen: the I/O around
// LockRules.foreignStep. On Hyprland `hyprctl -j locked` is read (SleepLockState with no
// session path: the compositor's word only, bounded to a second) when the compositor refused
// the shell's lock (`refused()`) and before the idle lock (`lockWhenFree()`); a lock read as
// held is read again after a growing pause until it ends. Elsewhere nothing is read: the
// refusal is all there is.
Scope {
    id: root

    signal logLine(string level, string message)
    // A lock asked through lockWhenFree() may go ahead
    signal lockAllowed(string source)

    // Another program holds the session lock (read so)
    readonly property bool held: _state.held
    readonly property var state: _state
    // The shell has a lock of its own asked or held (Lockscreen.locked): an answer read then
    // is about that one
    property bool ownLock: false
    property bool onHyprland: (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ?? "") !== ""
    // The longest pause between reads of a held lock (ms; 0: the rules' own)
    property int pollMaximum: 0

    property var _state: LockRules.foreignInitial()

    function refused() {
        _step({ type: "refused" });
    }

    function lockWhenFree(source) {
        _step({ type: "lockWanted", source: source });
    }

    function ownLocked() {
        _step({ type: "ownLocked" });
    }

    function _step(event) {
        const result = LockRules.foreignStep(_state, event, { canRead: onHyprland, pollMaximum: pollMaximum });
        if (result.ignored !== "")
            return;
        _state = result.state;
        for (const action of result.actions) {
            switch (action.type) {
            case "read":
                _reader.ask(action.serial);
                break;
            case "poll":
                _poll.interval = action.ms;
                _poll.restart();
                break;
            case "held":
                if (!action.held)
                    _poll.stop();
                break;
            case "lock":
                root.lockAllowed(action.source);
                break;
            case "log":
                root.logLine(action.level, action.message);
                break;
            }
        }
    }

    // One read at a time: asked while one runs, that one's answer is dropped and a fresh read
    // follows, so an answer always belongs to the serial it is reported with
    SleepLockState {
        id: _reader
        property int serial: 0
        property int wanted: 0
        onHyprland: root.onHyprland

        function ask(readSerial) {
            wanted = readSerial;
            if (!running) {
                serial = readSerial;
                start();
            }
        }

        onRead: outcome => {
            if (wanted !== serial) {
                // Started from outside the process's own change handler
                Qt.callLater(() => _reader.ask(_reader.wanted));
                return;
            }
            root._step({ type: "answer", serial: serial, outcome: outcome, ownLock: root.ownLock });
        }
    }

    Timer {
        id: _poll
        repeat: false
        onTriggered: root._step({ type: "pollDue" })
    }
}
