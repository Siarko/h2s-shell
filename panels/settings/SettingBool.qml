import QtQuick
import QtQuick.Layouts
import qs.singletons

RowLayout {
    property string label
    property bool value: false
    property bool disabled: false

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

    Rectangle {
        id: toggle
        property bool checked: value
        width: 36
        height: 20
        radius: 10
        color: checked ? Theme.accent : Theme.surface

        Rectangle {
            x: parent.checked ? parent.width - width - 2 : 2
            y: 2
            width: 16
            height: 16
            radius: 8
            color: Theme.textPrimary
            Behavior on x {
                NumberAnimation {
                    duration: Theme.duration("state")
                    easing: Theme.curve("state")
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: !toggle.parent.disabled
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: toggle.parent.value = !toggle.parent.value
        }
    }
}
