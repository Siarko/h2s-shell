import QtQuick
import QtQuick.Layouts
import qs.singletons

Item {
    id: root
    property string label
    property string value
    property bool disabled: false
    property int echoMode: TextInput.Normal
    property int inputWidthPercent: 30

    Layout.fillWidth: true
    Layout.preferredHeight: 44

    opacity: disabled ? 0.35 : 1.0

    Text {
        anchors.left: parent.left
        anchors.right: _inputRect.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: label
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBodyLarge
        color: Theme.textPrimary
        elide: Text.ElideRight
    }

    Rectangle {
        id: _inputRect
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width * (root.inputWidthPercent / 100)
        height: 26
        radius: 6
        color: Theme.cellDefault

        TextInput {
            anchors {
                fill: parent
                leftMargin: 8
                rightMargin: 8
            }
            text: value
            echoMode: root.echoMode
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            color: Theme.textPrimary
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            onTextEdited: root.value = text
        }
    }
}
