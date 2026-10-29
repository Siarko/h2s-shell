import QtQuick
import QtQuick.Layouts
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
    property bool confirmingDelete: false

    readonly property real _cardHeight: {
        if (root.editing) return _editForm.implicitHeight + 16
        if (root.confirmingDelete)
            return root.modelData.recurringEventId ? _recurDeleteCol.implicitHeight + 16 : 50
        return (expanded && modelData.description) ? 50 + _desc.implicitHeight + 8 : 50
    }

    width: ListView.view.width
    height: _cardHeight
    radius: 6
    color: Theme.surface
    clip: true

    border {
        color: modelData.calendarColor
        width: modelData.calendarColor ? 2 : 0
    }

    Behavior on height {
        NumberAnimation { duration: Theme.duration("expand"); easing.type: Theme.easing("expand") }
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

    // Summary row — 50px, hidden while editing or confirming delete
    Item {
        width: parent.width
        height: 50
        visible: !root.confirmingDelete && !root.editing

        Column {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 14
            anchors.rightMargin: GoogleCalendar.available ? 50 : (_birthdayIcon.visible ? _birthdayIcon.implicitWidth + 12 : 8)
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
            anchors.rightMargin: GoogleCalendar.available ? 50 : 8
            text: "🎂"
            font.pixelSize: Theme.fontSizeSection
            visible: root.modelData.eventType === 'birthday'
            width: visible ? implicitWidth : 6
        }
    }

    // Description — below the 50px summary row
    Text {
        id: _desc
        anchors {
            top: parent.top; topMargin: 50
            left: parent.left; right: parent.right
            leftMargin: 14; rightMargin: 6
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
            topMargin: 8; leftMargin: 14; rightMargin: 6
        }
        submitLabel: "Save"
        submitColor: Theme.confirmSecondary
        submitColorHover: Theme.confirmSecondaryHover
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
        visible: !root.editing && !root.confirmingDelete && GoogleCalendar.available
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 6
        anchors.topMargin: 15
        spacing: 6

        Text {
            text: "✏"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBodyLarge
            color: _editBtnArea.containsMouse ? Theme.textSecondary : Theme.textMuted

            MouseArea {
                id: _editBtnArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.expanded = false
                    root.editing = true
                }
            }
        }

        Text {
            text: "✕"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBodyLarge
            color: _deleteBtnArea.containsMouse ? Theme.textSecondary : Theme.textMuted

            MouseArea {
                id: _deleteBtnArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.confirmingDelete = true
            }
        }
    }

    // Delete confirmation — non-recurring: "Delete event? Yes / No"
    RowLayout {
        visible: root.confirmingDelete && !root.modelData.recurringEventId
        anchors { left: parent.left; right: parent.right; top: parent.top }
        anchors.leftMargin: 14
        anchors.rightMargin: 8
        height: 50
        spacing: 6

        Text {
            text: "Delete event?"
            Layout.alignment: Qt.AlignVCenter
            color: Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Text {
            text: "Yes"
            Layout.alignment: Qt.AlignVCenter
            color: _yesArea.containsMouse ? Theme.textPrimary : Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true

            MouseArea {
                id: _yesArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    GoogleCalendar.deleteEvent({
                        year: root.displayYear, month: root.displayMonth, day: root.selectedDay,
                        eventId: root.modelData.id, calendarId: root.modelData.calendarId })
                    root.confirmingDelete = false
                }
            }
        }

        Text {
            text: "No"
            Layout.alignment: Qt.AlignVCenter
            color: _noArea.containsMouse ? Theme.textPrimary : Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall

            MouseArea {
                id: _noArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.confirmingDelete = false
            }
        }

        Item { Layout.fillWidth: true }
    }

    // Delete confirmation — recurring: vertical list of options
    Column {
        id: _recurDeleteCol
        visible: root.confirmingDelete && !!root.modelData.recurringEventId
        anchors { left: parent.left; right: parent.right; top: parent.top }
        anchors.leftMargin: 14
        anchors.topMargin: 8
        spacing: 4

        Text {
            text: "Delete:"
            color: Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Text {
            text: "- This event"
            color: _thisEventArea.containsMouse ? Theme.textPrimary : Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true

            MouseArea {
                id: _thisEventArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    GoogleCalendar.deleteEvent({
                        year: root.displayYear, month: root.displayMonth, day: root.selectedDay,
                        eventId: root.modelData.id, calendarId: root.modelData.calendarId })
                    root.confirmingDelete = false
                }
            }
        }

        Text {
            text: "- This and following"
            color: _thisAndFollowingArea.containsMouse ? Theme.textPrimary : Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true

            MouseArea {
                id: _thisAndFollowingArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    GoogleCalendar.deleteFromEvent({
                        year: root.displayYear, month: root.displayMonth, day: root.selectedDay,
                        recurringEventId: root.modelData.recurringEventId, calendarId: root.modelData.calendarId })
                    root.confirmingDelete = false
                }
            }
        }

        Text {
            text: "- All events"
            color: _allEventsArea.containsMouse ? Theme.textPrimary : Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true

            MouseArea {
                id: _allEventsArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    GoogleCalendar.deleteEvent({
                        year: root.displayYear, month: root.displayMonth, day: root.selectedDay,
                        eventId: root.modelData.recurringEventId, calendarId: root.modelData.calendarId })
                    root.confirmingDelete = false
                }
            }
        }

        Text {
            text: "- Cancel"
            color: _recurCancelArea.containsMouse ? Theme.textPrimary : Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall

            MouseArea {
                id: _recurCancelArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.confirmingDelete = false
            }
        }
    }
}
