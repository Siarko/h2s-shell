import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.singletons

// The polkit prompt (Authentication): a program asks for an administrator's password. Over
// the focused screen, the rest dimmed, with the keyboard to itself — what the password is
// typed into goes nowhere else. Says what asks (the message, the action), lets the account
// be picked when several can answer, shows PAM's messages and a wrong password, and asks
// again. The lock screen card's look.
//
// polkit's helper runs one PAM stack, and where a fingerprint reader comes first PAM sends
// only its messages for up to half a minute before it asks for the password. So the field
// is there from the start: a password typed and Entered early is held and sent the moment
// PAM asks for it, and the line under PAM's message says what the prompt waits for
// (PolkitRules.conversationHint — from the messages that arrived, not their wording). With
// the password first (programs.h2s-shell.polkit.passwordFirst), Enter on an empty field
// goes on to the reader. The password is never logged or copied, and is cleared as it is
// submitted, cancelled, or the request ends.
//
// Under the title, "As user" first (polkit/AuthAnnouncement.qml). A request that is a run of
// the shell's queue (`announcement`: PrivilegedRuns.announcementFor) also says who asks and
// what for: "Module", "Authorization" and the command one click away — for a module's prompt
// polkit's message and action go there too, as they repeat the command; elsewhere they are
// the description over the field (PolkitRules.promptLayout). Every text here is plain text:
// polkit's message and action, PAM's words and the accounts' names too.
PanelWindow {
    id: root

    required property var flow
    // { module, authorization, command } for a run of the shell's queue, else null
    property var announcement: null

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "h2s-auth"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    readonly property var _identities: flow?.identities ?? []
    // What the stack polkit runs asks first ("fingerprint-first", "password-first", …)
    readonly property string _stack: Authentication.pamStack
    // This attempt's conversation as it arrived (PolkitRules.conversationStep), and what
    // it means for the field and the line under PAM's message
    property var _conversation: PolkitRules.conversationStart()
    readonly property string _phase: PolkitRules.conversationPhase(_conversation)
    readonly property var _hint: PolkitRules.conversationHint(_conversation, _stack, _held)
    // A password Entered before PAM asked for it: it stays in the field — never copied,
    // never logged — and goes the moment the password is asked for. Editing lets it go.
    property bool _held: false
    property string _error: ""

    function _step(event) {
        _conversation = PolkitRules.conversationStep(_conversation, event);
    }

    // The field's text: sent when asked for, held until then
    function _submit() {
        if (!flow)
            return;
        const text = _input.text;
        if (_conversation.asked) {
            if (text === "" && !PolkitRules.emptyAnswerAllowed(_conversation, _stack))
                return;
            _error = "";
            _held = false;
            flow.submit(text);
            _input.text = "";
            _step({ kind: "answered", empty: text === "" });
            return;
        }
        if (text !== "")
            _held = true;
    }

    function _sendHeld() {
        if (PolkitRules.sendHeldNow(_conversation, _held))
            _submit();
    }

    function _cancel() {
        _forget();
        flow?.cancelAuthenticationRequest();
    }

    // Nothing of a password outlives its request
    function _forget() {
        _held = false;
        _input.text = "";
    }

    function _nameOf(identity) {
        return identity?.displayName ?? String(identity ?? "");
    }

    // The next queued request can arrive in this same window: a fresh start
    onFlowChanged: {
        _announcement.commandOpen = false;
        _forget();
        _error = "";
        _conversation = PolkitRules.conversationStart();
        if ((flow?.supplementaryMessage ?? "") !== "")
            _step({ kind: "message" });
        if (flow?.isResponseRequired)
            _step({ kind: "request", echo: flow.responseVisible });
        _input.forceActiveFocus();
    }
    Component.onDestruction: _forget()

    Connections {
        target: root.flow
        ignoreUnknownSignals: true
        function onAuthenticationFailed() {
            root._step({ kind: "failed" });
            root._error = "That was not accepted. Try again.";
            _input.forceActiveFocus();
        }
        function onIsResponseRequiredChanged() {
            if (root.flow?.isResponseRequired) {
                // A shown question asks something else: what was typed for the password
                // must not appear in it
                if (root.flow.responseVisible && !root._conversation.asked)
                    root._forget();
                root._step({ kind: "request", echo: root.flow.responseVisible });
                _input.forceActiveFocus();
                root._sendHeld();
            }
        }
        // An info or error message from PAM (a fingerprint reader's "Place your finger…").
        // The same text twice in a row does not notify; the phase only needs "one came".
        function onSupplementaryMessageChanged() {
            if ((root.flow?.supplementaryMessage ?? "") !== "")
                root._step({ kind: "message" });
        }
        // Another account picked: Quickshell cancels the attempt and starts a new one
        function onSelectedIdentityChanged() {
            root._forget();
            root._step({ kind: "restarted" });
        }
    }

    Component.onCompleted: {
        if ((flow?.supplementaryMessage ?? "") !== "")
            _step({ kind: "message" });
        if (flow?.isResponseRequired)
            _step({ kind: "request", echo: flow.responseVisible });
        _input.forceActiveFocus();
    }

    // Esc cancels wherever the focus is in the prompt (the field, the account picker): keys
    // a child does not take come up to this scope
    FocusScope {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root._cancel()

        // The rest of the screen, dimmed; a click there does nothing (the prompt stays until
        // answered or cancelled) but gives the field its focus back
        Rectangle {
            anchors.fill: parent
            color: Theme.scrim
            opacity: 0.7
            MouseArea {
                anchors.fill: parent
                onClicked: _input.forceActiveFocus()
            }
        }

        Item {
            id: _card
            anchors.centerIn: parent
            width: Math.min(400, parent.width - 32)
            height: _column.implicitHeight + 48

            AuthCard {
                anchors.fill: parent
            }

            ColumnLayout {
                id: _column
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
                spacing: 12

                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: "Authentication required"
                    color: Theme.textPrimary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeHeading
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }

                // Who answers; who asks and what for, for a run of the shell's queue
                AuthAnnouncement {
                    id: _announcement
                    Layout.fillWidth: true
                    announcement: root.announcement
                    identityNames: root._identities.map(identity => root._nameOf(identity))
                    identityIndex: root._identities.indexOf(root.flow?.selectedIdentity)
                    polkitMessage: root.flow?.message ?? ""
                    actionId: root.flow?.actionId ?? ""
                    onCommandToggled: _input.forceActiveFocus()
                    onIdentityPicked: index => root.flow.selectedIdentity = root._identities[index]
                }

                // What asks, where polkit's message is the description
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    visible: _announcement.layout.polkitMessage === "top"
                    text: root.flow?.message ?? ""
                    wrapMode: Text.WordWrap
                    color: Theme.textPrimary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    visible: _announcement.layout.polkitMessage === "top" && (root.flow?.actionId ?? "") !== ""
                    text: root.flow?.actionId ?? ""
                    wrapMode: Text.WrapAnywhere
                    color: Theme.glassTextMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    horizontalAlignment: Text.AlignHCenter
                }

                // The last attempt was not accepted
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    visible: root._error !== ""
                    text: root._error
                    wrapMode: Text.WordWrap
                    color: Theme.error
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    horizontalAlignment: Text.AlignHCenter
                }

                // PAM's message (a fingerprint reader asking for a finger, its "no match")
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: root._phase === "asked" || root._phase === "starting" ? "" : (root.flow?.supplementaryMessage ?? "")
                    wrapMode: Text.WordWrap
                    color: root.flow?.supplementaryIsError ? Theme.error : Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    horizontalAlignment: Text.AlignHCenter
                }

                // The field: there from the start, so that a password can be typed while a
                // reader is asked first
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: Theme.lock.controlHeight
                    radius: Theme.lock.controlRadius
                    color: Theme.glass
                    border.color: root._error !== "" ? Theme.error : (_input.activeFocus ? Theme.glassBorderFocus : Theme.glassBorder)
                    border.width: Theme.border.width

                    Text {
                        textFormat: Text.PlainText
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
                        // Shown only for a question PAM marks as visible; a password typed early
                        // is hidden
                        readonly property bool _visible: root._conversation.asked && root._conversation.echo
                        echoMode: _visible ? TextInput.Normal : TextInput.Password
                        inputMethodHints: Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                        color: root._held || root._phase === "checking" ? Theme.glassTextMuted : Theme.textPrimary
                        selectionColor: Theme.selection
                        selectedTextColor: Theme.selectedText
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        font.letterSpacing: _visible ? 0 : 4
                        focus: true
                        onTextChanged: {
                            root._held = false;
                            if (text !== "")
                                root._error = "";
                        }
                        onAccepted: root._submit()
                        Keys.onEscapePressed: root._cancel()
                    }
                }

                // What the prompt waits for and what can be done (PolkitRules.conversationHint)
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: root._hint.text
                    wrapMode: Text.WordWrap
                    color: root._hint.error ? Theme.error : Theme.glassTextMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    horizontalAlignment: Text.AlignHCenter
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
                            textFormat: Text.PlainText
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
                        primary: true
                        available: root._conversation.asked
                            ? _input.text !== "" || PolkitRules.emptyAnswerAllowed(root._conversation, root._stack)
                            : _input.text !== "" && !root._held
                        label: root._phase === "checking" ? "Checking…"
                            : root._held ? "Waiting…"
                            : root._conversation.asked && _input.text === "" && PolkitRules.emptyAnswerAllowed(root._conversation, root._stack) ? "Use fingerprint"
                            : "Authenticate"
                        onClicked: {
                            root._submit();
                            _input.forceActiveFocus();
                        }
                    }
                }
            }
        }
    }
}
