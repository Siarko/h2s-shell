import QtQuick

// Nothing of its own: its suite tries module test mode's gate for modules written for an API
// below 1.10 (tests/LegacyElevateTest.qml)
QtObject {
    property var module: null
}
