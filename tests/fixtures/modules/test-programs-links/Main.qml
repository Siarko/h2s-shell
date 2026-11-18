import QtQuick

// Its stand-ins are links: pkexec to the system's setuid wrapper (NixOS), another to
// /usr/bin/pkexec (Arch), one to an executable of another fixture — all leave the module, so
// none is a stand-in, whichever exists — and one to a file inside the module, which is
// (tests/ModulesTest.qml)
QtObject {
    property var module: null
}
