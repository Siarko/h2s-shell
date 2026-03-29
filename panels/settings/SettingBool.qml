import QtQuick
import QtQuick.Layouts
import qs.singletons

RowLayout {
    property string label
    property bool value: false

    Layout.fillWidth: true
    Layout.preferredHeight: 44

    Text {
        text: label
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBodyLarge
        color: Theme.textPrimary
        Layout.fillWidth: true
    }

    Rectangle {
        id: toggle
        property bool checked: value
        width: 36
        height: 20
        radius: 10
        color: checked ? Theme.sliderAccent : Theme.cellDefault

        Rectangle {
            x: parent.checked ? parent.width - width - 2 : 2
            y: 2
            width: 16
            height: 16
            radius: 8
            color: Theme.textPrimary
            Behavior on x {
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutQuad
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: toggle.parent.value = !toggle.parent.value
        }
    }
}
