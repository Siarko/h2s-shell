import QtQuick

// Loads although two of its optional programs are not found (one only on a PATH the suite
// gives later) and one is the user's (bin/, untrusted): tests/ModulesTest.qml
QtObject {
    property var module: null
}
