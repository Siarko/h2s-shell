import QtQuick
import QtQuick.Layouts
import qs.singletons

RowLayout {
    property string label
    property int value
    property int from: 5
    property string suffix: ""
    property bool disabled: false
    signal valueEdited(int newValue)

    Layout.fillWidth: true
    Layout.preferredHeight: 44
    opacity: disabled ? 0.35 : 1.0

    Text {
        text: label
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBodyLarge
        color: Theme.textPrimary
        Layout.fillWidth: true
    }

    Row {
        spacing: 4

        Rectangle {
            width: 80
            height: 26
            radius: 6
            color: Theme.surface
            border.width: _input.activeFocus && !_input.acceptableInput ? 1 : 0
            border.color: Theme.error

            TextInput {
                id: _input
                anchors {
                    fill: parent
                    leftMargin: 8
                    rightMargin: 8
                }
                text: value
                readOnly: disabled
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: acceptableInput ? Theme.textPrimary : Theme.error
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: from }

                onTextEdited: {
                    if (acceptableInput)
                        valueEdited(parseInt(text))
                }

                onEditingFinished: {
                    if (!acceptableInput)
                        text = value
                }
            }
        }

        Text {
            visible: suffix !== ""
            text: suffix
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            color: Theme.textSecondary
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
