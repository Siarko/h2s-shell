import QtQuick
import QtQuick.Layouts
import qs.components
import qs.singletons
import qs.singletons.googlecalendar

// Monthly calendar with navigation arrows and day events panel
Item {
    id: root
    implicitWidth: 481   // 200 events + 1 separator + 280 calendar
    implicitHeight: 340

    property int displayMonth: new Date().getMonth()
    property int displayYear: new Date().getFullYear()
    property int selectedDay: _today.getDate()

    property real _monthScrollAccum: 0
    property real _yearScrollAccum: 0

    readonly property var _today: new Date()
    readonly property var _monthNames: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    readonly property var _dayNames: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    // Derived properties that QML can track for bindings
    // Day-of-week offset for the 1st (Monday=0 .. Sunday=6)
    readonly property int _startDow: (new Date(displayYear, displayMonth, 1).getDay() + 6) % 7
    readonly property int _daysInMonth: new Date(displayYear, displayMonth + 1, 0).getDate()
    readonly property int _prevMonthDays: new Date(displayYear, displayMonth, 0).getDate()

    // Live data from GoogleCalendar singleton
    readonly property var _dayEvents: GoogleCalendar.events[_dateKey(displayYear, displayMonth, selectedDay)] || []
    // readonly property var _dayEvents: GoogleCalendar._cache[_dateKey(displayYear, displayMonth, selectedDay)] || []
    // readonly property bool _dayLoading: !!GoogleCalendar._loading[_dateKey(displayYear, displayMonth, selectedDay)]

    function _dateKey(y, m, d) {
        return y + "-" + ("0" + (m + 1)).slice(-2) + "-" + ("0" + d).slice(-2);
    }

    function _prevMonth() {
        if (displayMonth === 0) {
            displayMonth = 11;
            displayYear--;
        } else {
            displayMonth--;
        }
        selectedDay = Math.min(selectedDay, _daysInMonth);
    }

    function _nextMonth() {
        if (displayMonth === 11) {
            displayMonth = 0;
            displayYear++;
        } else {
            displayMonth++;
        }
        selectedDay = Math.min(selectedDay, _daysInMonth);
    }

    // Fetch events whenever the viewed date changes
    onSelectedDayChanged: {
        console.log("Selected day change");
        // GoogleCalendar.fetchEventsForDate(displayYear, displayMonth, selectedDay);
        GoogleCalendar.fetchDayEvents(displayYear, displayMonth, selectedDay);
    }
    onDisplayMonthChanged: {
        console.log("Selected month change");
        // GoogleCalendar.fetchEventsForDate(displayYear, displayMonth, selectedDay);
        GoogleCalendar.fetchDayEvents(displayYear, displayMonth, selectedDay);
    }
    onDisplayYearChanged: {
        console.log("Selected Year change");
        // GoogleCalendar.fetchEventsForDate(displayYear, displayMonth, selectedDay);
        GoogleCalendar.fetchDayEvents(displayYear, displayMonth, selectedDay);
    }

    Component.onCompleted: {
        // GoogleCalendar.fetchEventsForDate(displayYear, displayMonth, selectedDay);
    }

    Row {
        anchors.fill: parent
        spacing: 0

        // Events panel (left, 200px)
        Item {
            width: 200
            height: parent.height

            ColumnLayout {
                anchors {
                    fill: parent
                    margins: 10
                }
                spacing: 6

                // Selected date label + refresh button
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
                        font.pixelSize: 12
                        font.bold: true
                        Layout.fillWidth: true
                    }

                    Text {
                        text: "↻"
                        color: _refreshArea.containsMouse ? Theme.textPrimary : Theme.textSecondary
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        // visible: GoogleCalendar.isAuthorized
                        visible: GoogleCalendar.isAuthorized

                        MouseArea {
                            id: _refreshArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            // onClicked: GoogleCalendar.invalidateAndRefetch(root.displayyear, root.displaymonth, root.selectedday)
                            onClicked: GoogleCalendar.fetchDayEvents(root.displayYear, root.displayMonth, root.selectedDay, true)
                        }
                    }
                }

                // Event cards
                ListView {
                    id: eventsList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 6
                    model: root._dayEvents

                    delegate: Rectangle {
                        id: _card
                        required property var modelData
                        property bool expanded: false

                        width: ListView.view.width
                        height: (expanded && !!modelData.description) ? 50 + _desc.implicitHeight + 8 : 50
                        radius: 6
                        color: Theme.cellDefault
                        clip: true

                        border {
                            color: modelData.calendarColor
                            width: modelData.calendarColor ? 2 : 0
                        }

                        Behavior on height {
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutQuad
                            }
                        }

                        // Accent bar (stretches full card height)
                        Rectangle {
                            width: 3
                            radius: 2
                            color: _card.modelData.color
                            anchors {
                                left: parent.left
                                top: parent.top
                                bottom: parent.bottom
                                leftMargin: 5
                                topMargin: 5
                                bottomMargin: 5
                            }
                        }

                        // Summary row — always 50px, content vertically centred inside
                        Item {
                            width: parent.width
                            height: 50

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.right: _birthdayIcon.left
                                anchors.leftMargin: 14
                                anchors.rightMargin: 4
                                spacing: 2

                                Text {
                                    width: parent.width
                                    text: _card.modelData.title
                                    color: Theme.textPrimary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    text: _card.modelData.time
                                    color: Theme.textSecondary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                }
                            }

                            Text {
                                id: _birthdayIcon
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.rightMargin: 8
                                text: "🎂"
                                font.pixelSize: 16
                                visible: _card.modelData.eventType === 'birthday'
                                width: visible ? implicitWidth : 6
                            }
                        }

                        // Description (anchored just below the 50px summary row)
                        Text {
                            id: _desc
                            anchors {
                                top: parent.top
                                topMargin: 50
                                left: parent.left
                                right: parent.right
                                leftMargin: 14
                                rightMargin: 6
                            }
                            text: _card.modelData.description || ""
                            visible: _card.expanded
                            color: Theme.textSecondary
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: _card.modelData.description ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (_card.modelData.description)
                                    _card.expanded = !_card.expanded;
                            }
                        }
                    }

                    // Empty state (hidden while loading)
                    Text {
                        anchors.centerIn: parent
                        text: "No events"
                        color: Theme.textTertiary
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        visible: eventsList.count === 0 && !root._dayLoading
                    }
                }
            }

            // Loading spinner overlay (centered over events area)
            Text {
                // visible: root._dayLoading
                visible: false
                text: "↻"
                font.pixelSize: 22
                color: Theme.textSecondary
                font.family: Theme.fontFamily
                anchors.centerIn: parent

                RotationAnimator on rotation {
                    // running: root._dayLoading
                    running: false
                    from: 0
                    to: 360
                    duration: 800
                    loops: Animation.Infinite
                }
            }
        }

        // Separator
        Rectangle {
            width: 1
            height: parent.height
            color: Theme.textDim
            opacity: 0.3
        }

        // Calendar panel (right, 280px)
        Item {
            width: 280
            height: parent.height

            ColumnLayout {
                anchors.fill: parent
                spacing: 4

                // Header: < Month Year >
                Row {
                    Layout.fillWidth: true
                    height: 30

                    ArrowButton {
                        text: "<"
                        onClicked: root._prevMonth()
                    }

                    Item {
                        width: parent.width - 60
                        height: parent.height

                        Row {
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                id: monthText
                                text: root._monthNames[root.displayMonth]
                                color: monthArea.containsMouse ? Theme.sliderAccent : Theme.textPrimary
                                font.family: Theme.fontFamily
                                font.pixelSize: 16
                                font.bold: true

                                MouseArea {
                                    id: monthArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onWheel: event => {
                                        root._monthScrollAccum += event.angleDelta.y;
                                        while (root._monthScrollAccum >= 120) {
                                            root._nextMonth();
                                            root._monthScrollAccum -= 120;
                                        }
                                        while (root._monthScrollAccum <= -120) {
                                            root._prevMonth();
                                            root._monthScrollAccum += 120;
                                        }
                                    }
                                }
                            }

                            Text {
                                id: yearText
                                text: root.displayYear
                                color: yearArea.containsMouse ? Theme.sliderAccent : Theme.textPrimary
                                font.family: Theme.fontFamily
                                font.pixelSize: 16
                                font.bold: true

                                MouseArea {
                                    id: yearArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onWheel: event => {
                                        root._yearScrollAccum += event.angleDelta.y;
                                        while (root._yearScrollAccum >= 120) {
                                            root.displayYear++;
                                            root._yearScrollAccum -= 120;
                                        }
                                        while (root._yearScrollAccum <= -120) {
                                            root.displayYear--;
                                            root._yearScrollAccum += 120;
                                        }
                                    }
                                }
                            }
                        }
                    }

                    ArrowButton {
                        text: ">"
                        onClicked: root._nextMonth()
                    }
                }

                // "Today" button — visible only when not viewing the current month/year
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 18
                    visible: root.displayMonth !== root._today.getMonth() || root.displayYear !== root._today.getFullYear()

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "↩ Today"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: todayArea.containsMouse ? Theme.textPrimary : Theme.textSecondary

                        MouseArea {
                            id: todayArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.displayMonth = root._today.getMonth();
                                root.displayYear = root._today.getFullYear();
                            }
                        }
                    }
                }

                // Day-of-week labels
                Row {
                    Layout.fillWidth: true
                    height: 20

                    Repeater {
                        model: root._dayNames
                        Text {
                            required property string modelData
                            width: parent.width / 7
                            height: parent.height
                            text: modelData
                            color: Theme.textSecondary
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                // 6-row date grid
                Grid {
                    id: dateGrid
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    columns: 7
                    rows: 6

                    Repeater {
                        model: 42

                        Rectangle {
                            required property int index

                            // Compute day number and whether it belongs to the current month
                            property bool isCurrent: index >= root._startDow && index < root._startDow + root._daysInMonth
                            property int dayNum: isCurrent ? index - root._startDow + 1 : (index < root._startDow ? root._prevMonthDays - root._startDow + index + 1 : index - root._startDow - root._daysInMonth + 1)
                            property bool isToday: isCurrent && dayNum === root._today.getDate() && root.displayMonth === root._today.getMonth() && root.displayYear === root._today.getFullYear()
                            property bool isSelected: isCurrent && dayNum === root.selectedDay

                            width: dateGrid.width / 7
                            height: dateGrid.height / 6
                            color: isToday ? Theme.todayHighlight : "transparent"
                            radius: 4
                            border.width: isSelected && !isToday ? 1 : 0
                            border.color: Theme.sliderAccent

                            Text {
                                anchors.centerIn: parent
                                text: dayNum
                                color: isCurrent ? Theme.textPrimary : Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
                                font.bold: isToday
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: parent.isCurrent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectedDay = parent.dayNum
                            }
                        }
                    }
                }
            }
        }
    }
}
