import QtQuick
import qs.singletons
import qs.singletons.googlecalendar
import qs.panels.calendar

// Monthly calendar panel: events list (left) + date grid (right).
// implicitHeight grows when the add-event form is open (driven by EventsPanel).
Item {
    id: root
    // 270 events + 1 separator + 280 calendar, by 340, at the built-in fonts: grown with
    // the text and the theme's calendar width (Theme.popupWidth), the height alike
    readonly property real _scale: Theme.popupWidth("calendar", 551) / 551
    readonly property int _gridHeight: Math.round(340 * _scale)
    implicitWidth: Math.round(270 * _scale) + 1 + Math.round(280 * _scale)
    implicitHeight: _gridHeight + _eventsPanel.addFormExtraHeight

    property int displayMonth: new Date().getMonth()
    property int displayYear:  new Date().getFullYear()
    property int selectedDay:  _today.getDate()

    readonly property var _today: new Date()
    readonly property var _monthNames: ["January", "February", "March", "April", "May", "June",
                                        "July", "August", "September", "October", "November", "December"]
    readonly property var _dayNames: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    // Needed to clamp selectedDay when navigating months
    readonly property int _daysInMonth: new Date(displayYear, displayMonth + 1, 0).getDate()

    function _prevMonth() {
        if (displayMonth === 0) { displayMonth = 11; displayYear-- }
        else displayMonth--
        selectedDay = Math.min(selectedDay, _daysInMonth)
    }

    function _nextMonth() {
        if (displayMonth === 11) { displayMonth = 0; displayYear++ }
        else displayMonth++
        selectedDay = Math.min(selectedDay, _daysInMonth)
    }

    // Qt.callLater deduplicates calls with the same function reference within one
    // event-loop tick. This prevents a double-fetch when both displayYear and
    // displayMonth change simultaneously during component initialisation.
    function _fetchCurrentMonth() {
        GoogleCalendar.fetchMonthEvents(displayYear, displayMonth);
    }

    onDisplayMonthChanged: Qt.callLater(_fetchCurrentMonth)
    onDisplayYearChanged:  Qt.callLater(_fetchCurrentMonth)

    // Logging in while the calendar is open changes neither the month nor the year, so
    // without this the events only appeared after a manual refresh
    Connections {
        target: GoogleCalendarAuth

        function onAuthorized(success) {
            if (success)
                GoogleCalendar.fetchMonthEvents(root.displayYear, root.displayMonth, true);
        }
    }

    // Switched back on by a profile (off battery, say) while the calendar is open
    Connections {
        target: GoogleCalendar

        function onAvailableChanged() {
            if (GoogleCalendar.available)
                GoogleCalendar.fetchMonthEvents(root.displayYear, root.displayMonth, true);
        }
    }

    Row {
        anchors.fill: parent
        spacing: 0

        EventsPanel {
            id: _eventsPanel
            width: Math.round(270 * root._scale)
            height: parent.height
            displayYear:  root.displayYear
            displayMonth: root.displayMonth
            selectedDay:  root.selectedDay
        }

        Rectangle {
            width: 1
            height: root._gridHeight
            color: Theme.textDisabled
            opacity: 0.3
        }

        MonthGrid {
            width: Math.round(280 * root._scale)
            height: root._gridHeight
            displayMonth: root.displayMonth
            displayYear:  root.displayYear
            selectedDay:  root.selectedDay
            today:        root._today
            monthNames:   root._monthNames
            dayNames:     root._dayNames
            viewMode:     Config.gcal.viewMode
            onPrevMonthRequested: root._prevMonth()
            onNextMonthRequested: root._nextMonth()
            onDayClicked:         day   => root.selectedDay   = day
            onTodayClicked:       {
                root.displayMonth = root._today.getMonth()
                root.displayYear  = root._today.getFullYear()
            }
            onYearDeltaRequested: delta => root.displayYear += delta
        }
    }
}
