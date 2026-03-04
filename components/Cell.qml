import QtQuick
import QtQuick.Layouts
import qs.singletons

// Reusable interactive bar widget with click and hover signals
Item {
    id: container
    property color cellColor: Theme.cellDefault
    // When true, keeps the cell highlighted regardless of hover (e.g. while its popup is open)
    property bool active: false
    // Emitted on click, carries the cell's color
    signal plonked(cellColor: color)
    // Emitted on mouse enter (true) and exit (false)
    signal hover(status: bool)
    // Emitted on scroll wheel: delta in notches (±1, ±2, …); shift indicates shift key held
    signal scrolled(delta: real)
    // Emitted on middle mouse button click
    signal middleClicked

    Layout.fillHeight: true
    Layout.preferredHeight: 20
    Layout.topMargin: 5
    Layout.bottomMargin: 5
    Layout.minimumWidth: 40
    implicitWidth: contentItem.childrenRect.width + 16

    default property alias content: contentItem.data

    Rectangle {
        id: rectangle
        radius: 5
        anchors.fill: parent
        color: (mouseArea.containsMouse || container.active) ? Theme.cellHover : container.cellColor
    }

    // Free-standing item for measuring content size without anchoring loops
    Item {
        id: contentItem
        anchors.centerIn: parent
    }

    // Extends 5px below the cell to prevent hover gaps between bar and popup
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton

        onClicked: event => {
            if (event.button === Qt.MiddleButton)
                container.middleClicked();
            else
                container.plonked(container.cellColor);
        }
        onEntered: container.hover(true)
        onExited: container.hover(false)
        onWheel: event => container.scrolled(event.angleDelta.y * (1 / 8) / 14)
    }
}
