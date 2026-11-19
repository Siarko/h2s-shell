import QtQuick

// Cannot be created: a required property the host does not give. Its dependents count it as
// failed — known only once the host has tried to make it
QtObject {
    property var module: null
    required property string notGiven
    readonly property QtObject exports: QtObject {}
}
