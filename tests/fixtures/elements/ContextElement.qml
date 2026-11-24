import QtQuick

// An element that takes a context, and counts the VPNs it names (tests/ModuleContributionTest.qml)
Item {
    property var context: null
    readonly property int othersUp: context?.otherVpnsUp?.length ?? -1
    width: 10
    height: 10
}
