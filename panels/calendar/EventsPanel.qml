import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.singletons
import qs.singletons.googlecalendar

// Left-side events panel: date header, animated add form, event cards list.
Item {
    id: root

    property int displayYear
    property int displayMonth
    property int selectedDay

    property bool _addingEvent: false

    readonly property string _statusMessage: {
        if (Config.gcal.enabled && !GoogleCalendarAuth.isAuthorized)
            return "Google Calendar connected but not authorized";
        return "";
    }

    // Used by Calendar.qml to grow implicitHeight when the add form is open.
    // = form content height + 8px (form item margins) + 6px (extra ColumnLayout spacing gap)
    readonly property real addFormExtraHeight: _addingEvent ? _addEventForm.implicitHeight + 14 : 0

    readonly property var _monthNames: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

    ColumnLayout {
        anchors {
            fill: parent
            margins: 10
        }
        spacing: 6

        // Date header row: label + "+" add button + "↻" refresh button
        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Text {
                text: {
                    var d = new Date(root.displayYear, root.displayMonth, root.selectedDay);
                    var days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
                    return days[d.getDay()] + ", " + root.selectedDay + " " + root._monthNames[root.displayMonth].substring(0, 3);
                }
                color: Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                font.bold: true
                Layout.fillWidth: true
            }

            Text {
                text: "+"
                color: _addArea.containsMouse ? Theme.textPrimary : Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSection
                visible: GoogleCalendar.isAuthorized

                MouseArea {
                    id: _addArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root._addingEvent = true
                }
            }

            Text {
                text: "↻"
                color: _refreshArea.containsMouse ? Theme.textPrimary : Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMedium
                visible: GoogleCalendar.isAuthorized

                MouseArea {
                    id: _refreshArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: GoogleCalendar.fetchDayEvents(root.displayYear, root.displayMonth, root.selectedDay, true)
                }
            }
        }

        // Status / error banner
        Rectangle {
            visible: root._statusMessage !== ""
            Layout.fillWidth: true
            implicitHeight: _statusText.implicitHeight + 8
            radius: 4
            color: Qt.rgba(Theme.textError.r, Theme.textError.g, Theme.textError.b, 0.12)

            Text {
                id: _statusText
                anchors { fill: parent; leftMargin: 8; rightMargin: 8; topMargin: 4; bottomMargin: 4 }
                text: root._statusMessage
                color: Theme.textError
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }
        }

        // Add event form — animated slide-in
        Item {
            id: _addFormWrapper
            Layout.fillWidth: true
            // Height = EventForm content + 4px top margin + 4px bottom margin (anchors.margins: 4 below)
            Layout.preferredHeight: root._addingEvent ? _addEventForm.implicitHeight + 8 : 0
            clip: true
            visible: root._addingEvent || Layout.preferredHeight > 0

            Behavior on Layout.preferredHeight {
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutQuad
                }
            }

            EventForm {
                id: _addEventForm
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 4
                }
                submitLabel: "Add Event"
                submitColor: "#1e5c1e"
                submitColorHover: "#2d6a2d"
                showCalendarPicker: true
                onSubmitted: (title, description, startTime, endTime) => {
                    GoogleCalendar.createEvent({ year: root.displayYear, month: root.displayMonth, day: root.selectedDay,
                        title, description, startTime, endTime,
                        calendarId: _addEventForm.selectedCalendarId,
                        colorId: _addEventForm.selectedColorId || null,
                        rrule: _addEventForm.rrule || null });
                    root._addingEvent = false;
                    reset();
                }
                onCancelled: {
                    root._addingEvent = false;
                    reset();
                }
            }
        }

        // Event cards
        ListView {
            id: _eventsList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            // ScriptModel diffs old vs. new values so only changed delegates get
            // added/removed — see MusicPanel.qml for why binding a plain live-model
            // array straight to Repeater/ListView.model was crashing this app.
            // Keyed by "id" since GoogleCalendar rebuilds the events array as brand-new
            // JS objects on every fetch.
            model: ScriptModel {
                objectProp: "id"
                values: GoogleCalendar.events[GoogleCalendar._dateKey(root.displayYear, root.displayMonth, root.selectedDay)] || []
            }

            delegate: EventCard {
                // required property var modelData
                displayYear: root.displayYear
                displayMonth: root.displayMonth
                selectedDay: root.selectedDay
            }

            Text {
                anchors.centerIn: parent
                text: "No events"
                color: Theme.textTertiary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                visible: _eventsList.count === 0 && !_loading
            }
        }
    }

    // Loading spinner overlay
    property bool _loading: GoogleCalendar.eventsLoading[GoogleCalendar._dateKey(displayYear, displayMonth, selectedDay)] ?? false

    Text {
        visible: root._loading
        text: "↻"
        font.pixelSize: Theme.fontSizeDisplay
        color: Theme.textSecondary
        font.family: Theme.fontFamily
        anchors.centerIn: parent

        RotationAnimator on rotation {
            running: root._loading
            from: 0
            to: 360
            duration: 800
            loops: Animation.Infinite
        }
    }
}
