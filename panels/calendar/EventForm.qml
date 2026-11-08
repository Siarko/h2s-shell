import QtQuick
import qs.components
import qs.singletons
import qs.singletons.googlecalendar

// Reusable event form: title, colour (EventColorRow), all day, start and end — each a date
// (DateField) and, unless all day, a time — description, calendar, recurrence
// (RecurrenceEditor), submit + cancel.
// implicitHeight = inner Column height (no padding — caller wraps with margins).
Item {
    id: root

    implicitHeight: _col.implicitHeight

    property string submitLabel: "Save"
    // The submit button's kind (SmallButton): "save" adding an event, "saveChange" editing one
    property string submitKind: "saveChange"

    property bool showCalendarPicker: false
    // A new event can go only to a calendar it may be written to
    readonly property var _writableCalendarIds: GoogleCalendar.enabledCalendarIds
        .filter(id => GoogleCalendar.calendars[id]?.writable ?? true)
    property string selectedCalendarId: ""

    property alias selectedColorId: _colorRow.selectedColorId
    property bool _allDay: false
    // The event's first and last day, "YYYY-MM-DD" (a timed event's end date is the day it
    // ends on). Moving the start moves the end with it; an end before the start becomes
    // the start (CalendarDates.spanWithStart, spanWithEnd).
    property string startDate: ""
    property string endDate: ""

    function setStartDate(key) {
        const span = CalendarDates.spanWithStart({ start: startDate || key, end: endDate || key }, key);
        startDate = span.start;
        endDate = span.end;
    }

    // Which date the calendar fills on the next day clicked: "start", "end" or "" (none).
    // Set by going into a date field; picking the start moves on to the end, picking the
    // end finishes. Going into another of the form's fields ends it; clicking outside the
    // form (the calendar, say) does not.
    property string pickTarget: ""

    // A day clicked in the calendar, as "YYYY-MM-DD"
    function pickDay(key) {
        if (pickTarget === "start") {
            setStartDate(key);
            pickTarget = "end";
        } else if (pickTarget === "end") {
            setEndDate(key);
            pickTarget = "";
        }
    }

    // The item with the keyboard focus: in one of the form's other fields, picking ends
    readonly property Item _focusItem: Window.activeFocusItem
    on_FocusItemChanged: {
        if (pickTarget === "" || !_focusItem)
            return;
        let inForm = false, inDate = false;
        for (let item = _focusItem; item; item = item.parent) {
            if (item === _startDateInput || item === _endDateInput)
                inDate = true;
            if (item === root)
                inForm = true;
        }
        if (inForm && !inDate)
            pickTarget = "";
    }

    function setEndDate(key) {
        const span = CalendarDates.spanWithEnd({ start: startDate || key, end: endDate || key }, key);
        startDate = span.start;
        endDate = span.end;
    }

    readonly property string rrule: _recurrence.rrule

    // event: { title, description, startDate, endDate, startTime, endTime } — the times
    // empty for all day (GoogleCalendarData.eventBody)
    signal submitted(var event)
    signal cancelled

    Component.onCompleted: {
        if (showCalendarPicker && selectedCalendarId === "") {
            let enabled = root._writableCalendarIds;
            if (enabled && enabled.length > 0)
                selectedCalendarId = enabled[0];
        }
    }

    // event: { title, description, startDate, endDate, startTime, endTime, allDay, colorId,
    // rrule }
    function populate(event) {
        pickTarget = "";
        _titleInput.text = event.title ?? "";
        startDate = event.startDate;
        endDate = event.endDate || event.startDate;
        _startInput.setValue(event.startTime ?? "");
        _endInput.setValue(event.endTime ?? "");
        _descInput.text = event.description ?? "";
        _allDay = event.allDay ?? false;
        selectedColorId = event.colorId ?? "";
        _recurrence.setRule(event.rrule ?? "");
    }

    // An empty form for an event on `dateKey`
    function reset(dateKey) {
        pickTarget = "";
        startDate = dateKey ?? "";
        endDate = dateKey ?? "";
        _titleInput.text = "";
        _startInput.clear();
        _endInput.clear();
        _descInput.text = "";
        _allDay = false;
        selectedColorId = "";
        _recurrence.reset();
    }

    function _submit() {
        pickTarget = "";
        const startTime = _allDay ? "" : _startInput.text;
        const endTime = _allDay ? "" : (_endInput.text || startTime);
        let end = endDate || startDate;
        // A timed event ending earlier in the day than it starts, on its start day, goes on
        // past midnight: 22:00 → 02:00 ends the next day
        if (!_allDay && end === startDate && startTime !== "" && endTime < startTime)
            end = CalendarDates.addDays(startDate, 1);
        submitted({
            title: _titleInput.text,
            description: _descInput.text,
            startDate: startDate,
            endDate: end,
            startTime: startTime,
            endTime: endTime
        });
    }

    // "From" and "To", as wide as the wider
    component SpanLabel: Text {
        width: _spanLabelWidth.advanceWidth + 6
        height: 28
        color: Theme.textMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        verticalAlignment: Text.AlignVCenter
    }

    TextMetrics {
        id: _spanLabelWidth
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        text: "From"
    }

    Column {
        id: _col
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        spacing: 6

        // Title
        InputField {
            id: _titleInput
            objectName: "eventTitle"
            fieldColor: Theme.popupBackground
            outlined: true
            placeholder: "Title"
            width: parent.width
        }

        EventColorRow {
            id: _colorRow
            width: parent.width
        }

        Checkbox {
            id: _allDayCheckbox
            label: "All day"
            checked: root._allDay
            onToggled: root._allDay = !root._allDay
            // Into the times, or past them when they are hidden; Shift+Tab goes back to
            // the title as usual
            Keys.onTabPressed: {
                _startDateInput.focusDay();
            }
        }

        // Start and end: a date each, and a time unless all day. Tab runs start date →
        // start time → end date → end time.
        Row {
            width: parent.width
            height: 28
            spacing: 4

            SpanLabel { text: "From" }

            DateField {
                id: _startDateInput
                width: implicitWidth
                height: 28
                date: root.startDate
                armed: root.pickTarget === "start"
                onEntered: root.pickTarget = "start"
                onEdited: date => root.setStartDate(date)
                onTabOutForward: root._allDay ? _endDateInput.focusDay() : _startInput.focusHours()
                onTabOutBackward: _allDayCheckbox.forceActiveFocus()
            }

            TimeField {
                id: _startInput
                visible: !root._allDay
                width: parent.width - x
                height: 28
                onTabOutForward: _endDateInput.focusDay()
                onTabOutBackward: _startDateInput.focusYear()
            }
        }

        Row {
            width: parent.width
            height: 28
            spacing: 4

            SpanLabel { text: "To" }

            DateField {
                id: _endDateInput
                width: implicitWidth
                height: 28
                date: root.endDate
                armed: root.pickTarget === "end"
                onEntered: root.pickTarget = "end"
                onEdited: date => root.setEndDate(date)
                onTabOutForward: root._allDay ? _descInput.forceActiveFocus() : _endInput.focusHours()
                onTabOutBackward: root._allDay ? _startDateInput.focusYear() : _startInput.focusMinutes()
            }

            TimeField {
                id: _endInput
                visible: !root._allDay
                width: parent.width - x
                height: 28
                onTabOutForward: _descInput.forceActiveFocus()
                onTabOutBackward: _endDateInput.focusYear()
            }
        }

        // What the calendar does while a date is armed
        Text {
            visible: root.pickTarget !== ""
            width: parent.width
            text: root.pickTarget === "start" ? "Pick the first day in the calendar" : "Pick the last day in the calendar"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            wrapMode: Text.WordWrap
        }

        // Description
        Rectangle {
            width: parent.width
            height: Math.max(60, _descInput.implicitHeight + 8)
            color: Theme.popupBackground
            border.color: _descInput.activeFocus ? Theme.textSecondary : Theme.textDisabled
            radius: Theme.field.radius

            TextEdit {
                id: _descInput
                selectionColor: Theme.selection
                selectedTextColor: Theme.selectedText
                anchors {
                    fill: parent
                    margins: 4
                }
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                wrapMode: TextEdit.WordWrap

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier)) {
                        if (root._allDay)
                            _endDateInput.focusYear();
                        else
                            _endInput.focusMinutes();
                        event.accepted = true;
                    }
                }
            }
            Text {
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    leftMargin: 4
                    topMargin: 4
                }
                text: "Description"
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                visible: !_descInput.text.length
                enabled: false
            }
        }

        // Which calendar a new event goes to — only when showCalendarPicker
        Dropdown {
            width: parent.width
            visible: root.showCalendarPicker
            placeholder: "Select calendar"
            options: root._writableCalendarIds.map(id => ({
                value: id,
                label: GoogleCalendar.calendars[id]?.name ?? id,
                color: GoogleCalendar.calendars[id]?.color ?? Theme.textDisabled
            }))
            value: root.selectedCalendarId
            onPicked: value => root.selectedCalendarId = value
        }

        RecurrenceEditor {
            id: _recurrence
            width: parent.width
        }

        // Submit / Cancel buttons
        Row {
            width: parent.width
            spacing: 6

            SmallButton {
                width: (parent.width - 6) / 2
                label: root.submitLabel
                kind: root.submitKind
                onClicked: root._submit()
            }

            SmallButton {
                width: (parent.width - 6) / 2
                label: "Cancel"
                kind: "cancel"
                onClicked: {
                    root.pickTarget = "";
                    root.cancelled();
                }
            }
        }
    }
}
