import QtQuick
import Quickshell
import QtQuick.Layouts
import qs.components
import qs.singletons
import qs.singletons.googlecalendar

// Right-side monthly date grid: navigation header, day labels, 6-row cell grid.
Item {
    id: root

    property int displayMonth
    property int displayYear
    property int selectedDay
    property var today: new Date()
    property var monthNames: ["January", "February", "March", "April", "May", "June",
                              "July", "August", "September", "October", "November", "December"]
    property var dayNames: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    // Scroll accumulators — private, live here so Calendar.qml stays clean
    property real _monthScrollAccum: 0
    property real _yearScrollAccum: 0

    // A change of month slides the old month out and the new one in, from the side it
    // comes from: later months from the right, earlier ones from the left. The old month
    // is a snapshot of the grid. There are three snapshots, taking turns: one is live,
    // parked outside the clipped area, so it always holds what the grid last showed;
    // when the month changes — before the grid redraws — it freezes and becomes the
    // month sliding out. So a change mid-slide slides too, from where the grid is, and
    // the month that was sliding out then keeps going beside it (the third snapshot)
    // rather than vanishing.
    // Set once, not bound: it has to keep the old month until the slide starts
    property int _shownMonthIndex: -1
    // 1: the new month comes from the right, -1: from the left; and the slide's before it
    property int _slideDirection: 1
    property int _previousDirection: 1
    // Which snapshot is live (0–2); the one after it is the month sliding out, the one
    // after that the month before it, shown only when a slide interrupted another going
    // the same way (going back, the grid itself covers where it was)
    property int _capturing: 0
    property bool _showOlder: false
    property bool _swapPending: false
    Component.onCompleted: _shownMonthIndex = displayYear * 12 + displayMonth
    onDisplayMonthChanged: _freezeOldMonth()
    onDisplayYearChanged: _freezeOldMonth()

    function _freezeOldMonth() {
        // Once per change: December to January changes the year too
        if (_swapPending)
            return;
        _swapPending = true;
        _capturing = (_capturing + 2) % 3;
        Qt.callLater(_slideToShownMonth);
    }

    function _slideToShownMonth() {
        _swapPending = false;
        const monthIndex = displayYear * 12 + displayMonth;
        if (monthIndex === _shownMonthIndex)
            return;
        _previousDirection = _slideDirection;
        _slideDirection = monthIndex > _shownMonthIndex ? 1 : -1;
        _shownMonthIndex = monthIndex;
        _showOlder = _monthSlide.running && _slideDirection === _previousDirection;
        // The month sliding out starts where the grid is now
        const from = (_monthSlide.running ? _gridShift.x : 0) + _slideDirection * _dateGrid.width;
        _monthSlide.stop();
        _monthSlide.fromX = from;
        _monthSlide.start();
    }

    component MonthSnapshot: ShaderEffectSource {
        required property int snapshotIndex
        // 0: live, 1: the month sliding out, 2: the one before it
        readonly property int role: (snapshotIndex - root._capturing + 3) % 3
        sourceItem: _dateGrid
        width: _dateGrid.width
        height: _dateGrid.height
        live: role === 0
        visible: role !== 2 || (root._showOlder && _monthSlide.running)
        x: role === 0 ? width + 1
            : role === 1 ? _gridShift.x - root._slideDirection * width
            : _gridShift.x - (root._slideDirection + root._previousDirection) * width
    }

    // Derived grid geometry
    readonly property int _startDow:      (new Date(displayYear, displayMonth, 1).getDay() + 6) % 7
    readonly property int _daysInMonth:   new Date(displayYear, displayMonth + 1, 0).getDate()
    readonly property int _prevMonthDays: new Date(displayYear, displayMonth, 0).getDate()

    property string viewMode: "day"

    // The grid's 42 days, the month's with the ends of the months around it
    function _cellKey(index) {
        return CalendarDates.keyOfDate(new Date(displayYear, displayMonth, index - _startDow + 1));
    }
    readonly property string _firstKey: _cellKey(0)
    readonly property string _lastKey: _cellKey(41)
    // The month's events, each once, and the bars of those spanning days
    // (CalendarDates.dayBars), by day key
    readonly property var _monthEvents: {
        const seen = {};
        const events = [];
        for (let day = 1; day <= _daysInMonth; day++) {
            for (const event of GoogleCalendar.events[CalendarDates.dateKey(displayYear, displayMonth, day)] ?? []) {
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
    // The open event form's days, "YYYY-MM-DD" (empty when none), shaded; and whether a
    // click picks a date for it rather than selecting the day
    property string rangeStart: ""
    property string rangeEnd: ""
    property bool picking: false

    signal prevMonthRequested()
    signal nextMonthRequested()
    signal dayClicked(int day)
    signal todayClicked()
    signal yearDeltaRequested(int delta)

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        // Header: < Month Year >
        Row {
            Layout.fillWidth: true
            height: 30

            ArrowButton {
                text: "<"
                onClicked: root.prevMonthRequested()
            }

            Item {
                width: parent.width - 60
                height: parent.height

                Row {
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        text: root.monthNames[root.displayMonth]
                        color: _monthArea.containsMouse ? Theme.accent : Theme.textPrimary
                        Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSection
                        font.bold: true

                        MouseArea {
                            id: _monthArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onWheel: event => {
                                root._monthScrollAccum += event.angleDelta.y
                                while (root._monthScrollAccum >= 120) {
                                    root.nextMonthRequested()
                                    root._monthScrollAccum -= 120
                                }
                                while (root._monthScrollAccum <= -120) {
                                    root.prevMonthRequested()
                                    root._monthScrollAccum += 120
                                }
                            }
                        }
                    }

                    Text {
                        text: root.displayYear
                        color: _yearArea.containsMouse ? Theme.accent : Theme.textPrimary
                        Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSection
                        font.bold: true

                        MouseArea {
                            id: _yearArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onWheel: event => {
                                root._yearScrollAccum += event.angleDelta.y
                                while (root._yearScrollAccum >= 120) {
                                    root.yearDeltaRequested(1)
                                    root._yearScrollAccum -= 120
                                }
                                while (root._yearScrollAccum <= -120) {
                                    root.yearDeltaRequested(-1)
                                    root._yearScrollAccum += 120
                                }
                            }
                        }
                    }
                }
            }

            ArrowButton {
                text: ">"
                onClicked: root.nextMonthRequested()
            }
        }

        // "Today" button — visible only when not viewing the current month/year
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(18, _todayText.implicitHeight)
            visible: root.displayMonth !== root.today.getMonth() || root.displayYear !== root.today.getFullYear()

            Text {
                id: _todayText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "↩ Today"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: _todayArea.containsMouse ? Theme.textPrimary : Theme.textSecondary
                Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

                MouseArea {
                    id: _todayArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.todayClicked()
                }
            }
        }

        // Day-of-week labels, as tall as a line of them, never less than 20 px
        Row {
            Layout.fillWidth: true
            height: Math.max(20, _dayNameMetrics.height)

            TextMetrics {
                id: _dayNameMetrics
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                text: "Mo"
            }

            Repeater {
                // ScriptModel, never the bare array — see "The Repeater crash" in
                // docs/ARCHITECTURE.md; dayNames is an input, set by the parent
                model: ScriptModel {
                    values: root.dayNames
                }
                Text {
                    required property string modelData
                    width: parent.width / 7
                    height: parent.height
                    text: modelData
                    color: Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        // 6-row date grid
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            // The months sliding past stay inside the grid
            clip: true

            // The three snapshots of the grid, see _freezeOldMonth. The one sliding out sits
            // a grid's width beside the grid, outside the clipped area when idle; the live
            // one is parked outside it, where it is still rendered (so it stays current)
            // but not seen.
            MonthSnapshot { snapshotIndex: 0 }
            MonthSnapshot { snapshotIndex: 1 }
            MonthSnapshot { snapshotIndex: 2 }

            // Week-range border — a single rectangle spanning the full row
            Rectangle {
                visible: root.viewMode === "week"
                x: 0
                y: {
                    let selectedIndex = root._startDow + root.selectedDay - 1;
                    return Math.floor(selectedIndex / 7) * (_dateGrid.height / 6);
                }
                width: _dateGrid.width
                height: _dateGrid.height / 6
                Behavior on y { NumberAnimation { duration: Theme.duration("move"); easing: Theme.curve("move") } }
                color: "transparent"
                border.color: Theme.accent
                border.width: Theme.border.width
                radius: Theme.calendar.dayRadius
                z: 1
            }

            Grid {
                id: _dateGrid
                anchors.fill: parent
                columns: 7
                rows: 6
                transform: Translate { id: _gridShift }

                NumberAnimation {
                    id: _monthSlide
                    property real fromX: 0
                    target: _gridShift
                    property: "x"
                    from: fromX
                    to: 0
                    duration: Theme.duration("slide")
                    easing: Theme.curve("slide")
                }

                Repeater {
                    model: 42

                    Rectangle {
                        id: _cell
                        required property int index

                        property bool isCurrent:  index >= root._startDow && index < root._startDow + root._daysInMonth
                        property int  dayNum:     isCurrent
                            ? index - root._startDow + 1
                            : (index < root._startDow
                                ? root._prevMonthDays - root._startDow + index + 1
                                : index - root._startDow - root._daysInMonth + 1)
                        property bool isToday:    isCurrent && dayNum === root.today.getDate() && root.displayMonth === root.today.getMonth() && root.displayYear === root.today.getFullYear()
                        property bool isSelected: isCurrent && dayNum === root.selectedDay
                        readonly property string _key: root._cellKey(index)
                        readonly property var _bars: root._dayBars[_key] ?? []
                        // Keys compare as dates: "YYYY-MM-DD" sorts in order
                        property bool inRange: isCurrent && root.rangeStart !== ""
                            && _key >= root.rangeStart && _key <= (root.rangeEnd || root.rangeStart)

                        width: _dateGrid.width / 7
                        height: _dateGrid.height / 6
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
        }
    }
}
