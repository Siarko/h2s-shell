import QtQuick
import Quickshell
import qs.components
import QtQuick.Layouts
import qs.singletons

// The password prompt: a view of Lockscreen.view (LockRules.view). It shows what the rules
// say — busy ("Verifying…", or "Unlocking…" while an unlock waits for the compositor), the
// error, a notice, the placeholder or PAM's question, the passive methods' lines —
// and keeps only the half-typed text. The field never has keyboard focus: keys reach it as
// the rules' forwardKey effects through applyKey() (see LockSurface.qml), and it empties
// only when `fieldEpoch` changes — when the rules took the input, moved the prompt or put
// it to sleep — never on its own when something is submitted.
Item {
    id: root
    implicitWidth: 320
    implicitHeight: _col.implicitHeight + 48

    // LockRules.view(state), from the surface
    required property var view
    // Whether this instance shows the prompt (view.promptSurface is its surface)
    property bool awake: false
    // Caps Lock is known to be on (Lockscreen.capsLock): said under the field
    property bool capsLock: false

    // Enter, or the Unlock button: the field's text, for the rules' `submit`
    signal submitted(string text)

    readonly property int fieldEpoch: view.fieldEpoch
    onFieldEpochChanged: _input.text = ""

    // A forwardKey effect: a character inserted, Enter submitting, Backspace, Delete and
    // the cursor keys editing (LockIoRules.editField)
    function applyKey(key, text) {
        const edited = LockIoRules.editField({ text: _input.text, cursor: _input.cursorPosition }, key, text);
        if (edited.text !== _input.text)
            _input.text = edited.text;
        _input.cursorPosition = edited.cursor;
        if (edited.submit)
            root.submitted(_input.text);
    }

    readonly property bool _showError: view.error !== ""

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
            objectName: "error"
            Layout.fillWidth: true
            visible: root._showError
            text: root.view.error
            textFormat: Text.PlainText
            Accessible.role: Accessible.AlertMessage
            Accessible.name: text
            color: Theme.error
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        // Information that is no error: the compositor has not confirmed the lock yet
        Text {
            objectName: "notice"
            Layout.fillWidth: true
            visible: root.view.notice !== ""
            text: root.view.notice
            textFormat: Text.PlainText
            color: Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        // PAM's question in full, when it is too long for the field's placeholder (which
        // elides): "Enter the code sent to the phone ending in …" must not lose its end
        Text {
            objectName: "question"
            Layout.fillWidth: true
            visible: _placeholder.truncated
            text: root.view.placeholder
            textFormat: Text.PlainText
            color: Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Theme.lock.controlHeight
            radius: Theme.lock.controlRadius
            color: Theme.glass
            // Red while the error stands and nothing new is typed
            border.color: root._showError && _input.text === ""
                ? Theme.error
                : (root.awake ? Theme.glassBorderFocus : Theme.glassBorder)
            border.width: Theme.border.width

            Text {
                id: _placeholder
                objectName: "placeholder"
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 12 }
                text: root.view.placeholder
                textFormat: Text.PlainText
                color: Theme.glassTextMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                elide: Text.ElideRight
                visible: _input.text === ""
            }

            TextInput {
                id: _input
                objectName: "field"
                // A long password scrolls inside the field rather than running over its edge
                clip: true
                selectionColor: Theme.selection
                selectedTextColor: Theme.selectedText
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 12 }
                echoMode: root.view.answerVisible ? TextInput.Normal : TextInput.Password
                inputMethodHints: Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                color: root.view.busy ? Theme.glassTextMuted : Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                font.letterSpacing: root.view.answerVisible ? 0 : Theme.passwordLetterSpacing
                // Never focused: keys come only through applyKey (LockSurface.qml)
                focus: false
                activeFocusOnPress: false
                activeFocusOnTab: false
                selectByMouse: false
                cursorVisible: root.awake
                Accessible.role: Accessible.EditableText
                Accessible.passwordEdit: echoMode === TextInput.Password
                Accessible.name: root.view.placeholder
            }
        }

        // The most common reason for a password that is "wrong"
        Text {
            objectName: "capsLock"
            Layout.fillWidth: true
            visible: root.capsLock
            text: "Caps Lock is on"
            color: Theme.warning
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            horizontalAlignment: Text.AlignHCenter
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Theme.lock.controlHeight
            radius: Theme.lock.controlRadius
            color: (root.view.busy || _unlockHover.lit)
                ? Theme.glassHover
                : Theme.glassRaised

            Behavior on color { ColorAnimation { duration: Theme.duration("state"); easing: Theme.curve("state") } }

            Accessible.role: Accessible.Button
            Accessible.name: root.view.buttonText

            Text {
                objectName: "button"
                anchors.centerIn: parent
                text: root.view.buttonText
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
            }

            PointerArea {
                id: _unlockHover
                enabled: !root.view.busy
                cursorShape: Qt.PointingHandCursor
                onClicked: root.submitted(_input.text)
            }
        }

        // The ways in that need nothing typed: what each is doing, from the rules
        // ("Touch the fingerprint reader", PAM's own "Failed to match fingerprint", "not
        // available, trying again later"). A fresh array on every view: keyed by name
        // (KeyedModel, "The Repeater crash" in docs/ARCHITECTURE.md)
        KeyedModel { id: _methodsModel; values: root.view.methods; keyProp: "name" }
        Repeater {
            model: _methodsModel.model

            Text {
                required property string modelData
                readonly property var method: _methodsModel.byKey[modelData] ?? ({})
                Layout.fillWidth: true
                visible: method.visible ?? false
                text: method.text ?? ""
                textFormat: Text.PlainText
                color: method.isError ? Theme.error : Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
        }
    }
}
