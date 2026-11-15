import QtQuick
import qs.singletons

// Loaded by file:// URL from outside Quickshell's scanned tree (tests/QuickshellPinTest.qml):
// sees its directory's singleton and the core's
QtObject {
    property var pin: PinState
    property var config: Config
    property var rules: ModuleRules
    Component.onCompleted: PinState.count += 1
}
