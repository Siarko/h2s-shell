import QtQuick
import QtQuick.Layouts
import qs.singletons

// A notification's inline reply: a field and Send. Enter sends too; an empty reply is not
// sent; Escape clears the field and lets go of the keyboard.
//
// The card's window takes the keyboard only while it is needed (`wantsKeyboard`): the
// pointer over the reply, or a reply being written. The HUD's toasts otherwise never take
// focus, so clicking one does not pull the keyboard from the app underneath.
RowLayout {
    id: root

    property color fieldColor: Theme.surfaceSunken
    // The sender's hint ("Reply to Anna…"), else ours
    property string placeholder: ""

    // Being written: focused, or holding text (focus can move away mid-reply and come back)
    readonly property bool engaged: _replyInput.activeFocus || _replyInput.text.length > 0
    readonly property bool wantsKeyboard: _hover.hovered || engaged

    signal sent(string text)

    function _send() {
        if (_replyInput.text.length === 0)
            return;
        const text = _replyInput.text;
        _replyInput.text = "";
        _replyInput.focus = false;
        sent(text);
    }

    // A new notification in the same card starts with an empty field
    function clear() {
        _replyInput.text = "";
        _replyInput.focus = false;
    }

    spacing: 6

    HoverHandler {
        id: _hover
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 28
        radius: Theme.notificationCard.controlRadius
        color: root.fieldColor
        border.width: _replyInput.activeFocus ? 1 : 0
        border.color: Theme.accent

        Text {
            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
            text: root.placeholder !== "" ? root.placeholder : "Reply…"
            elide: Text.ElideRight
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
            clip: true
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            color: Theme.textPrimary
            verticalAlignment: TextInput.AlignVCenter
            onAccepted: root._send()
            Keys.onEscapePressed: root.clear()
        }

        // The window gets the keyboard on a click (on demand), and the field its focus
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.IBeamCursor
            acceptedButtons: Qt.NoButton
        }
    }

    Rectangle {
        implicitWidth: 48
        implicitHeight: 28
        radius: Theme.notificationCard.controlRadius
        color: _replyInput.text.length > 0 ? Theme.accent : Theme.surfaceHover

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
