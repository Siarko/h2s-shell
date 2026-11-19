import QtQuick
import QtQuick.Layouts
import qs.components
import qs.singletons
import qs.singletons.googlecalendar

// Single event card delegate. Width fills the parent ListView.
// Caller must bind displayYear/Month/selectedDay for CRUD calls, and give the card its event
// (looked up by key: EventsPanel's KeyedModel, so a card keeps its event for its whole life).
Rectangle {
    id: root

    // The event shown (GoogleCalendarData.event); empty while none
    property var calendarEvent: ({})
    // The calendar backend: GoogleCalendar, or a test's stand-in
    property var calendar: GoogleCalendar
    property int displayYear
    property int displayMonth
    property int selectedDay
    property bool showDate: false

    function _dow(date) {
        return ["sun","mon","tue","wed","thu","fri","sat"][date.getDay()];
    }

    // A card's button: a glyph on a button's background, square, as tall as a button
    // (and as DeleteButton beside it), so it is clear what is clicked
    component ActionButton: Rectangle {
        id: _actionButton
        property string glyph
        signal clicked
        width: height
        height: Math.max(Theme.button.minHeight, _glyphText.implicitHeight + 2 * Theme.button.verticalPadding)
        radius: Theme.button.radius
        color: _actionArea.lit ? Theme.surfaceHover : Theme.surface
        Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

        Text {
            id: _glyphText
            anchors.centerIn: parent
            text: _actionButton.glyph
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeMedium
            color: _actionArea.lit ? Theme.textPrimary : Theme.textSecondary
        }

        PointerArea {
            id: _actionArea
            cursorShape: Qt.PointingHandCursor
            onClicked: _actionButton.clicked()
        }
    }

    property bool expanded: false
    property bool editing: false
    // The edit form, for the calendar to fill its dates
    readonly property alias form: _editForm
    // An event of a series being deleted: the choice of what to delete replaces the summary
    // (RecurringDeleteChoice). A single event asks on its DeleteButton instead.
    property bool confirmingDelete: false
    readonly property bool _recurring: !!root.calendarEvent.recurringEventId
    // A question, an open description or an edit never carries over to another event: the
    // card's event keeps its id for the card's life (a keyed list), and should that ever
    // change, all is reset
    readonly property string _eventId: root.calendarEvent?.id ?? ""
    on_EventIdChanged: {
        confirmingDelete = false;
        _deleteButton.asking = false;
        expanded = false;
        editing = false;
    }
    // The event an edit saves to, taken when the edit starts: the save never goes to
    // another one, whatever the card shows by then (GoogleCalendarData.editSaveTarget)
    property var _editStartedOn: null

    // The summary row: as tall as its two lines need, never less than 50 px
    readonly property real _summaryHeight: Math.max(50, _summaryLines.implicitHeight + 12)
    // Where the text starts: the row's padding, and room for the calendar's colour bar at
    // the left edge
    readonly property real _textInset: Theme.row.horizontalPadding + 6

    readonly property real _cardHeight: {
        if (root.editing) return _editForm.implicitHeight + 16
        if (root.confirmingDelete)
            return _recurringDelete.implicitHeight + 16
        return (expanded && root.calendarEvent.description) ? _summaryHeight + _desc.implicitHeight + 8 : _summaryHeight
    }

    width: ListView.view.width
    height: _cardHeight
    radius: Theme.row.radius
    color: Theme.surface
    clip: true

    border {
        color: root.calendarEvent.calendarColor || Theme.surface
        width: root.calendarEvent.calendarColor ? 2 : 0
    }

    Behavior on height {
        NumberAnimation { duration: Theme.duration("expand"); easing: Theme.curve("expand") }
    }

    // Accent bar
    Rectangle {
        width: 3
        radius: 2
        color: root.calendarEvent.color
        anchors {
            left: parent.left; top: parent.top; bottom: parent.bottom
            leftMargin: 5; topMargin: 5; bottomMargin: 5
        }
    }

    // Summary row, hidden while editing or confirming delete
    Item {
        width: parent.width
        height: root._summaryHeight
        visible: !root.confirmingDelete && !root.editing

        Column {
            id: _summaryLines
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: root._textInset
            // Clear of the actions at the right, which widen while a delete asks
            anchors.rightMargin: root.calendar.available ? _actions.width + 12 : (_birthdayIcon.visible ? _birthdayIcon.implicitWidth + 12 : 8)
            spacing: 2

            Text {
                id: _titleText
                width: parent.width
                text: root.calendarEvent.title ?? ""
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBodyLarge
                font.bold: true
                elide: Text.ElideRight
            }

            Row {
                spacing: 6

                Text {
                    text: root.calendarEvent.time ?? ""
                    color: Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }

                Text {
                    visible: root.showDate && (root.calendarEvent.startTime !== null || root.calendarEvent.allDayDuration > 0)
                    text: {
                        let s = root.calendarEvent.allDayStartDate;
                        let e = root.calendarEvent.allDayEndDate;
                        if (root.calendarEvent.allDayDuration > 1)
                            return root._dow(s) + " " + s.getDate() + " - " + root._dow(e) + " " + e.getDate() + " (" + root.calendarEvent.allDayDuration + " days)";
                        if (root.calendarEvent.allDayDuration === 1)
                            return root._dow(s) + " " + s.getDate();
                        if (!root.calendarEvent.startTime) return "";
                        let d = root.calendarEvent.startTime;
                        return ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"][d.getDay()] + " " + d.getDate();
                    }
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }

        Text {
            id: _birthdayIcon
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: root.calendar.available ? _actions.width + 12 : 8
            text: "🎂"
            font.pixelSize: Theme.fontSizeSection
            visible: root.calendarEvent.eventType === 'birthday'
            width: visible ? implicitWidth : 6
        }
    }

    // Description — below the summary row
    Text {
        id: _desc
        anchors {
            top: parent.top; topMargin: root._summaryHeight
            left: parent.left; right: parent.right
            leftMargin: root._textInset; rightMargin: 6
        }
        text: root.calendarEvent.description || ""
        visible: root.expanded && !root.editing
        color: Theme.textSecondary
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        wrapMode: Text.WordWrap
    }

    // Main MouseArea — expand/collapse description on click.
    // Declared before the edit form so the form's higher z-order lets its buttons receive clicks first.
    MouseArea {
        anchors.fill: parent
        enabled: !root.editing && !root.confirmingDelete
        cursorShape: root.calendarEvent.description ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (root.calendarEvent.description)
                root.expanded = !root.expanded
        }
    }

    // Inline edit form — declared after main MouseArea so it has higher z-order.
    EventForm {
        id: _editForm
        visible: root.editing
        anchors {
            left: parent.left; right: parent.right; top: parent.top
            topMargin: 8; leftMargin: root._textInset; rightMargin: 6
        }
        submitLabel: "Save"
        submitKind: "saveChange"
        // The event's own dates, never the day selected in the calendar: a multi-day event
        // edited from its second day keeps its first
        onSubmitted: event => {
            const target = GoogleCalendarData.editSaveTarget(root._editStartedOn, root.calendar.events);
            if (target.refusal !== "") {
                _editForm.message = target.refusal;
                return;
            }
            root.calendar.updateEvent(Object.assign(event, {
                year: root.displayYear, month: root.displayMonth,
                eventId: target.eventId, calendarId: target.calendarId,
                colorId: _editForm.selectedColorId || null,
                rrule: _editForm.rrule || null }))
            root.editing = false
        }
        onCancelled: root.editing = false
    }

    // Pre-fill edit form when editing begins
    onEditingChanged: {
        root._editStartedOn = editing ? { id: root.calendarEvent?.id, calendarId: root.calendarEvent?.calendarId } : null;
        if (editing) {
            _editForm.populate({
                title: root.calendarEvent.title !== "(No title)" ? root.calendarEvent.title : "",
                description: root.calendarEvent.description || "",
                startDate: root.calendarEvent.startDate,
                endDate: root.calendarEvent.endDate,
                startTime: root.calendarEvent.startTimeStr,
                endTime: root.calendarEvent.endTimeStr,
                allDay: root.calendarEvent.startTimeStr === "",
                colorId: root.calendarEvent.colorId ?? "",
                rrule: root.calendarEvent.rrule ?? ""
            })
        }
    }

    // Edit / Delete action buttons — higher z, intercept clicks in their area
    Row {
        id: _actions
        // Not for events of a read-only calendar (holidays, say): Google would refuse
        visible: !root.editing && !root.confirmingDelete && root.calendar.available
            && (root.calendar.calendars[root.calendarEvent.calendarId]?.writable ?? true)
        anchors.right: parent.right
        anchors.rightMargin: 6
        // Level with the title, so they read as the event's own buttons
        y: _summaryLines.y + _titleText.y + _titleText.height / 2 - height / 2
        spacing: 4

        ActionButton {
            glyph: "󰏫"  // nf-md-pencil: "✏" drew tiny and blurred in the theme font
            onClicked: {
                _deleteButton.asking = false
                root.expanded = false
                root.editing = true
            }
        }

        // A single event: asks on the button, deletes on the second click
        DeleteButton {
            id: _deleteButton
            anchors.verticalCenter: parent.verticalCenter
            visible: !root._recurring
            label: "✕"
            fontSize: Theme.fontSizeMedium
            confirmLabel: "Delete?"
            cancelTip: "Keep the event"
            onConfirmed: root.calendar.deleteEvent({
                year: root.displayYear, month: root.displayMonth, day: root.selectedDay,
                eventId: root.calendarEvent.id, calendarId: root.calendarEvent.calendarId })
        }

        // An event of a series: what to delete is chosen below
        ActionButton {
            visible: root._recurring
            glyph: "✕"
            onClicked: root.confirmingDelete = true
        }
    }

    RecurringDeleteChoice {
        id: _recurringDelete
        visible: root.confirmingDelete
        anchors { left: parent.left; right: parent.right; top: parent.top }
        anchors.leftMargin: root._textInset
        anchors.topMargin: 8
        onCancelled: root.confirmingDelete = false
        onChosen: which => {
            const event = { year: root.displayYear, month: root.displayMonth, day: root.selectedDay,
                            calendarId: root.calendarEvent.calendarId };
            if (which === "this")
                root.calendar.deleteEvent(Object.assign(event, { eventId: root.calendarEvent.id }));
            else if (which === "following")
                root.calendar.deleteFromEvent(Object.assign(event, { recurringEventId: root.calendarEvent.recurringEventId }));
            else
                root.calendar.deleteEvent(Object.assign(event, { eventId: root.calendarEvent.recurringEventId }));
            root.confirmingDelete = false;
        }
    }
}
