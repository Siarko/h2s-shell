import QtQuick
import qs.singletons

// A colour's swatch that opens its picker: on squares, so transparency shows; outlined
// empty when there is no colour (or not a valid one). The owner shows a ColorPicker
// while `open`, as the Colors page does; a click asks for that (`clicked`).
Item {
    id: root

    // A colour, or "" / anything not one for none
    property string color: ""
    property bool open: false
    property string tooltip: open ? "Close the picker" : "Pick a colour"
    signal clicked()

    readonly property bool _valid: /^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(color)

    implicitWidth: 22
    implicitHeight: 22

    Checkerboard {
        anchors.fill: parent
        visible: root._valid
        cellSize: 11
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.field.radius
        color: root._valid ? root.color : "transparent"
        border.width: root.open || _area.lit ? Theme.border.selectedWidth : Theme.border.width
        border.color: root.open || _area.lit ? Theme.accent : Theme.outline
    }

    PointerArea {
        id: _area
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    HoverTip {
        target: root
        shown: _area.containsMouse
        text: root.tooltip
    }
}
