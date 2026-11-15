import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons

// Whether Caps Lock is on, from the kernel's keyboard LEDs: /sys/class/leds/*::capslock/
// brightness, one per keyboard, which the compositor drives from its xkb state. Any LED on
// is Caps Lock on (LockIoRules.capsLockFromLeds). No such LED, or none that can be read:
// unknown (null), and the prompt says nothing — a missing warning is what there was before,
// a wrong one sends the owner chasing a problem that is not there.
//
// It replaces guessing from the keys typed, which went stale across locks and took a
// composed capital (dead key + Shift+e = "É", Compose, an input method) for Caps Lock.
//
// sysfs sends no change notifications, so it is read when asked (`read()`: the driver asks
// on each key at an awake prompt and when the prompt wakes) and once more shortly after —
// the Caps Lock key reaches the shell about when the compositor sets the LED, and the first
// read may still see the old value. Never on a timer while nobody types.
//
// H2S_LOCK_LEDS_DIR names another directory instead of /sys/class/leds — the lock test bed's
// seam (no keyboard, so no LED, in its nested compositor); inert unless set.
Scope {
    id: root

    // true, false, or null (unknown)
    readonly property var on: _on
    property var _on: null

    readonly property string directory: Quickshell.env("H2S_LOCK_LEDS_DIR") || "/sys/class/leds"

    // A read now (and one shortly after); a read asked for while one runs is run after it
    function read() {
        _settle.restart();
        _run();
    }

    // Forgotten (a new lock): unknown until the next read answers
    function forget() {
        _settle.stop();
        _on = null;
    }

    property bool _again: false
    property var _lines: []

    function _run() {
        if (_probe.running) {
            _again = true;
            return;
        }
        _probe.running = true;
    }

    Timer {
        id: _settle
        interval: 250
        repeat: false
        onTriggered: root._run()
    }

    // One line per LED: "led <brightness>", or "led ?" when it cannot be read. Builtins
    // only: no process beyond the one shell per read
    Process {
        id: _probe
        command: ["sh", "-c",
            "for file in \"$1\"/*::capslock/brightness; do\n"
            + "    [ -e \"$file\" ] || continue\n"
            + "    if IFS= read -r value < \"$file\" 2> /dev/null; then echo \"led $value\"; else echo 'led ?'; fi\n"
            + "done\n"
            + "exit 0",
            "sh", root.directory]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => root._lines = root._lines.concat([line])
        }
        onRunningChanged: {
            if (running)
                return;
            const lines = root._lines;
            root._lines = [];
            root._on = LockIoRules.capsLockFromLeds(lines);
            if (root._again) {
                root._again = false;
                root._run();
            }
        }
    }
}
