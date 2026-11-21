import QtQuick

// Nothing of its own: tests/ModulesTest.qml starts a run as administrator on its handle, which
// the shell refuses before any prompt (its manifest declares no `privileged`)
QtObject {
    property var module: null
}
