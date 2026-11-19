import QtQuick
import qs.components
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

    // The calendar backend: GoogleCalendar, or a test's stand-in
    property var calendar: GoogleCalendar

    property bool _addingEvent: false
    readonly property string _selectedKey: CalendarDates.dateKey(displayYear, displayMonth, selectedDay)

    // The open event form (adding, or the card being edited — the one opened last), for
    // the calendar: it fills the form's armed date and shades its span. Null when none.
    property var activeForm: null
    on_AddingEventChanged: {
        if (_addingEvent)
            activeForm = _addEventForm;
        else if (activeForm === _addEventForm)
            activeForm = null;
    }
    // The event being edited stays listed while other days are looked at, so the edit is
    // not lost when the calendar moves on
    property var _editingEvent: null
    property var _editingCard: null
    function _editStarted(card) {
        _editingCard = card;
        _editingEvent = card.calendarEvent;
        activeForm = card.form;
    }
    function _editEnded(card) {
        if (_editingCard !== card)
            return;
        _editingCard = null;
        _editingEvent = null;
        if (activeForm === card.form)
            activeForm = _addingEvent ? _addEventForm : null;
    }
    property string viewMode: Config.gcal.viewMode

    readonly property var _displayedEvents: {
        const events = _eventsOfView;
        const editingKey = _editingEvent ? GoogleCalendarData.eventKey(_editingEvent) : "";
        if (_editingEvent && !events.some(event => GoogleCalendarData.eventKey(event) === editingKey))
            return [_editingEvent].concat(events);
        return events;
    }

    KeyedModel {
        id: _eventsModel
        values: root._displayedEvents
        // The calendar with the id: one event id can be in two calendars (an invitation),
        // and keys made unique by their place would follow the order, not the event
        keyOf: event => GoogleCalendarData.eventKey(event)
    }

    readonly property var _eventsOfView: {
        if (viewMode === "week") {
            let dow = new Date(displayYear, displayMonth, selectedDay).getDay();
            let monOffset = (dow + 6) % 7;
            let weekStart = new Date(displayYear, displayMonth, selectedDay - monOffset);
            let result = [];
            for (let i = 0; i < 7; i++) {
                let d = new Date(weekStart);
                d.setDate(weekStart.getDate() + i);
                let key = CalendarDates.dateKey(d.getFullYear(), d.getMonth(), d.getDate());
                result.push(...(root.calendar.events[key] ?? []));
            }
            return GoogleCalendarData.uniqueEvents(result);
        }
        if (viewMode === "mon") {
            let days = new Date(displayYear, displayMonth + 1, 0).getDate();
            let result = [];
            for (let d = 1; d <= days; d++)
                result.push(...(root.calendar.events[CalendarDates.dateKey(displayYear, displayMonth, d)] ?? []));
            return GoogleCalendarData.uniqueEvents(result);
        }
        return GoogleCalendarData.uniqueEvents(root.calendar.events[CalendarDates.dateKey(displayYear, displayMonth, selectedDay)] ?? []);
    }

    // One banner at a time: switched off, not signed in, or the last load failed — each
    // with its own action on click
    readonly property string _statusKind: !root.calendar.enabled ? "off"
        : !GoogleCalendarAuth.isAuthorized ? "unauthorized"
        : root.calendar.error !== "" ? "error" : ""
    readonly property string _statusMessage: ({
        "off": "Google Calendar is off",
        "unauthorized": "Google Calendar connected but not authorized",
        "error": root.calendar.error + " — click to retry",
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
                            font.bold: _modeArea.lit || root.viewMode === modelData.toLowerCase()
                            color: (root.viewMode === modelData.toLowerCase()) ? Theme.textPrimary
                                 : _modeArea.lit                     ? Theme.textSecondary
                                 : Theme.textSecondary

                            PointerArea {
                                id: _modeArea
                                centred: false
                                anchors.fill: parent
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
                visible: root.calendar.available

                Text {
                    objectName: "calendarAdd"
                    text: "+"
                    color: _addArea.lit ? Theme.textPrimary : Theme.textSecondary
                    Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSection

                    PointerArea {
                        id: _addArea
                        // The glyph is small for a finger: the target reaches past it
                        reach: 8
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            _addEventForm.reset(root._selectedKey);
                            root._addingEvent = true;
                        }
                    }
                }

                Text {
                    text: "󰑓"
                    color: _refreshArea.lit ? Theme.textPrimary : Theme.textSecondary
                    Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMedium

                    PointerArea {
                        id: _refreshArea
                        reach: 8
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.calendar.fetchMonthEvents(root.displayYear, root.displayMonth, true)
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
                color: _bannerArea.lit ? Theme.textPrimary : Theme.error
                Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMedium
            }

            PointerArea {
                id: _bannerArea
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root._statusKind === "error")
                        root.calendar.fetchMonthEvents(root.displayYear, root.displayMonth, true);
                    else if (root._statusKind === "unauthorized")
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
                onSubmitted: event => {
                    root.calendar.createEvent(Object.assign(event, {
                        year: root.displayYear, month: root.displayMonth,
                        calendarId: _addEventForm.selectedCalendarId,
                        colorId: _addEventForm.selectedColorId || null,
                        rrule: _addEventForm.rrule || null }));
                    root._addingEvent = false;
                }
                onCancelled: root._addingEvent = false
            }
        }

        // Event cards
        ListView {
            id: _eventsList
            objectName: "calendarEvents"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            // Keyed by the event's calendar and id (GoogleCalendar builds new objects on every fetch): a
            // card keeps its event — an open edit with it — while events before it come
            // and go
            model: _eventsModel.model

            delegate: EventCard {
                required property string modelData
                calendarEvent: _eventsModel.byKey[modelData] ?? ({})
                calendar: root.calendar
                displayYear: root.displayYear
                displayMonth: root.displayMonth
                selectedDay: root.selectedDay
                showDate: root.viewMode !== "day"
                onEditingChanged: editing ? root._editStarted(this) : root._editEnded(this)
                Component.onDestruction: root._editEnded(this)
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
    property bool _loading: root.calendar.eventsLoading[CalendarDates.monthKey(displayYear, displayMonth)] ?? false

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
