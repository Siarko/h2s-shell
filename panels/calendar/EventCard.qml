import QtQuick
import QtQuick.Layouts
import qs.components
import qs.singletons
import qs.singletons.googlecalendar

// Single event card delegate. Width fills the parent ListView.
// Caller must bind displayYear/Month/selectedDay for CRUD calls.
Rectangle {
    id: root

    required property var modelData
    property int displayYear
    property int displayMonth
    property int selectedDay
    property bool showDate: false

    function _dow(date) {
        return ["sun","mon","tue","wed","thu","fri","sat"][date.getDay()];
    }

    property bool expanded: false
    property bool editing: false
    // An event of a series being deleted: the choice of what to delete replaces the summary
    // (RecurringDeleteChoice). A single event asks on its DeleteButton instead.
    property bool confirmingDelete: false
    readonly property bool _recurring: !!modelData.recurringEventId
    // A question never carries over to another event shown by this card
    onModelDataChanged: {
        confirmingDelete = false;
        _deleteButton.asking = false;
    }

    // The summary row: as tall as its two lines need, never less than 50 px
    readonly property real _summaryHeight: Math.max(50, _summaryLines.implicitHeight + 12)
    // Where the text starts: the row's padding, and room for the calendar's colour bar at
    // the left edge
    readonly property real _textInset: Theme.row.horizontalPadding + 6

    readonly property real _cardHeight: {
        if (root.editing) return _editForm.implicitHeight + 16
        if (root.confirmingDelete)
            return _recurringDelete.implicitHeight + 16
        return (expanded && modelData.description) ? _summaryHeight + _desc.implicitHeight + 8 : _summaryHeight
    }

    width: ListView.view.width
    height: _cardHeight
    radius: Theme.row.radius
    color: Theme.surface
    clip: true

    border {
        color: modelData.calendarColor
        width: modelData.calendarColor ? 2 : 0
    }

    Behavior on height {
        NumberAnimation { duration: Theme.duration("expand"); easing: Theme.curve("expand") }
    }

    // Accent bar
    Rectangle {
        width: 3
        radius: 2
        color: root.modelData.color
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
            anchors.rightMargin: GoogleCalendar.available ? _actions.width + 12 : (_birthdayIcon.visible ? _birthdayIcon.implicitWidth + 12 : 8)
            spacing: 2

            Text {
                width: parent.width
                text: root.modelData.title
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBodyLarge
                font.bold: true
                elide: Text.ElideRight
            }

            Row {
                spacing: 6

                Text {
                    text: root.modelData.time
                    color: Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }

                Text {
                    visible: root.showDate && (root.modelData.startTime !== null || root.modelData.allDayDuration > 0)
                    text: {
                        let s = root.modelData.allDayStartDate;
                        let e = root.modelData.allDayEndDate;
                        if (root.modelData.allDayDuration > 1)
                            return root._dow(s) + " " + s.getDate() + " - " + root._dow(e) + " " + e.getDate() + " (" + root.modelData.allDayDuration + " days)";
                        if (root.modelData.allDayDuration === 1)
                            return root._dow(s) + " " + s.getDate();
                        if (!root.modelData.startTime) return "";
                        let d = root.modelData.startTime;
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
            anchors.rightMargin: GoogleCalendar.available ? _actions.width + 12 : 8
            text: "🎂"
            font.pixelSize: Theme.fontSizeSection
            visible: root.modelData.eventType === 'birthday'
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
        text: root.modelData.description || ""
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
        cursorShape: root.modelData.description ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (root.modelData.description)
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
        onSubmitted: (title, description, startTime, endTime) => {
            GoogleCalendar.updateEvent({
                year: root.displayYear, month: root.displayMonth, day: root.selectedDay,
                eventId: root.modelData.id, calendarId: root.modelData.calendarId,
                title, description, startTime, endTime,
                colorId: _editForm.selectedColorId || null,
                rrule: _editForm.rrule || null })
            root.editing = false
        }
        onCancelled: root.editing = false
    }

    // Pre-fill edit form when editing begins
    onEditingChanged: {
        if (editing) {
            _editForm.populate(
                modelData.title !== "(No title)" ? modelData.title : "",
                modelData.startTimeStr,
                modelData.endTimeStr,
                modelData.description || "",
                modelData.startTimeStr === "",
                modelData.colorId ?? "",
                modelData.rrule ?? ""
            )
        }
    }

    // Edit / Delete action buttons — higher z, intercept clicks in their area
    Row {
        id: _actions
        visible: !root.editing && !root.confirmingDelete && GoogleCalendar.available
        anchors.right: parent.right
        anchors.verticalCenter: parent.top
        anchors.verticalCenterOffset: root._summaryHeight / 2
        anchors.rightMargin: 6
        spacing: 6

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "✏"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBodyLarge
            color: _editBtnArea.containsMouse ? Theme.textSecondary : Theme.textMuted
            Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

            MouseArea {
                id: _editBtnArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    _deleteButton.asking = false
                    root.expanded = false
                    root.editing = true
                }
            }
        }

        // A single event: asks on the button, deletes on the second click
        DeleteButton {
            id: _deleteButton
            anchors.verticalCenter: parent.verticalCenter
            visible: !root._recurring
            label: "✕"
            confirmLabel: "Delete?"
            cancelTip: "Keep the event"
            onConfirmed: GoogleCalendar.deleteEvent({
                year: root.displayYear, month: root.displayMonth, day: root.selectedDay,
                eventId: root.modelData.id, calendarId: root.modelData.calendarId })
        }

        // An event of a series: what to delete is chosen below
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root._recurring
            text: "✕"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBodyLarge
            color: _deleteSeriesArea.containsMouse ? Theme.textSecondary : Theme.textMuted
            Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

            MouseArea {
                id: _deleteSeriesArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.confirmingDelete = true
            }
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
                            calendarId: root.modelData.calendarId };
            if (which === "this")
                GoogleCalendar.deleteEvent(Object.assign(event, { eventId: root.modelData.id }));
            else if (which === "following")
                GoogleCalendar.deleteFromEvent(Object.assign(event, { recurringEventId: root.modelData.recurringEventId }));
            else
                GoogleCalendar.deleteEvent(Object.assign(event, { eventId: root.modelData.recurringEventId }));
            root.confirmingDelete = false;
        }
    }
}
