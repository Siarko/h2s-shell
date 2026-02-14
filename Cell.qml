import QtQuick
import QtQuick.Layouts

// Reusable interactive bar widget with click and hover signals
Item {
    id: container
    property alias cellColor: rectangle.color
    // Emitted on click, carries the cell's color
    signal plonked(cellColor: color)
    // Emitted on mouse enter (true) and exit (false)
    signal hover(status: bool)

    Layout.fillHeight: true
    Layout.preferredHeight: 20
    Layout.topMargin: 5
    Layout.bottomMargin: 5
    Layout.minimumWidth: 40
    // Layout.fillWidth: true
    // Layout.preferredWidth: 100

    default property alias content: rectangle.data

    Rectangle {
        id: rectangle
        radius: 5
        anchors.fill: parent
    }

    // Extends 5px below the cell to prevent hover gaps between bar and popup
    MouseArea {
        // anchors.top: parent.top
        // anchors.left: parent.left
        // anchors.right: parent.right
        //
        // height: parent.height + 5
        anchors.fill: parent
        hoverEnabled: true

        onClicked: container.plonked(container.cellColor)
        onEntered: container.hover(true)
        onExited: container.hover(false)
    }
}
