import QtQuick
import qs.components
import QtQuick.Layouts
import Quickshell.Services.Pam
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

    function _tryAuth() {
        if (_pam.active) return
        _failed = false
        _pam.start()
    }

    PamContext {
        id: _pam
        config: "login"
        onResponseRequiredChanged: if (responseRequired) respond(_input.text)
        onCompleted: result => {
            if (result === PamResult.Success) {
                Lockscreen.unlock()
            } else {
                _errorMessage = result === PamResult.MaxTries
                    ? "Too many attempts"
                    : "Authentication failed"
                _failed = true
                _input.text = ""
                _input.forceActiveFocus()
            }
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
                text: "Password"
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
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                color: _pam.active ? Theme.glassTextMuted : Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                font.letterSpacing: 4
                focus: true
                readOnly: _pam.active
                onTextChanged: { root.activity(); if (text !== "") root._failed = false }
                onAccepted: root._tryAuth()
                Keys.onEscapePressed: Lockscreen.unlock()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Theme.lock.controlHeight
            radius: Theme.lock.controlRadius
            color: (_pam.active || _unlockHover.lit)
                ? Theme.glassHover
                : Theme.glassRaised

            Behavior on color { ColorAnimation { duration: Theme.duration("state"); easing: Theme.curve("state") } }

            Text {
                anchors.centerIn: parent
                text: _pam.active ? "Verifying…" : "Unlock"
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
            }

            PointerArea {
                id: _unlockHover
                enabled: !_pam.active
                cursorShape: Qt.PointingHandCursor
                onClicked: root._tryAuth()
            }
        }
    }
}
