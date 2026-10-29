import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.singletons

Item {
    id: _so
    property string label: ""
    property var options: []
    property var labels: []
    property string value: ""
    signal picked(string newValue)

    Layout.fillWidth: true
    implicitHeight: _soCol.implicitHeight + 8

    Column {
        id: _soCol
        width: _so.width
        spacing: 6

        Text {
            text: _so.label
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBodyLarge
            color: Theme.textPrimary
        }

        Row {
            spacing: 4

            Repeater {
                // ScriptModel, never the bare array — see "The Repeater crash"; the
                // options can be live (profile names)
                model: ScriptModel {
                    values: _so.options
                }

                Rectangle {
                    required property string modelData
                    required property int index
                    property bool selected: modelData === _so.value
                    width: _pillText.implicitWidth + 16
                    height: 26
                    radius: 6
                    color: selected ? Theme.accent : "transparent"
                    border.width: selected ? 0 : 1
                    border.color: Theme.outline

                    Text {
                        id: _pillText
                        anchors.centerIn: parent
                        text: _so.labels[index]
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        color: selected ? Theme.textPrimary : Theme.textSecondary
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: _so.picked(modelData)
                    }
                }
            }
        }
    }
}
