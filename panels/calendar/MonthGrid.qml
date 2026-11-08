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
    // A finger swipe across the grid changes the month: the grid follows the finger, and
    // the month it brings in follows beside it — a second grid, the preview, its events
    // fetched as soon as it shows. Let go far enough, the grid takes the preview's place
    // and the slide carries on from there. The preview covers the snapshots beside the
    // grid, which hold whichever month was left last, not the one coming.
    // 1: the next month, on the right; -1: the one before, on the left; 0: none
    property int _previewDirection: 0
    readonly property int _previewIndex: displayYear * 12 + displayMonth + (_previewDirection || 1)
    property real _swipeBase: 0

    function _showPreview(direction) {
        if (direction === _previewDirection)
            return;
        _previewDirection = direction;
        if (direction !== 0)
            GoogleCalendar.fetchMonthEvents(Math.floor(_previewIndex / 12), _previewIndex % 12);
    }

    // Let go far enough: the grid moves to where the preview is and becomes that month —
    // all before anything is drawn again — and slides on to rest from there
    function _landSwipe(direction) {
        _previewDirection = 0;
        _showOlder = false;
        _previousDirection = _slideDirection;
        _slideDirection = direction;
        _gridShift.x += direction * _dateGrid.width;
        if (direction > 0)
            nextMonthRequested();
        else
            prevMonthRequested();
        // The month changed at once (_freezeOldMonth froze the live snapshot on the old
        // one); the slide it queued would start from a grid's width further out
        _shownMonthIndex = displayYear * 12 + displayMonth;
        _monthSlide.fromX = _gridShift.x;
        _monthSlide.start();
    }
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
        // A month changed otherwise (the arrows, the wheel) ends a swipe's preview
        _previewDirection = 0;
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
        // The month sliding out gives way to a swipe's preview, which stands where it would
        visible: role === 0 || (role === 1 && root._previewDirection === 0) || (root._showOlder && _monthSlide.running)
        x: role === 0 ? width + 1
            : role === 1 ? _gridShift.x - root._slideDirection * width
            : _gridShift.x - (root._slideDirection + root._previousDirection) * width
    }

    property string viewMode: "day"

    // The open event form's days, "YYYY-MM-DD" (empty when none), shaded; and whether a
    // click picks a date for it rather than selecting the day
    property string rangeStart: ""
    property string rangeEnd: ""
    property bool picking: false

    signal prevMonthRequested()
    signal nextMonthRequested()
    signal dayClicked(int day)
    signal todayClicked()
    // A month of the shown year picked in the months view
    signal monthPicked(int month)

    // The months view: the shown year's twelve months in place of the days, brought by a
    // click or a tap on the month or the year. Its arrows and a swipe move by years and a
    // month goes there — moving by years without a wheel (the year's own wheel stays).
    property bool _choosingMonth: false
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
                onClicked: root._choosingMonth ? root.yearDeltaRequested(-1) : root.prevMonthRequested()
            }

            Item {
                width: parent.width - 60
                height: parent.height

                Row {
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        // The months view shows the year alone
                        visible: !root._choosingMonth
                        text: root.monthNames[root.displayMonth]
                        color: _monthArea.lit ? Theme.accent : Theme.textPrimary
                        Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSection
                        font.bold: true

                        PointerArea {
                            id: _monthArea
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root._choosingMonth = !root._choosingMonth
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
                        color: _yearArea.lit ? Theme.accent : Theme.textPrimary
                        Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSection
                        font.bold: true

                        PointerArea {
                            id: _yearArea
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root._choosingMonth = !root._choosingMonth
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
                onClicked: root._choosingMonth ? root.yearDeltaRequested(1) : root.nextMonthRequested()
            }
        }

        // "Today" button — shown only away from the current month, but its line is always
        // there: a grid that lost a line to it would change size, its days jumping, on every
        // swipe to and from the current month
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(18, _todayText.implicitHeight)
            readonly property bool _away: root.displayMonth !== root.today.getMonth() || root.displayYear !== root.today.getFullYear()
            opacity: _away ? 1 : 0
            enabled: _away
            Behavior on opacity { NumberAnimation { duration: Theme.duration("fade"); easing: Theme.curve("fade") } }

            Text {
                id: _todayText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "↩ Today"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: _todayArea.lit ? Theme.textPrimary : Theme.textSecondary
                Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

                PointerArea {
                    id: _todayArea
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root._choosingMonth = false;
                        root.todayClicked();
                    }
                }
            }
        }

        // Day-of-week labels, as tall as a line of them, never less than 20 px
        Row {
            id: _dayNamesRow
            Layout.fillWidth: true
            opacity: root._choosingMonth ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: Theme.duration("fade"); easing: Theme.curve("fade") } }
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
            // Under the months view while it shows: unseen, and nothing in it to tap
            opacity: root._choosingMonth ? 0 : 1
            enabled: !root._choosingMonth
            Behavior on opacity { NumberAnimation { duration: Theme.duration("fade"); easing: Theme.curve("fade") } }
            // The months sliding past stay inside the grid
            clip: true

            // The three snapshots of the grid, see _freezeOldMonth. The one sliding out sits
            // a grid's width beside the grid, outside the clipped area when idle; the live
            // one is parked outside it, where it is still rendered (so it stays current)
            // but not seen.
            MonthSnapshot { snapshotIndex: 0 }
            MonthSnapshot { snapshotIndex: 1 }
            MonthSnapshot { snapshotIndex: 2 }

            // Swiped by a finger: left for the next month, right for the one before. Above
            // the days, which still get a tap — the swipe takes the finger only once it
            // moves.
            Item {
                anchors.fill: parent
                z: 2

                SwipeGesture {
                    id: _swipe
                    yAxis.enabled: false
                    onActiveChanged: {
                        if (active) {
                            // Caught mid-slide: held where it is. The month before the one
                            // sliding out is left behind for good.
                            root._showOlder = false;
                            _monthSlide.stop();
                            root._swipeBase = _gridShift.x;
                            return;
                        }
                        if (meant(deltaX, velocity().x, _dateGrid.width / 5))
                            root._landSwipe(deltaX < 0 ? 1 : -1);
                        else {
                            // Back to rest, the preview with it (hidden once there)
                            _monthSlide.fromX = _gridShift.x;
                            _monthSlide.start();
                        }
                    }
                    onDeltaXChanged: {
                        if (!active)
                            return;
                        _gridShift.x = root._swipeBase + deltaX;
                        // The side the grid has moved away from shows the month there
                        if (_gridShift.x !== 0)
                            root._showPreview(_gridShift.x < 0 ? 1 : -1);
                    }
                }
            }

            // Week-range border — a single rectangle spanning the full row
            Rectangle {
                visible: root.viewMode === "week"
                x: 0
                y: {
                    let selectedIndex = _dateGrid.startDow + root.selectedDay - 1;
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

            NumberAnimation {
                id: _monthSlide
                property real fromX: 0
                target: _gridShift
                property: "x"
                from: fromX
                to: 0
                duration: Theme.duration("slide")
                easing: Theme.curve("slide")
                // A swipe let go too soon has come back: its preview is done
                onFinished: root._previewDirection = 0
            }

            MonthDays {
                id: _dateGrid
                anchors.fill: parent
                transform: Translate { id: _gridShift }
                year: root.displayYear
                month: root.displayMonth
                selectedDay: root.selectedDay
                today: root.today
                viewMode: root.viewMode
                rangeStart: root.rangeStart
                rangeEnd: root.rangeEnd
                picking: root.picking
                onDayClicked: day => root.dayClicked(day)
            }

            // The month a swipe is bringing in, beside the grid; nothing to click in it
            MonthDays {
                visible: root._previewDirection !== 0
                enabled: false
                z: 0.5
                width: _dateGrid.width
                height: _dateGrid.height
                x: _gridShift.x + root._previewDirection * width
                year: Math.floor(root._previewIndex / 12)
                month: root._previewIndex % 12
                today: root.today
                viewMode: root.viewMode
                rangeStart: root.rangeStart
                rangeEnd: root.rangeEnd
                picking: root.picking
            }
        }
    }

    // The months view, over where the day names and the days are
    Item {
        id: _monthsView
        y: _dayNamesRow.y
        width: root.width
        height: root.height - y
        opacity: root._choosingMonth ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.duration("fade"); easing: Theme.curve("fade") } }

        Grid {
            id: _monthCells
            anchors.fill: parent
            columns: 3
            rows: 4

            Repeater {
                model: 12

                Rectangle {
                    id: _monthCell
                    required property int index
                    // The month the days show, in the year shown; and this month of today
                    readonly property bool _shown: index === root.displayMonth
                    readonly property bool _current: index === root.today.getMonth() && root.displayYear === root.today.getFullYear()

                    width: _monthCells.width / 3
                    height: _monthCells.height / 4
                    radius: Theme.calendar.dayRadius
                    color: _current ? Theme.calendarToday
                         : _shown ? Theme.accentTint
                         : _cellArea.lit ? Qt.alpha(Theme.accentTint, 0.55)
                         : Qt.alpha(Theme.accentTint, 0)
                    Behavior on color { ColorAnimation { duration: Theme.duration("state"); easing: Theme.curve("state") } }
                    border.width: _shown && _current ? Theme.border.width : 0
                    border.color: Theme.accent

                    Text {
                        anchors.centerIn: parent
                        text: root.monthNames[_monthCell.index].slice(0, 3)
                        color: Theme.textPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeMedium
                        font.bold: _monthCell._current
                    }

                    // The cells touch: no larger target than the cell
                    PointerArea {
                        id: _cellArea
                        centred: false
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root._choosingMonth = false;
                            root.monthPicked(_monthCell.index);
                        }
                    }
                }
            }
        }

        // Swiped by a finger: left for the next year, right for the one before
        Item {
            anchors.fill: parent
            z: 2

            SwipeGesture {
                yAxis.enabled: false
                onActiveChanged: {
                    if (!active && meant(deltaX, velocity().x, _monthsView.width / 5))
                        root.yearDeltaRequested(deltaX < 0 ? 1 : -1);
                }
            }
        }
    }
}
