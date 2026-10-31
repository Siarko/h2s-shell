import QtQuick
import qs.components
import qs.singletons
import qs.singletons.googlecalendar

// Reusable event form: title, colour (EventColorRow), all day, start/end time,
// description, calendar, recurrence (RecurrenceEditor), submit + cancel.
// implicitHeight = inner Column height (no padding — caller wraps with margins).
Item {
    id: root

    implicitHeight: _col.implicitHeight

    property string submitLabel: "Save"
    // The submit button's kind (SmallButton): "save" adding an event, "saveChange" editing one
    property string submitKind: "saveChange"

    property bool showCalendarPicker: false
    property string selectedCalendarId: ""

    property alias selectedColorId: _colorRow.selectedColorId
    property bool _allDay: false

    readonly property string rrule: _recurrence.rrule

    signal submitted(string title, string description, string startTime, string endTime)
    signal cancelled

    Component.onCompleted: {
        if (showCalendarPicker && selectedCalendarId === "") {
            let enabled = GoogleCalendar.enabledCalendarIds;
            if (enabled && enabled.length > 0)
                selectedCalendarId = enabled[0];
        }
    }

    function populate(title, startTime, endTime, description, allDay, colorId, rrule) {
        _titleInput.text = title;
        _startInput.setValue(startTime);
        _endInput.setValue(endTime);
        _descInput.text = description;
        _allDay = allDay ?? false;
        selectedColorId = colorId ?? "";
        _recurrence.setRule(rrule ?? "");
    }

    function reset() {
        _titleInput.text = "";
        _startInput.clear();
        _endInput.clear();
        _descInput.text = "";
        _allDay = false;
        selectedColorId = "";
        _recurrence.reset();
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
                if (root._allDay)
                    _descInput.forceActiveFocus();
                else
                    _startInput.focusHours();
            }
        }

        // Start → End time row — hidden when all day
        Item {
            width: parent.width
            height: root._allDay ? 0 : 28
            clip: true

            Row {
                width: parent.width
                height: 28
                spacing: 4

                TimeField {
                    id: _startInput
                    width: (parent.width - 20) / 2
                    height: 28
                    onTabOutForward: _endInput.focusHours()
                    onTabOutBackward: _allDayCheckbox.forceActiveFocus()
                }

                Text {
                    text: "→"
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    width: 12
                    height: 28
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                }

                TimeField {
                    id: _endInput
                    width: (parent.width - 20) / 2
                    height: 28
                    onTabOutForward: _descInput.forceActiveFocus()
                    onTabOutBackward: _startInput.focusMinutes()
                }
            }
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
                            _allDayCheckbox.forceActiveFocus();
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
            options: GoogleCalendar.enabledCalendarIds.map(id => ({
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
                onClicked: root.submitted(_titleInput.text, _descInput.text, root._allDay ? "" : _startInput.text, root._allDay ? "" : _endInput.text)
            }

            SmallButton {
                width: (parent.width - 6) / 2
                label: "Cancel"
                kind: "cancel"
                onClicked: root.cancelled()
            }
        }
    }
}
