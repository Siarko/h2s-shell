import QtQuick

// A popup panel whose `availableHeight` is readonly: the popup cannot set it, and still
// gives it `popupAnimating`
Item {
    id: panel
    property var module: null
    readonly property real availableHeight: 77
    property bool popupAnimating: false
    onPopupAnimatingChanged: if (popupAnimating) InputsState.sawAnimating = true
    implicitWidth: 200
    implicitHeight: 40

    Component.onCompleted: InputsState.panel = panel
    Component.onDestruction: {
        if (InputsState.panel === panel)
            InputsState.panel = null;
    }
}
