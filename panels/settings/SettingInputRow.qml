import QtQuick
import QtQuick.Layouts
import qs.singletons

RowLayout {
    property string label
    property string value
    property int echoMode: TextInput.Normal

    Layout.fillWidth: true
    Layout.preferredHeight: 44

    Text {
        text: label
        font.family: Theme.fontFamily
        font.pixelSize: 13
        color: Theme.textPrimary
        Layout.fillWidth: true
    }

    Rectangle {
        width: 130
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
            echoMode: parent.parent.echoMode
            font.family: Theme.fontFamily
            font.pixelSize: 12
            color: Theme.textPrimary
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            onTextEdited: parent.parent.value = text
        }
    }
}
