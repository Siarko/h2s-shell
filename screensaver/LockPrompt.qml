import QtQuick
import qs.components
import QtQuick.Layouts
import qs.singletons

Item {
    id: root
    implicitWidth: 320
    implicitHeight: _col.implicitHeight + 48

    signal activity

    property bool _failed: false
    property string _errorMessage: ""

    function reset() {
        _input.text = ""
        _failed = false
        _errorMessage = ""
    }

    onVisibleChanged: if (visible) _input.forceActiveFocus()

    // A character typed before the field could take it (the key that woke the prompt)
    function type(text) {
        if (text.length === 1 && text >= " " && text !== "\x7f")
            _input.insert(_input.length, text)
    }

    function _send() {
        if (LockAuth.verifying) return
        _failed = false
        LockAuth.submit(_input.text)
        // An answer to a further question: the field empties for the next one
        _input.text = ""
    }

    Connections {
        target: LockAuth
        function onRejected() {
            root._errorMessage = LockAuth.error
            root._failed = true
            _input.text = ""
            _input.forceActiveFocus()
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.lock.cardRadius
        color: Theme.overlay
        border.color: Theme.glassBorder
        border.width: Theme.border.width
    }

    ColumnLayout {
        id: _col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
        spacing: 12

        Text {
            Layout.fillWidth: true
            text: "Session locked"
            color: Theme.textPrimary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeHeading
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            Layout.fillWidth: true
            visible: _failed
            text: _errorMessage
            color: Theme.error
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            horizontalAlignment: Text.AlignHCenter
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Theme.lock.controlHeight
            radius: Theme.lock.controlRadius
            color: Theme.glass
            border.color: _failed
                ? Theme.error
                : (_input.activeFocus ? Theme.glassBorderFocus : Theme.glassBorder)
            border.width: Theme.border.width

            Text {
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12 }
                text: LockAuth.awaitingInput && LockAuth.question !== "" ? LockAuth.question : "Password"
                color: Theme.glassTextMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                visible: _input.text === ""
            }

            TextInput {
                id: _input
                selectionColor: Theme.selection
                selectedTextColor: Theme.selectedText
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 12 }
                echoMode: LockAuth.awaitingInput && LockAuth.answerVisible ? TextInput.Normal : TextInput.Password
                inputMethodHints: Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                color: LockAuth.verifying ? Theme.glassTextMuted : Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                font.letterSpacing: 4
                focus: true
                readOnly: LockAuth.verifying
                onTextChanged: { root.activity(); if (text !== "") root._failed = false }
                onAccepted: root._send()
                Keys.onEscapePressed: Lockscreen.unlock()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Theme.lock.controlHeight
            radius: Theme.lock.controlRadius
            color: (LockAuth.verifying || _unlockHover.lit)
                ? Theme.glassHover
                : Theme.glassRaised

            Behavior on color { ColorAnimation { duration: Theme.duration("state"); easing: Theme.curve("state") } }

            Text {
                anchors.centerIn: parent
                text: LockAuth.verifying ? "Verifying…" : "Unlock"
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
            }

            PointerArea {
                id: _unlockHover
                enabled: !LockAuth.verifying
                cursorShape: Qt.PointingHandCursor
                onClicked: root._send()
            }
        }

        // The ways in that need nothing typed, while they are waiting: what PAM last
        // said about each ("Place your finger…", "Failed to match fingerprint"), or
        // the method's own hint before it has said anything
        Repeater {
            model: [LockAuth.fingerprint, LockAuth.securityKey]

            Text {
                required property var modelData
                Layout.fillWidth: true
                visible: modelData.available
                text: modelData.message !== "" ? modelData.message : modelData.hint
                color: modelData.messageIsError ? Theme.error : Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
        }
    }
}
