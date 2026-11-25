import QtQuick

// The shell's WheelHandler: one that takes a mouse wheel, and one rule for how far an event
// moves. Qt on Wayland hands a wheel's notches over as from its touchpad device (every axis
// event has a pixel delta), and a plain WheelHandler takes the mouse only, so it turned every
// wheel event away. Every WheelHandler in the tree is this one (tests/run-mockups-selftest.sh
// checks it).
//
// step(event): the movement along this handler's orientation, in pixels, signed as the
// deltas are (positive: up or left). A wheel's notches (no scroll phase) move by their angle,
// `notchPixels` a notch: their pixel delta is the compositor's 15 a notch, too small to
// scroll by. A touchpad's stroke (a scroll phase) moves by its pixels, with the finger: its
// angle delta is twelve times those.
//
// Like any WheelHandler it takes one orientation (`orientation`, vertical by default): a
// horizontal wheel needs a second one.
WheelHandler {
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

    // How far one notch of a wheel moves, in pixels
    property real notchPixels: 48

    function step(event) {
        const horizontal = orientation === Qt.Horizontal;
        const pixel = horizontal ? event.pixelDelta.x : event.pixelDelta.y;
        const angle = horizontal ? event.angleDelta.x : event.angleDelta.y;
        return event.phase !== Qt.NoScrollPhase && pixel !== 0 ? pixel : angle / 120 * notchPixels;
    }
}
