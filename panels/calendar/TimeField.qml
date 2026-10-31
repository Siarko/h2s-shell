import QtQuick
import qs.singletons

// A time typed as two segments (FieldSegment), hours and minutes, each with its
// placeholder (HH, MM).
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

            FieldSegment {
                id: _hours
                font: _digits.font
                digitWidth: _digits.advanceWidth / 2
                height: Math.max(20, Math.ceil(_digits.height))
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

            FieldSegment {
                id: _minutes
                font: _digits.font
                digitWidth: _digits.advanceWidth / 2
                height: Math.max(20, Math.ceil(_digits.height))
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
