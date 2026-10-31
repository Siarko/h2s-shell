import QtQuick
import qs.singletons

// One segment of a segmented field (TimeField, DateField): `digits` digits from `minimum`
// to `maximum`, with its placeholder.
// - Only digits that can still make a valid value are taken (two-digit segments); a first
//   digit above `firstDigitLimit` can only be a one-digit value: with `padLeft` it is
//   completed at once ("7" → 07) and the segment moves on, otherwise it is refused.
// - A full segment moves on (`next`). Leaving a partly typed one completes it: padded on
//   the left ("1" → 01) with `padLeft`, else on the right ("3" → 30); `complete` replaces
//   that rule (a year: "26" → 2026).
// - Up and Down step the value, wrapping; Right at the end and Left at the start move to
//   the neighbours (`next`, `previous`), as does Backspace in an empty segment; keys in
//   `advanceKeys` (a separator, say) move on.
// - Tab and Shift+Tab are the owner's (`outForward`, `outBackward`).
Item {
    id: _segment

    property alias input: _input
    property font font
    property real digitWidth: 8
    property int digits: 2
    property int minimum: 0
    property int maximum: 59
    property int firstDigitLimit: 5
    property bool padLeft: false
    property string placeholder
    // function(text) → the completed text, instead of padding; null for padding
    property var complete: null
    property var advanceKeys: []

    signal next
    signal previous
    signal outForward
    signal outBackward

    function completed(value) {
        if (complete)
            return complete(value);
        if (value.length === 0)
            return "0".repeat(digits);
        if (value.length < digits)
            return padLeft ? ("0".repeat(digits) + value).slice(-digits) : (value + "0".repeat(digits)).slice(0, digits);
        return value;
    }

    function focusAll() {
        _input.forceActiveFocus();
        _input.selectAll();
    }

    function step(delta) {
        const current = parseInt(completed(_input.text));
        const range = maximum - minimum + 1;
        const value = ((isNaN(current) ? minimum : current) - minimum + delta + range) % range + minimum;
        _input.text = ("0".repeat(digits) + value).slice(-digits);
        _input.selectAll();
    }

    width: Math.max(9 * digits, Math.ceil(digitWidth * digits) + 2)
    height: Math.max(20, Math.ceil(_input.contentHeight))

    TextInput {
        id: _input
        selectionColor: Theme.selection
        selectedTextColor: Theme.selectedText
        anchors.fill: parent
        maximumLength: _segment.digits
        color: Theme.textPrimary
        font: _segment.font
        horizontalAlignment: TextInput.AlignHCenter
        verticalAlignment: TextInput.AlignVCenter

        onActiveFocusChanged: {
            if (activeFocus)
                selectAll();
            else if (text.length > 0 && text.length < _segment.digits)
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
            if (_segment.advanceKeys.indexOf(event.key) !== -1) {
                if (length > 0)
                    _segment.next();
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
                if (_segment.digits !== 2)
                    return;
                const digit = event.key - Qt.Key_0;
                // The position being typed: where the selection starts, or the cursor
                const position = selectionStart !== selectionEnd ? selectionStart : cursorPosition;
                if (position === 0 && digit > _segment.firstDigitLimit) {
                    // Can only be one digit: padded on the left it completes at once
                    if (_segment.padLeft && digit >= _segment.minimum) {
                        text = "0" + digit;
                        _segment.next();
                    }
                    event.accepted = true;
                    return;
                }
                if (position === 1) {
                    const value = parseInt(text[0]) * 10 + digit;
                    if (value > _segment.maximum || value < _segment.minimum) {
                        event.accepted = true;
                        return;
                    }
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

        // A full segment: on to what comes next
        onTextEdited: if (length === _segment.digits) _segment.next()

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
