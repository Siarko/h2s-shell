import QtQuick
import QtTest as QT

// QtTest's TestCase as the window suites use it: for its events (mouseClick, keyClick,
// touchEvent, wait), never run as a test of its own. What it changes:
// - windowShown is the driver's window's own: a frame of it has been drawn. QtTest's reads
//   its root object, which only its own runner sets, and which is null in a process being
//   torn down ("Cannot read property 'windowShown' of null", a TypeError that fails a run).
// - waitShown(): a suite's first event waits for that frame, not for a fixed time, so no
//   event goes to a surface that is not on the screen yet.
// A driver outside any window (a property of the suite) has none: windowShown stays false.
QT.TestCase {
    id: driver
    when: false

    property int framesDrawn: 0
    windowShown: framesDrawn > 0

    // A hang guard, counted in waits (a loaded machine makes each longer, never fewer)
    function waitShown(limitMs = 10000) {
        for (let waited = 0; waited < limitMs && !windowShown; waited += 10)
            wait(10);
        return windowShown;
    }

    Connections {
        target: driver.Window.window
        ignoreUnknownSignals: true
        function onFrameSwapped() {
            driver.framesDrawn++;
        }
    }
}
