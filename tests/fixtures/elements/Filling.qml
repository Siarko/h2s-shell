import QtQuick

// An element anchored to both sides of its parent, with no width of its own
// (tests/ModuleContributionTest.qml)
Rectangle {
    anchors.left: parent ? parent.left : undefined
    anchors.right: parent ? parent.right : undefined
    implicitHeight: 20
    color: "transparent"
}
