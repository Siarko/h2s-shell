import QtQuick

// The shell's WheelHandler: one that takes a mouse wheel. Qt on Wayland hands a wheel's
// notches over as from its touchpad device (every axis event has a pixel delta), and a plain
// WheelHandler takes the mouse only, so it turned every wheel event away. Every WheelHandler
// in the tree is this one (tests/run-mockups-selftest.sh checks it).
//
// Like any WheelHandler it takes one orientation (`orientation`, vertical by default): a
// horizontal wheel needs a second one.
WheelHandler {
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
}
