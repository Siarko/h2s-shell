import QtQuick
import QtQuick.Layouts

Item {
    id: container
    property alias cellColor: rectangle.color
    signal plonked(cellColor: color)
    signal hover(status: bool)

    Layout.fillHeight: true
    Layout.preferredHeight: 20
    Layout.topMargin: 5
    Layout.bottomMargin: 5
    Layout.minimumWidth: 40
    Layout.fillWidth: true

    Rectangle {
        id: rectangle
        radius: 5
        anchors.fill: parent
    }

    MouseArea {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right

        height: parent.height + 5
        hoverEnabled: true

        onClicked: container.plonked(container.cellColor)
        onEntered: container.hover(true)
        onExited: container.hover(false)
    }
}
