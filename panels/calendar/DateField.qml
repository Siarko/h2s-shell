import QtQuick
import qs.singletons
import qs.singletons.googlecalendar

// A date typed as three segments (FieldSegment): day, month, year — DD.MM.YYYY.
// - Clicking anywhere in the field focuses the day, selected.
// - Each segment takes only digits that can still make a valid value; a full segment, or
//   ".", moves on to the next. A two-digit year is this century's ("26" → 2026).
// - Leaving the field checks the date: a day past the month's end becomes its last day
//   (31.02 → 28.02 or 29.02); what cannot be read (an empty segment, a three-digit year)
//   goes back to the date it had. Only a changed date is reported, through `edited` —
//   `date` itself is the owner's to set.
// - Up and Down step the segment, wrapping; Tab: day → month → year → `tabOutForward`;
//   Shift+Tab back to `tabOutBackward`.
Item {
    id: root

    // "YYYY-MM-DD"
    property string date: ""
    signal edited(string date)
    signal tabOutForward()
    signal tabOutBackward()
    // Focus came into the field — the event form arms the calendar for it
    signal entered()

    readonly property bool editing: _day.input.activeFocus || _month.input.activeFocus || _year.input.activeFocus
    // The calendar fills this field on the next day clicked (the event form's pick target)
    property bool armed: false

    function focusDay() {
        _day.focusAll();
    }

    function focusYear() {
        _year.focusAll();
    }

    function _show() {
        const parts = date.split("-");
        _day.input.text = parts[2] ?? "";
        _month.input.text = parts[1] ?? "";
        _year.input.text = parts[0] ?? "";
    }

    function _commit() {
        const year = parseInt(_year.completed(_year.input.text));
        const month = parseInt(_month.input.text) - 1;
        const day = parseInt(_day.input.text);
        if (isNaN(year) || isNaN(month) || isNaN(day) || year < 1970 || month < 0 || month > 11 || day < 1) {
            _show();
            return;
        }
        const typed = CalendarDates.dateKey(year, month, Math.min(day, CalendarDates.daysInMonth(year, month)));
        if (typed === date) {
            _show();
            return;
        }
        edited(typed);
        // The owner may not take the date as typed (an end before the start moves the
        // start instead), so the segments show what it holds
        _show();
    }

    onDateChanged: if (!editing) _show()
    Component.onCompleted: _show()
    // Checked a moment later: moving between segments takes the focus from one before
    // giving it to the next, and in between the field looks left
    onEditingChanged: Qt.callLater(_focusSettled)
    property bool _wasEditing: false
    function _focusSettled() {
        if (editing === _wasEditing)
            return;
        _wasEditing = editing;
        if (editing)
            entered();
        else
            _commit();
    }

    implicitWidth: _row.width + 16
    implicitHeight: Math.max(26, _digits.height + 8)

    TextMetrics {
        id: _digits
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBody
        text: "88"
    }

    component Dot: Text {
        width: Math.max(4, _dotWidth.advanceWidth + 1)
        height: _day.height
        text: "."
        font: _digits.font
        color: root.editing ? Theme.textSecondary : Theme.textMuted
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    TextMetrics {
        id: _dotWidth
        font: _digits.font
        text: "."
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.field.radius
        color: Theme.popupBackground
        border.color: root.editing || root.armed ? Theme.accent : Theme.outline
        border.width: root.armed && !root.editing ? Theme.border.selectedWidth : Theme.border.width
        Behavior on border.color { ColorAnimation { duration: Theme.duration("state"); easing: Theme.curve("state") } }

        // A click outside the segments focuses the day
        MouseArea {
            anchors.fill: parent
            onClicked: root.focusDay()
        }

        Row {
            id: _row
            anchors.centerIn: parent

            FieldSegment {
                id: _day
                font: _digits.font
                digitWidth: _digits.advanceWidth / 2
                height: Math.max(20, Math.ceil(_digits.height))
                minimum: 1
                maximum: 31
                firstDigitLimit: 3
                padLeft: true
                placeholder: "DD"
                advanceKeys: [Qt.Key_Period, Qt.Key_Comma, Qt.Key_Slash, Qt.Key_Minus]
                onNext: _month.focusAll()
                onOutForward: _month.focusAll()
                onOutBackward: root.tabOutBackward()
            }

            Dot {}

            FieldSegment {
                id: _month
                font: _digits.font
                digitWidth: _digits.advanceWidth / 2
                height: Math.max(20, Math.ceil(_digits.height))
                minimum: 1
                maximum: 12
                firstDigitLimit: 1
                padLeft: true
                placeholder: "MM"
                advanceKeys: [Qt.Key_Period, Qt.Key_Comma, Qt.Key_Slash, Qt.Key_Minus]
                onNext: _year.focusAll()
                onPrevious: _day.focusAll()
                onOutForward: _year.focusAll()
                onOutBackward: _day.focusAll()
            }

            Dot {}

            FieldSegment {
                id: _year
                font: _digits.font
                digitWidth: _digits.advanceWidth / 2
                height: Math.max(20, Math.ceil(_digits.height))
                digits: 4
                minimum: 1970
                maximum: 2099
                placeholder: "YYYY"
                // Two digits are this century's year; anything else short cannot be read
                complete: value => value.length === 2 ? "20" + value : value
                onPrevious: _month.focusAll()
                onOutForward: root.tabOutForward()
                onOutBackward: _month.focusAll()
            }
        }
    }
}
