import QtQuick

// An element that takes a context, and counts the VPNs it names; what its context was when it
// was made, before any later pass (tests/ModuleContributionTest.qml)
Item {
    property var context: null
    readonly property int othersUp: context?.otherVpnsUp?.length ?? -1
    // At Component.onCompleted: given, frozen, its list an Array read through a getter
    property string atStart: ""
    width: 10
    height: 10
    Component.onCompleted: {
        const given = context;
        atStart = given === null ? "none" : [Object.isFrozen(given), Array.isArray(given.otherVpnsUp),
                                             Object.getOwnPropertyDescriptor(given, "otherVpnsUp")?.get !== undefined,
                                             Object.getOwnPropertyDescriptor(given, "vpn")?.get !== undefined].join(",");
    }
}
