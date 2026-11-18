import QtQuick

// Its testPrograms directory is a link to another fixture's stand-ins: it leaves the module,
// so nothing in it is a stand-in, pkexec included (tests/ModulesTest.qml)
QtObject {
    property var module: null
}
