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
    property string viewMode: Config.gcal.viewMode

    function _dedupById(events) {
        let seen = {};
        return events.filter(e => { if (seen[e.id]) return false; seen[e.id] = true; return true; });
    }

    readonly property var _displayedEvents: {
        if (viewMode === "week") {
            let dow = new Date(displayYear, displayMonth, selectedDay).getDay();
            let monOffset = (dow + 6) % 7;
            let weekStart = new Date(displayYear, displayMonth, selectedDay - monOffset);
            let result = [];
            for (let i = 0; i < 7; i++) {
                let d = new Date(weekStart);
                d.setDate(weekStart.getDate() + i);
                let key = GoogleCalendar._dateKey(d.getFullYear(), d.getMonth(), d.getDate());
                result.push(...(GoogleCalendar.events[key] ?? []));
            }
            return _dedupById(result);
        }
        if (viewMode === "mon") {
            let days = new Date(displayYear, displayMonth + 1, 0).getDate();
            let result = [];
            for (let d = 1; d <= days; d++)
                result.push(...(GoogleCalendar.events[GoogleCalendar._dateKey(displayYear, displayMonth, d)] ?? []));
            return _dedupById(result);
        }
        return GoogleCalendar.events[GoogleCalendar._dateKey(displayYear, displayMonth, selectedDay)] ?? [];
    }

    // One banner at a time: switched off, not signed in, or the last load failed — each
    // with its own action on click
    readonly property string _statusKind: !GoogleCalendar.enabled ? "off"
        : !GoogleCalendarAuth.isAuthorized ? "unauthorized"
        : GoogleCalendar.error !== "" ? "error" : ""
    readonly property string _statusMessage: ({
        "off": "Google Calendar is off",
        "unauthorized": "Google Calendar connected but not authorized",
        "error": GoogleCalendar.error + " — click to retry",
        "": ""
    })[_statusKind]

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

        // Date header row: date label (left) | Day/Week/Mon (centre) | +/↻ (right)
        RowLayout {
            Layout.fillWidth: true
            spacing: 0

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
                // The date gives way first when the column is narrow
                Layout.fillWidth: true
                Layout.maximumWidth: implicitWidth
                Layout.minimumWidth: 30
                elide: Text.ElideRight
            }

            Item { Layout.fillWidth: true; Layout.minimumWidth: 6 }

            Row {
                spacing: 1

                Repeater {
                    model: ["Day", "Week", "Mon"]

                    Row {
                        required property string modelData
                        required property int index

                        Text {
                            visible: index > 0
                            text: "/"
                            color: Theme.textDisabled
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            height: _modeLabel.implicitHeight
                            verticalAlignment: Text.AlignVCenter
                        }

                        Text {
                            id: _modeLabel
                            text: modelData
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: _modeArea.containsMouse || root.viewMode === modelData.toLowerCase()
                            color: (root.viewMode === modelData.toLowerCase()) ? Theme.textPrimary
                                 : _modeArea.containsMouse                     ? Theme.textSecondary
                                 : Theme.textSecondary

                            MouseArea {
                                id: _modeArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Config.gcal.viewMode = modelData.toLowerCase()
                            }
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true; Layout.minimumWidth: 6 }

            Row {
                spacing: 6
                visible: GoogleCalendar.available

                Text {
                    text: "+"
                    color: _addArea.containsMouse ? Theme.textPrimary : Theme.textSecondary
                    Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSection

                    MouseArea {
                        id: _addArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root._addingEvent = true
                    }
                }

                Text {
                    text: "󰑓"
                    color: _refreshArea.containsMouse ? Theme.textPrimary : Theme.textSecondary
                    Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMedium

                    MouseArea {
                        id: _refreshArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: GoogleCalendar.fetchMonthEvents(root.displayYear, root.displayMonth, true)
                    }
                }
            }
        }

        // Status / error banner
        Rectangle {
            visible: root._statusMessage !== ""
            Layout.fillWidth: true
            implicitHeight: _statusText.implicitHeight + 8
            radius: Theme.listItem.radius
            color: Theme.errorTint

            Text {
                id: _statusText
                anchors { fill: parent; leftMargin: 8; rightMargin: 36; topMargin: 4; bottomMargin: 4 }
                text: root._statusMessage
                color: Theme.error
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }

            Text {
                anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                text: "→"
                color: _bannerArea.containsMouse ? Theme.textPrimary : Theme.error
                Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMedium
            }

            MouseArea {
                id: _bannerArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root._statusKind === "error")
                        GoogleCalendar.fetchMonthEvents(root.displayYear, root.displayMonth, true);
                    else if (root._statusKind === "unauthorized"
                             && Config.gcal.clientId !== "" && Config.gcal.clientSecret !== "")
                        GoogleCalendarAuth.login();
                    else
                        Shell.openSettings("calendar");
                }
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
                    duration: Theme.duration("expand")
                    easing: Theme.curve("expand")
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
                submitKind: "save"
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
                values: root._displayedEvents
            }

            delegate: EventCard {
                // required property var modelData
                displayYear: root.displayYear
                displayMonth: root.displayMonth
                selectedDay: root.selectedDay
                showDate: root.viewMode !== "day"
            }

            Text {
                anchors.centerIn: parent
                text: "No events"
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                visible: _eventsList.count === 0 && !_loading
            }
        }
    }

    // Loading spinner overlay
    property bool _loading: GoogleCalendar.eventsLoading[GoogleCalendar._monthKey(displayYear, displayMonth)] ?? false

    // Spins around the centre of the glyph's ring. Rotating the Text spun it around the
    // middle of its box instead — Nerd Font icons are wider than the one-cell box and
    // stick out to the right — and even the middle of the ink is off, since the arrowhead
    // pokes out of the ring on the right. The ring's centre, fitted to the rendered glyph:
    // 0.401 em from the left of the ink, 0.359 em above the baseline. The box here is the
    // ink (TextMetrics, which matches the render), with the glyph placed so that point
    // lands on the box's centre, the rotation origin.
    Item {
        id: _spinner
        visible: root._loading
        anchors.centerIn: parent
        width: _spinnerMetrics.tightBoundingRect.width
        height: _spinnerMetrics.tightBoundingRect.height

        Text {
            id: _spinnerGlyph
            x: _spinner.width / 2 - (_spinnerMetrics.tightBoundingRect.x + 0.401 * font.pixelSize)
            y: _spinner.height / 2 - (baselineOffset - 0.359 * font.pixelSize)
            text: "󰑓"
            font.pixelSize: Theme.fontSizeDisplay
            font.family: Theme.fontFamily
            color: Theme.textSecondary
        }

        TextMetrics {
            id: _spinnerMetrics
            font: _spinnerGlyph.font
            text: _spinnerGlyph.text
        }

        RotationAnimator on rotation {
            running: root._loading
            from: 0
            to: 360
            duration: Theme.duration("spin")
            easing: Theme.curve("spin")
            loops: Animation.Infinite
        }
    }
}
