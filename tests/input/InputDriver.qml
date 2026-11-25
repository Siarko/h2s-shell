import QtQuick
import Quickshell
import Quickshell.Io
import qs.tests

// A real pointer and keyboard for a suite of tests-input.qml: the lock bed's virtual devices
// (tests/lock/input/ltinput.py), which tests/run-input.sh starts on the run's compositor and
// whose command pipe it hands over as H2S_INPUT_FIFO. The input reaches the window through
// the compositor, as a mouse's and a keyboard's do, never as events made inside Qt.
//
// Lives inside the suite's window (its WindowDriver waits there). Each call returns once the
// compositor has the input (the client's acknowledgement), not once the shell has handled
// it: a suite then waits on the state it expects. False when the pipe did not take it.
//
//   pointAt(item, x, y)   the pointer to that point of the item (the window anchored at the
//                         output's top left corner)
//   click(item, x, y)     there, then a left click
//   wheel(notches)        a mouse wheel's notches, positive down
//   key(keysym)           one key by its keysym name (Down, Return, Escape, space, …)
//   type(text)            the text typed
Item {
    id: root

    // The suite's WindowDriver, whose wait() turns the event loop
    required property var driver
    readonly property string _fifo: Quickshell.env("H2S_INPUT_FIFO") ?? ""
    property int _exitCode: -1

    // Writes the command, then waits until the client acknowledges it (a line more in
    // <fifo>.ack); five seconds guard a client that is gone
    Process {
        id: _writer
        onExited: exitCode => root._exitCode = exitCode
    }

    function send(command) {
        if (_fifo === "")
            return false;
        _exitCode = -1;
        _writer.command = ["sh", "-c",
            "ack=\"$1.ack\"; before=$(cat \"$ack\" 2> /dev/null | wc -l); printf '%s\\n' \"$2\" > \"$1\" || exit 1; "
            + "n=0; while [ \"$(cat \"$ack\" 2> /dev/null | wc -l)\" -le \"$before\" ]; do "
            + "n=$((n + 1)); [ \"$n\" -gt 500 ] && exit 1; sleep 0.01; done",
            "sh", _fifo, command];
        _writer.running = true;
        for (let waited = 0; waited < 8000 && _exitCode === -1; waited += 10)
            driver.wait(10);
        return _exitCode === 0;
    }

    function pointAt(item, x, y) {
        const window = item.Window.window;
        const point = item.mapToItem(null, x, y);
        const screen = window?.screen ?? Quickshell.screens[0];
        return send("abs " + Math.round(point.x) + " " + Math.round(point.y) + " " + screen.width + " " + screen.height);
    }

    function click(item, x, y) {
        return pointAt(item, x, y) && send("click left");
    }

    function wheel(notches) {
        return send("scroll vertical " + notches);
    }

    function key(keysym) {
        return send("key " + keysym);
    }

    function type(text) {
        return send("type " + text);
    }
}
