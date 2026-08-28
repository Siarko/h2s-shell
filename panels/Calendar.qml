import QtQuick
import qs.singletons
import qs.singletons.googlecalendar
import qs.panels.calendar

// Monthly calendar panel: events list (left) + date grid (right).
// implicitHeight grows when the add-event form is open (driven by EventsPanel).
Item {
    id: root
    implicitWidth: 551   // 270 events + 1 separator + 280 calendar
    implicitHeight: 340 + _eventsPanel.addFormExtraHeight

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

    Row {
        anchors.fill: parent
        spacing: 0

        EventsPanel {
            id: _eventsPanel
            width: 270
            height: parent.height
            displayYear:  root.displayYear
            displayMonth: root.displayMonth
            selectedDay:  root.selectedDay
        }

        Rectangle {
            width: 1
            height: 340
            color: Theme.textDim
            opacity: 0.3
        }

        MonthGrid {
            width: 280
            height: 340
            displayMonth: root.displayMonth
            displayYear:  root.displayYear
            selectedDay:  root.selectedDay
            today:        root._today
            monthNames:   root._monthNames
            dayNames:     root._dayNames
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
