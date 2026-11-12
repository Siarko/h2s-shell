import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.singletons

// The polkit prompt (Authentication): a program asks for an administrator's password. Over
// the focused screen, the rest dimmed, with the keyboard to itself — what the password is
// typed into goes nowhere else. Says what asks (the message, the action), lets the account
// be picked when several can answer, shows PAM's messages (a fingerprint reader's needs no
// password) and a wrong password, and asks again. The lock screen card's look. The
// password is never logged or kept: the field is cleared as it is submitted.
PanelWindow {
    id: root

    required property var flow

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "h2s-auth"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    readonly property var _identities: flow?.identities ?? []
    // Submitted, waiting for polkit's answer
    property bool _waiting: false
    property string _error: ""

    function _submit() {
        if (!flow || !flow.isResponseRequired || _waiting)
            return;
        _waiting = true;
        _error = "";
        flow.submit(_input.text);
        _input.text = "";
    }

    function _cancel() {
        flow?.cancelAuthenticationRequest();
    }

    function _nameOf(identity) {
        return identity?.displayName ?? String(identity ?? "");
    }

    Connections {
        target: root.flow
        ignoreUnknownSignals: true
        function onAuthenticationFailed() {
            root._waiting = false;
            root._error = "That was not accepted. Try again.";
            _input.forceActiveFocus();
        }
        function onIsResponseRequiredChanged() {
            if (root.flow?.isResponseRequired) {
                root._waiting = false;
                _input.forceActiveFocus();
            }
        }
    }

    Component.onCompleted: _input.forceActiveFocus()

    // The rest of the screen, dimmed; a click there does nothing (the prompt stays until
    // answered or cancelled)
    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
        opacity: 0.7
        MouseArea { anchors.fill: parent }
    }

    Item {
        id: _card
        anchors.centerIn: parent
        width: Math.min(400, parent.width - 32)
        height: _column.implicitHeight + 48

        Rectangle {
            anchors.fill: parent
            radius: Theme.lock.cardRadius
            color: Theme.overlay
            border.color: Theme.glassBorder
            border.width: Theme.border.width
        }

        ColumnLayout {
            id: _column
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
            spacing: 12

            Text {
                Layout.fillWidth: true
                text: "Authentication required"
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeHeading
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }

            // What asks
            Text {
                Layout.fillWidth: true
                text: root.flow?.message ?? ""
                wrapMode: Text.WordWrap
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                Layout.fillWidth: true
                visible: (root.flow?.actionId ?? "") !== ""
                text: root.flow?.actionId ?? ""
                wrapMode: Text.WrapAnywhere
                color: Theme.glassTextMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                horizontalAlignment: Text.AlignHCenter
            }

            // Which account answers, when several can
            Dropdown {
                visible: root._identities.length > 1
                Layout.fillWidth: true
                options: root._identities.map((identity, index) => ({ value: index, label: root._nameOf(identity) }))
                value: root._identities.indexOf(root.flow?.selectedIdentity)
                onPicked: index => root.flow.selectedIdentity = root._identities[index]
            }
            Text {
                Layout.fillWidth: true
                visible: root._identities.length === 1
                text: "As " + root._nameOf(root._identities[0])
                color: Theme.glassTextMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                horizontalAlignment: Text.AlignHCenter
            }

            // PAM's message (a fingerprint reader asking for a finger), or the last error
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: root._error !== "" ? root._error : (root.flow?.supplementaryMessage ?? "")
                wrapMode: Text.WordWrap
                color: root._error !== "" || root.flow?.supplementaryIsError ? Theme.error : Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                horizontalAlignment: Text.AlignHCenter
            }

            Rectangle {
                Layout.fillWidth: true
                visible: root.flow?.isResponseRequired ?? false
                implicitHeight: Theme.lock.controlHeight
                radius: Theme.lock.controlRadius
                color: Theme.glass
                border.color: root._error !== "" ? Theme.error : (_input.activeFocus ? Theme.glassBorderFocus : Theme.glassBorder)
                border.width: Theme.border.width

                Text {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12 }
                    // PAM's own words ("Password:"), without the colon
                    text: (root.flow?.inputPrompt ?? "").replace(/:\s*$/, "") || "Password"
                    color: Theme.glassTextMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    visible: _input.text === ""
                }

                TextInput {
                    id: _input
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 12 }
                    echoMode: root.flow?.responseVisible ? TextInput.Normal : TextInput.Password
                    inputMethodHints: Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                    color: root._waiting ? Theme.glassTextMuted : Theme.textPrimary
                    selectionColor: Theme.selection
                    selectedTextColor: Theme.selectedText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    font.letterSpacing: root.flow?.responseVisible ? 0 : 4
                    focus: true
                    readOnly: root._waiting
                    onTextChanged: if (text !== "") root._error = ""
                    onAccepted: root._submit()
                    Keys.onEscapePressed: root._cancel()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                component PromptButton: Rectangle {
                    id: _button
                    property string label: ""
                    property bool primary: false
                    property bool available: true
                    signal clicked()
                    Layout.fillWidth: true
                    implicitHeight: Theme.lock.controlHeight
                    radius: Theme.lock.controlRadius
                    opacity: available ? 1 : 0.5
                    color: _area.lit && available ? Theme.glassHover : (primary ? Theme.glassRaised : Theme.glass)
                    Behavior on color { ColorAnimation { duration: Theme.duration("state"); easing: Theme.curve("state") } }
                    Text {
                        anchors.centerIn: parent
                        text: _button.label
                        color: Theme.textPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                    }
                    PointerArea {
                        id: _area
                        centred: false
                        anchors.fill: parent
                        enabled: _button.available
                        cursorShape: Qt.PointingHandCursor
                        onClicked: _button.clicked()
                    }
                }

                PromptButton {
                    label: "Cancel"
                    onClicked: root._cancel()
                }
                PromptButton {
                    visible: root.flow?.isResponseRequired ?? false
                    primary: true
                    available: !root._waiting && _input.text !== ""
                    label: root._waiting ? "Checking…" : "Authenticate"
                    onClicked: root._submit()
                }
            }
        }
    }
}
