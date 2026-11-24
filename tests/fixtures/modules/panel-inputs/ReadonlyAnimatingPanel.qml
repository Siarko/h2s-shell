import QtQuick

// A popup panel whose `popupAnimating` is readonly: the popup cannot set it, and still
// gives it `availableHeight`, kept current
Item {
    id: panel
    property var module: null
    property real availableHeight: 0
    readonly property bool popupAnimating: true
    implicitWidth: 200
    implicitHeight: 40

    Component.onCompleted: InputsState.panel = panel
    Component.onDestruction: {
        if (InputsState.panel === panel)
            InputsState.panel = null;
    }
}
