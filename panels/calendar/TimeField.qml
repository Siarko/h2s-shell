import QtQuick
import qs.singletons

// Segmented HH:MM time input.
// - Click anywhere in the field → hours segment is focused and selected
// - Type 2 digits for hours → auto-advances to minutes
// - Tab in hours → minutes; Shift+Tab in minutes → hours
// - Right arrow at end of hours → minutes; Left arrow at start of minutes → hours
// - Only digit keys are accepted; all other printable keys are suppressed
// - text: "HH:MM" string, or "" when both segments are empty
// - Tab in minutes → tabOutForward signal (caller advances to next field)
// - Shift+Tab in hours → tabOutBackward signal (caller goes to prev field)
Item {
    id: root

    implicitHeight: 28

    readonly property string text: {
        var h = _hInput.text
        var m = _mInput.text
        if (h.length === 0 && m.length === 0) return ""
        return ("0" + h).slice(-2) + ":" + ("0" + m).slice(-2)
    }

    function setValue(timeStr) {
        if (!timeStr) {
            _hInput.text = ""
            _mInput.text = ""
            return
        }
        var parts = timeStr.split(":")
        _hInput.text = parts.length > 0 ? parts[0] : ""
        _mInput.text = parts.length > 1 ? parts[1] : ""
    }

    function clear() {
        _hInput.text = ""
        _mInput.text = ""
    }

    signal tabOutForward()   // emitted: Tab pressed while in minutes segment
    signal tabOutBackward()  // emitted: Shift+Tab pressed while in hours segment

    function focusHours() {
        _hInput.forceActiveFocus()
        _hInput.selectAll()
    }
    function focusMinutes() {
        _mInput.forceActiveFocus()
        _mInput.selectAll()
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.popupBackground
        border.color: (_hInput.activeFocus || _mInput.activeFocus) ? Theme.textSecondary : Theme.textDim
        radius: 4

        // Clicking anywhere outside the TextInputs (e.g. padding) focuses hours
        MouseArea {
            anchors.fill: parent
            onClicked: {
                _hInput.forceActiveFocus()
                _hInput.selectAll()
            }
        }

        Row {
            anchors.centerIn: parent
            spacing: 0

            // Hours segment
            TextInput {
                id: _hInput
                width: 18
                height: 20
                maximumLength: 2
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: 12
                horizontalAlignment: TextInput.AlignHCenter
                verticalAlignment: TextInput.AlignVCenter

                onActiveFocusChanged: if (activeFocus) selectAll()

                onTextChanged: {
                    if (text.length === 2) {
                        _mInput.forceActiveFocus()
                        _mInput.selectAll()
                    }
                }

                Keys.onPressed: (event) => {
                    // Shift+Tab → escape backward out of TimeField
                    if (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier)) {
                        if (text.length < 2) text = ("00" + text).slice(-2)
                        root.tabOutBackward()
                        event.accepted = true
                        return
                    }
                    // Tab → advance to minutes
                    if (event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier)) {
                        if (text.length < 2) text = ("00" + text).slice(-2)
                        _mInput.forceActiveFocus()
                        _mInput.selectAll()
                        event.accepted = true
                        return
                    }
                    // Right arrow at end → advance to minutes
                    if (event.key === Qt.Key_Right
                            && cursorPosition === length
                            && selectedText.length === 0) {
                        _mInput.forceActiveFocus()
                        _mInput.selectAll()
                        event.accepted = true
                        return
                    }
                    if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
                        var digit = event.key - Qt.Key_0
                        // Position being typed: selectionStart when there is a selection,
                        // otherwise cursorPosition.
                        var pos = (selectionStart === selectionEnd) ? cursorPosition : selectionStart
                        if (pos === 0) {
                            // First digit of hours: 0-2 only (no valid 24h hour starts with 3-9)
                            if (digit > 2) { event.accepted = true; return }
                        } else if (pos === 1) {
                            // Second digit of hours: if first digit is 2, only 0-3 allowed
                            if (parseInt(text[0]) === 2 && digit > 3) { event.accepted = true; return }
                        }
                        return
                    }
                    // Allow navigation and editing keys; reject everything else
                    var allowed = event.key === Qt.Key_Backspace
                        || event.key === Qt.Key_Delete
                        || event.key === Qt.Key_Left
                        || event.key === Qt.Key_Right
                        || event.key === Qt.Key_Home
                        || event.key === Qt.Key_End
                        || (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier))
                    if (!allowed) event.accepted = true
                }
            }

            Text {
                text: ":"
                width: 8
                height: 20
                color: (_hInput.activeFocus || _mInput.activeFocus)
                    ? Theme.textSecondary : Theme.textTertiary
                font.family: Theme.fontFamily
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            // Minutes segment
            TextInput {
                id: _mInput
                width: 18
                height: 20
                maximumLength: 2
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: 12
                horizontalAlignment: TextInput.AlignHCenter
                verticalAlignment: TextInput.AlignVCenter

                onActiveFocusChanged: if (activeFocus) selectAll()

                Keys.onPressed: (event) => {
                    // Tab → escape forward out of TimeField
                    if (event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier)) {
                        if (text.length < 2) text = ("00" + text).slice(-2)
                        root.tabOutForward()
                        event.accepted = true
                        return
                    }
                    // Shift+Tab → go back to hours
                    if (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier)) {
                        if (text.length < 2) text = ("00" + text).slice(-2)
                        _hInput.forceActiveFocus()
                        _hInput.selectAll()
                        event.accepted = true
                        return
                    }
                    // Left arrow at start → go back to hours
                    if (event.key === Qt.Key_Left
                            && cursorPosition === 0
                            && selectedText.length === 0) {
                        _hInput.forceActiveFocus()
                        _hInput.selectAll()
                        event.accepted = true
                        return
                    }
                    if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
                        var digit = event.key - Qt.Key_0
                        var pos = (selectionStart === selectionEnd) ? cursorPosition : selectionStart
                        if (pos === 0) {
                            // First digit of minutes: 0-5 only (no valid minute starts with 6-9)
                            if (digit > 5) { event.accepted = true; return }
                        }
                        return
                    }
                    var allowed = event.key === Qt.Key_Backspace
                        || event.key === Qt.Key_Delete
                        || event.key === Qt.Key_Left
                        || event.key === Qt.Key_Right
                        || event.key === Qt.Key_Home
                        || event.key === Qt.Key_End
                        || (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier))
                    if (!allowed) event.accepted = true
                }
            }
        }

        // Placeholder — shown only when both segments are empty and neither is focused
        Text {
            anchors { fill: parent; leftMargin: 6; topMargin: 4; bottomMargin: 4 }
            text: "HH:MM"
            color: Theme.textTertiary
            font.family: Theme.fontFamily
            font.pixelSize: 12
            verticalAlignment: Text.AlignVCenter
            visible: _hInput.text.length === 0 && _mInput.text.length === 0
                     && !_hInput.activeFocus && !_mInput.activeFocus
            enabled: false
        }
    }
}
