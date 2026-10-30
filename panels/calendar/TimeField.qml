import QtQuick
import qs.singletons

// A time typed as two segments, hours and minutes, each with its placeholder (HH, MM).
// - Clicking anywhere in the field focuses the hours, selected.
// - Only digits that can still make a valid time are taken; an hour that can only be one
//   digit (3–9) is completed at once ("7" → 07) and the minutes are next. Two digits move
//   on to the minutes too.
// - Leaving a segment with one digit completes it: an hour is that hour ("1" → 01), a
//   minute is that many tens ("3" → 30).
// - Up and Down step the segment, wrapping; Backspace in empty minutes goes back to the
//   hours; Right at the end of the hours and Left at the start of the minutes move between
//   them.
// - Tab: hours → minutes → `tabOutForward` (the caller moves on); Shift+Tab: minutes →
//   hours → `tabOutBackward`.
// - `text` is "HH:MM", or "" when both segments are empty.
Item {
    id: root

    readonly property string text: {
        const hours = _hours.input.text;
        const minutes = _minutes.input.text;
        if (hours.length === 0 && minutes.length === 0)
            return "";
        return _hours.completed(hours) + ":" + _minutes.completed(minutes);
    }

    signal tabOutForward()
    signal tabOutBackward()

    function setValue(timeString) {
        const parts = (timeString || "").split(":");
        _hours.input.text = parts[0] ?? "";
        _minutes.input.text = parts[1] ?? "";
    }

    function clear() {
        setValue("");
    }

    function focusHours() {
        _hours.focusAll();
    }

    function focusMinutes() {
        _minutes.focusAll();
    }

    readonly property bool _editing: _hours.input.activeFocus || _minutes.input.activeFocus

    implicitHeight: Math.max(26, _digits.height + 8)

    // A segment is as wide as two digits, in the theme's font
    TextMetrics {
        id: _digits
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBody
        text: "88"
    }

    // One segment: two digits up to `maximum`, completed by `padLeft` (an hour: "1" → 01)
    // or on the right (minutes: "3" → 30); `firstDigitLimit` is the largest first digit a
    // two-digit value can have
    component Segment: Item {
        id: _segment
        property alias input: _input
        property int maximum: 59
        property int firstDigitLimit: 5
        property bool padLeft: false
        property string placeholder
        signal next
        signal previous
        signal outForward
        signal outBackward

        function completed(value) {
            if (value.length === 0)
                return "00";
            if (value.length === 1)
                return padLeft ? "0" + value : value + "0";
            return value;
        }

        function focusAll() {
            _input.forceActiveFocus();
            _input.selectAll();
        }

        function step(delta) {
            const current = parseInt(completed(_input.text));
            const value = ((isNaN(current) ? 0 : current) + delta + maximum + 1) % (maximum + 1);
            _input.text = ("0" + value).slice(-2);
            _input.selectAll();
        }

        width: Math.max(18, Math.ceil(_digits.advanceWidth) + 2)
        height: Math.max(20, Math.ceil(_digits.height))

        TextInput {
            id: _input
            selectionColor: Theme.selection
            selectedTextColor: Theme.selectedText
            anchors.fill: parent
            maximumLength: 2
            color: Theme.textPrimary
            font: _digits.font
            horizontalAlignment: TextInput.AlignHCenter
            verticalAlignment: TextInput.AlignVCenter

            onActiveFocusChanged: {
                if (activeFocus)
                    selectAll();
                else if (text.length === 1)
                    text = _segment.completed(text);
            }

            Keys.onPressed: event => {
                const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
                if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                    if (shift || event.key === Qt.Key_Backtab)
                        _segment.outBackward();
                    else
                        _segment.outForward();
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
                    _segment.step(event.key === Qt.Key_Up ? 1 : -1);
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Right && cursorPosition === length && selectedText.length === 0) {
                    _segment.next();
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Left && cursorPosition === 0 && selectedText.length === 0) {
                    _segment.previous();
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Backspace && length === 0) {
                    _segment.previous();
                    event.accepted = true;
                    return;
                }
                if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
                    const digit = event.key - Qt.Key_0;
                    // The position being typed: where the selection starts, or the cursor
                    const position = selectionStart !== selectionEnd ? selectionStart : cursorPosition;
                    if (position === 0 && digit > _segment.firstDigitLimit) {
                        // Can only be one digit: an hour completes at once, a minute cannot
                        if (_segment.padLeft) {
                            text = "0" + digit;
                            _segment.next();
                        }
                        event.accepted = true;
                        return;
                    }
                    if (position === 1 && parseInt(text[0]) * 10 + digit > _segment.maximum) {
                        event.accepted = true;
                        return;
                    }
                    return;
                }
                const editing = event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete
                    || event.key === Qt.Key_Left || event.key === Qt.Key_Right
                    || event.key === Qt.Key_Home || event.key === Qt.Key_End
                    || (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier));
                if (!editing)
                    event.accepted = true;
            }

            // Two digits typed: on to what comes next
            onTextEdited: if (length === 2) _segment.next()

            Text {
                anchors.fill: parent
                visible: parent.text === ""
                text: _segment.placeholder
                font: parent.font
                color: Theme.textDisabled
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.field.radius
        color: Theme.popupBackground
        border.width: Theme.border.width
        border.color: root._editing ? Theme.accent : Theme.outline
        Behavior on border.color { ColorAnimation { duration: Theme.duration("state"); easing: Theme.curve("state") } }

        // A click outside the segments focuses the hours
        MouseArea {
            anchors.fill: parent
            onClicked: root.focusHours()
        }

        Row {
            anchors.centerIn: parent

            Segment {
                id: _hours
                maximum: 23
                firstDigitLimit: 2
                padLeft: true
                placeholder: "HH"
                onNext: root.focusMinutes()
                onOutForward: root.focusMinutes()
                onOutBackward: root.tabOutBackward()
            }

            Text {
                width: Math.max(8, _colonWidth.advanceWidth + 2)
                height: _hours.height
                text: ":"
                font: _digits.font
                color: root._editing ? Theme.textSecondary : Theme.textMuted
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter

                TextMetrics {
                    id: _colonWidth
                    font: _digits.font
                    text: ":"
                }
            }

            Segment {
                id: _minutes
                maximum: 59
                firstDigitLimit: 5
                placeholder: "MM"
                onPrevious: root.focusHours()
                onOutForward: root.tabOutForward()
                onOutBackward: root.focusHours()
            }
        }
    }
}
