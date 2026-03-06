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

    property bool expanded: false
    property bool editing: false
    property bool confirmingDelete: false

    readonly property real _cardHeight: {
        if (root.editing) return _editForm.implicitHeight + 16
        if (root.confirmingDelete) return 50
        return (expanded && modelData.description) ? 50 + _desc.implicitHeight + 8 : 50
    }

    width: ListView.view.width
    height: _cardHeight
    radius: 6
    color: Theme.cellDefault
    clip: true

    border {
        color: modelData.calendarColor
        width: modelData.calendarColor ? 2 : 0
    }

    Behavior on height {
        NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
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
            anchors.rightMargin: GoogleCalendar.isAuthorized ? 50 : (_birthdayIcon.visible ? _birthdayIcon.implicitWidth + 12 : 8)
            spacing: 2

            Text {
                width: parent.width
                text: root.modelData.title
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.bold: true
                elide: Text.ElideRight
            }

            Text {
                text: root.modelData.time
                color: Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }
        }

        Text {
            id: _birthdayIcon
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: GoogleCalendar.isAuthorized ? 50 : 8
            text: "🎂"
            font.pixelSize: 16
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
        font.pixelSize: 11
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
            topMargin: 8; leftMargin: 6; rightMargin: 6
        }
        submitLabel: "Save"
        submitColor: "#1e3a5f"
        submitColorHover: "#2d4a6d"
        onSubmitted: (title, description, startTime, endTime) => {
            GoogleCalendar.updateEvent({
                year: root.displayYear, month: root.displayMonth, day: root.selectedDay,
                eventId: root.modelData.id, calendarId: root.modelData.calendarId,
                title, description, startTime, endTime })
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
                modelData.startTimeStr === ""
            )
        }
    }

    // Edit / Delete action buttons — higher z, intercept clicks in their area
    Row {
        visible: !root.editing && !root.confirmingDelete && GoogleCalendar.isAuthorized
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 6
        anchors.topMargin: 15
        spacing: 6

        Text {
            text: "✏"
            font.family: Theme.fontFamily
            font.pixelSize: 13
            color: _editBtnArea.containsMouse ? Theme.textSecondary : Theme.textTertiary

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
            font.pixelSize: 13
            color: _deleteBtnArea.containsMouse ? Theme.textSecondary : Theme.textTertiary

            MouseArea {
                id: _deleteBtnArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.confirmingDelete = true
            }
        }
    }

    // Delete confirmation row — higher z than main MouseArea
    RowLayout {
        visible: root.confirmingDelete
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
            font.pixelSize: 11
        }

        Text {
            text: "Yes"
            Layout.alignment: Qt.AlignVCenter
            color: _yesArea.containsMouse ? Theme.textPrimary : Theme.sliderAccent
            font.family: Theme.fontFamily
            font.pixelSize: 11
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
            font.pixelSize: 11

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
}
