import QtQuick

// A row whose only child can hide: its implicit width goes to none
// (tests/ModuleContributionTest.qml)
Row {
    property bool childShown: true
    Rectangle {
        visible: parent.childShown
        width: 10
        height: 10
        color: "transparent"
    }
}
