import QtQuick
import qs.singletons

// A one-line text field: a box with the input in it, a placeholder while it is empty, the
// accent around it while it has focus and red while `problem`. As tall as a line of its
// text needs, never less than 26 px. `password` hides the text, with an eye to show it;
// whether it shows is `revealed`, which the field toggles itself unless the owner keeps it
// (`ownsReveal: false`, listening to `revealToggled`) — e.g. per Wi-Fi network.
//
//   InputField { placeholder: "Name"; text: model.name; onAccepted: save(text) }
Rectangle {
    id: root

    property alias text: _input.text
    // The TextInput itself, for what this does not pass on (validator, maximumLength, …)
    property alias input: _input
    property string placeholder: ""
    property bool problem: false
    property bool password: false
    property bool revealed: false
    property bool ownsReveal: true
    property int fontSize: Theme.fontSizeBody
    property color fieldColor: Theme.surface
    // A border at rest too, not only while focused
    property bool outlined: false
    readonly property bool editing: _input.activeFocus

    signal accepted
    signal editingFinished
    signal textEdited
    signal revealToggled

    // Focus to the input, its text selected
    function focusAll() {
        _input.forceActiveFocus();
        _input.selectAll();
    }

    implicitWidth: 120
    implicitHeight: Math.max(26, _input.implicitHeight + 8)
    radius: Theme.field.radius
    color: fieldColor
    border.width: Theme.border.width
    border.color: problem ? Theme.error
        : _input.activeFocus ? Theme.accent
        : outlined ? Theme.outline : Qt.alpha(Theme.outline, 0)
    Behavior on border.color { ColorAnimation { duration: Theme.duration("state"); easing: Theme.curve("state") } }

    TextInput {
        id: _input
        selectionColor: Theme.selection
        selectedTextColor: Theme.selectedText
        anchors {
            left: parent.left
            right: _eye.visible ? _eye.left : parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: Theme.field.horizontalPadding
            rightMargin: _eye.visible ? 4 : Theme.field.horizontalPadding
        }
        verticalAlignment: TextInput.AlignVCenter
        echoMode: root.password && !root.revealed ? TextInput.Password : TextInput.Normal
        font.family: Theme.fontFamily
        font.pixelSize: root.fontSize
        color: Theme.textPrimary
        selectByMouse: true
        clip: true
        onAccepted: root.accepted()
        onEditingFinished: root.editingFinished()
        onTextEdited: root.textEdited()

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            visible: parent.text === "" && !parent.activeFocus && root.placeholder !== ""
            text: root.placeholder
            elide: Text.ElideRight
            font: parent.font
            color: Theme.textDisabled
        }
    }

    // Shows or hides a password
    Text {
        id: _eye
        visible: root.password
        anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
        text: root.revealed ? "󰛐" : "󰛑"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeMedium
        color: _eyeArea.containsMouse ? Theme.textSecondary : Theme.textMuted

        MouseArea {
            id: _eyeArea
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (root.ownsReveal)
                    root.revealed = !root.revealed;
                root.revealToggled();
            }
        }
    }
}
