import QtQuick

// A popup panel whose `opener` is readonly: the popup cannot set it, at its first build or
// when it is opened again from another entry
Item {
    id: panel
    property var module: null
    readonly property var opener: null
    implicitWidth: 200
    implicitHeight: 40

    Component.onCompleted: OpenerState.panel = panel
    Component.onDestruction: {
        if (OpenerState.panel === panel)
            OpenerState.panel = null;
    }
}
