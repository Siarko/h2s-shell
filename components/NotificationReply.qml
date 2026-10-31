import QtQuick
import QtQuick.Layouts
import qs.singletons

// A notification's inline reply: a field and Send. Enter sends too; an empty reply is not
// sent.
RowLayout {
    id: root

    property color fieldColor: Theme.surfaceSunken

    signal sent(string text)

    function _send() {
        if (_replyInput.text.length > 0)
            sent(_replyInput.text);
    }

    spacing: 6

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 28
        radius: Theme.notificationCard.controlRadius
        color: root.fieldColor

        Text {
            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
            text: "Reply…"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            color: Theme.textMuted
            verticalAlignment: Text.AlignVCenter
            visible: _replyInput.text.length === 0
        }

        TextInput {
            id: _replyInput
            selectionColor: Theme.selection
            selectedTextColor: Theme.selectedText
            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            color: Theme.textPrimary
            verticalAlignment: TextInput.AlignVCenter
            onAccepted: root._send()
        }
    }

    Rectangle {
        implicitWidth: 48
        implicitHeight: 28
        radius: Theme.notificationCard.controlRadius
        color: Theme.accent

        Text {
            anchors.centerIn: parent
            text: "Send"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.textPrimary
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root._send()
        }
    }
}
