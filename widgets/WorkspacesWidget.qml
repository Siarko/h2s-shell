import QtQuick
import QtQuick.Layouts
import qs.singletons

Item {
    Layout.fillHeight: true
    Layout.topMargin: 5
    Layout.bottomMargin: 5
    implicitWidth: wsRow.width + 16

    Rectangle {
        anchors.fill: parent
        radius: 5
        color: Theme.cellDefault
    }

    Row {
        id: wsRow
        anchors.centerIn: parent
        spacing: 4

        Repeater {
            model: Workspaces.workspaces
            delegate: Rectangle {
                required property var modelData
                width: Math.max(22, wsText.implicitWidth + 8)
                height: 22
                radius: 4
                color: modelData.focused ? Theme.cellAccent : (modelData.active ? Theme.cellAccentSecondary : "transparent")

                Text {
                    id: wsText
                    text: modelData.name || modelData.id
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    color: Theme.textPrimary
                    anchors.centerIn: parent
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: Workspaces.activate(modelData)
                }
            }
        }
    }
}
