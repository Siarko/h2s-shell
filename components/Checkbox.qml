import QtQuick
import qs.singletons

// A checkbox with an optional label beside it. Clicking either, or Space while it has the
// focus, emits `toggled`; the owner flips `checked`, so the box can follow state kept
// elsewhere (a calendar enabled in GoogleCalendar, say). Takes the focus on Tab; an owner
// that wants Tab to go somewhere particular sets `Keys.onTabPressed`.
Item {
    id: root

    property bool checked: false
    property string label: ""

    signal toggled

    implicitWidth: _row.implicitWidth
    implicitHeight: 22
    activeFocusOnTab: true

    Keys.onSpacePressed: root.toggled()

    Row {
        id: _row
        height: parent.height
        spacing: 6

        Rectangle {
            width: 14
            height: 14
            radius: Theme.checkbox.radius
            anchors.verticalCenter: parent.verticalCenter
            color: root.checked ? Theme.accent : "transparent"
            border.color: root.activeFocus ? Theme.textSecondary : (root.checked ? Theme.accent : Theme.textDisabled)
            border.width: Theme.border.width

            Text {
                anchors.centerIn: parent
                visible: root.checked
                text: "✓"
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeTiny
            }
        }

        Text {
            visible: root.label !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            color: Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
