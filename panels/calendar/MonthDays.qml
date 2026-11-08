import QtQuick
import Quickshell
import qs.singletons
import qs.singletons.googlecalendar

// One month's days: six weeks of cells with the ends of the months around it, event
// dots and the bars of events spanning days. MonthGrid shows two: the month shown, and the
// month a finger swipe is bringing in, beside it.
Grid {
    id: root

    property int year
    property int month
    // 0 for none (the preview selects nothing)
    property int selectedDay: 0
    property var today: new Date()
    property string viewMode: "day"
    // The open event form's days, "YYYY-MM-DD" (empty when none), shaded; and whether a
    // click picks a date for it rather than selecting the day
    property string rangeStart: ""
    property string rangeEnd: ""
    property bool picking: false

    signal dayClicked(int day)

    columns: 7
    rows: 6

    readonly property int startDow:       (new Date(year, month, 1).getDay() + 6) % 7
    readonly property int _daysInMonth:   new Date(year, month + 1, 0).getDate()
    readonly property int _prevMonthDays: new Date(year, month, 0).getDate()

    // The grid's 42 days, the month's with the ends of the months around it
    function _cellKey(index) {
        return CalendarDates.keyOfDate(new Date(year, month, index - startDow + 1));
    }
    readonly property string _firstKey: _cellKey(0)
    readonly property string _lastKey: _cellKey(41)
    // The month's events, each once, and the bars of those spanning days
    // (CalendarDates.dayBars), by day key
    readonly property var _monthEvents: {
        const seen = {};
        const events = [];
        for (let day = 1; day <= _daysInMonth; day++) {
            for (const event of GoogleCalendar.events[CalendarDates.dateKey(year, month, day)] ?? []) {
                if (!seen[event.id]) {
                    seen[event.id] = true;
                    events.push(event);
                }
            }
        }
        return events;
    }
    readonly property var _dayBars: CalendarDates.dayBars(_monthEvents, _firstKey, _lastKey)
    // Lanes of bars drawn in a day; more are left out — the day's list shows them all
    readonly property int _maxLanes: 3

    Repeater {
        model: 42

        Rectangle {
            id: _cell
            required property int index

            property bool isCurrent:  index >= root.startDow && index < root.startDow + root._daysInMonth
            property int  dayNum:     isCurrent
                ? index - root.startDow + 1
                : (index < root.startDow
                    ? root._prevMonthDays - root.startDow + index + 1
                    : index - root.startDow - root._daysInMonth + 1)
            property bool isToday:    isCurrent && dayNum === root.today.getDate() && root.month === root.today.getMonth() && root.year === root.today.getFullYear()
            property bool isSelected: isCurrent && dayNum === root.selectedDay
            readonly property string _key: root._cellKey(index)
            readonly property var _bars: root._dayBars[_key] ?? []
            // Keys compare as dates: "YYYY-MM-DD" sorts in order
            property bool inRange: isCurrent && root.rangeStart !== ""
                && _key >= root.rangeStart && _key <= (root.rangeEnd || root.rangeStart)

            width: root.width / 7
            height: root.height / 6
            color: isToday    ? Theme.calendarToday
                 : isSelected ? Theme.accentTint
                 : inRange    ? Qt.alpha(Theme.accentTint, 0.55)
                 : Qt.alpha(Theme.accentTint, 0)
            Behavior on color { ColorAnimation { duration: Theme.duration("state"); easing: Theme.curve("state") } }
            radius: Theme.calendar.dayRadius
            // Border shows selected range: day→cell, week→handled by overlay, month→none
            // While picking a date, the first and last day of the span are outlined
            // instead, so where it begins and ends shows
            readonly property bool _spanEnd: root.picking && inRange
                && (_key === root.rangeStart || _key === (root.rangeEnd || root.rangeStart))
            border.width: _spanEnd || (!root.picking && root.viewMode === "day" && isSelected && !isToday) ? Theme.border.width : 0
            border.color: Theme.accent

            Text {
                anchors.centerIn: parent
                text: dayNum
                color: isCurrent ? Theme.textPrimary : Theme.textDisabled
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMedium
                font.bold: isToday
            }

            // Events of this day alone: a dot each, in the event's colour, under
            // the day's number — two rows of four at most; the day's list shows
            // them all
            readonly property var _dots: isCurrent
                ? (GoogleCalendar.events[_key] ?? []).filter(event => !event.lastDate || event.lastDate === event.startDate).slice(0, 8)
                : []

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 3
                spacing: 2

                Repeater {
                    // The first four, then the rest; each row centred
                    model: ScriptModel {
                        values: [_cell._dots.slice(0, 4), _cell._dots.slice(4)].filter(row => row.length > 0)
                    }

                    Row {
                        id: _dotRow
                        required property var modelData
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 2

                        Repeater {
                            // ScriptModel, never the bare array — see "The Repeater
                            // crash" in docs/ARCHITECTURE.md
                            model: ScriptModel {
                                values: _dotRow.modelData
                            }

                            Rectangle {
                                required property var modelData
                                width: 4
                                height: 4
                                radius: width / 2
                                color: modelData.color
                            }
                        }
                    }
                }
            }

            // Events spanning days: a bar above the day's number, in the event's
            // colour through all its days, its pieces meeting at the cells' edges
            // (across weeks too, the lane kept), rounded where the event starts
            // and ends; lanes stack downwards from the top
            Repeater {
                // ScriptModel, never the bare array — see "The Repeater crash"
                // in docs/ARCHITECTURE.md
                model: ScriptModel {
                    values: _cell._bars.filter(bar => bar.lane < root._maxLanes)
                }

                Rectangle {
                    required property var modelData
                    readonly property real _inset: 3
                    x: modelData.isStart ? _inset : 0
                    width: _cell.width - (modelData.isStart ? _inset : 0) - (modelData.isEnd ? _inset : 0)
                    height: 3
                    anchors.top: _cell.top
                    anchors.topMargin: 2 + modelData.lane * 4
                    color: modelData.color
                    opacity: _cell.isCurrent ? 1 : 0.4
                    topLeftRadius: modelData.isStart ? height / 2 : 0
                    bottomLeftRadius: modelData.isStart ? height / 2 : 0
                    topRightRadius: modelData.isEnd ? height / 2 : 0
                    bottomRightRadius: modelData.isEnd ? height / 2 : 0
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled: parent.isCurrent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.dayClicked(parent.dayNum)
            }
        }
    }
}
