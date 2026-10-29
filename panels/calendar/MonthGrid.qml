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

    // Derived grid geometry
    readonly property int _startDow:      (new Date(displayYear, displayMonth, 1).getDay() + 6) % 7
    readonly property int _daysInMonth:   new Date(displayYear, displayMonth + 1, 0).getDate()
    readonly property int _prevMonthDays: new Date(displayYear, displayMonth, 0).getDate()

    property string viewMode: "day"

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
                        color: _monthArea.containsMouse ? Theme.sliderAccent : Theme.textPrimary
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
                        color: _yearArea.containsMouse ? Theme.sliderAccent : Theme.textPrimary
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
            Layout.preferredHeight: 18
            visible: root.displayMonth !== root.today.getMonth() || root.displayYear !== root.today.getFullYear()

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "↩ Today"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: _todayArea.containsMouse ? Theme.textPrimary : Theme.textSecondary

                MouseArea {
                    id: _todayArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.todayClicked()
                }
            }
        }

        // Day-of-week labels
        Row {
            Layout.fillWidth: true
            height: 20

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
                color: "transparent"
                border.color: Theme.sliderAccent
                border.width: 1
                radius: 4
                z: 1
            }

            Grid {
                id: _dateGrid
                anchors.fill: parent
                columns: 7
                rows: 6

                Repeater {
                    model: 42

                    Rectangle {
                        required property int index

                        property bool isCurrent:  index >= root._startDow && index < root._startDow + root._daysInMonth
                        property int  dayNum:     isCurrent
                            ? index - root._startDow + 1
                            : (index < root._startDow
                                ? root._prevMonthDays - root._startDow + index + 1
                                : index - root._startDow - root._daysInMonth + 1)
                        property bool isToday:    isCurrent && dayNum === root.today.getDate() && root.displayMonth === root.today.getMonth() && root.displayYear === root.today.getFullYear()
                        property bool isSelected: isCurrent && dayNum === root.selectedDay

                        width: _dateGrid.width / 7
                        height: _dateGrid.height / 6
                        color: isToday    ? Theme.todayHighlight
                             : isSelected ? Qt.rgba(Theme.sliderAccent.r, Theme.sliderAccent.g, Theme.sliderAccent.b, 0.2)
                             : "transparent"
                        radius: 4
                        // Border shows selected range: day→cell, week→handled by overlay, month→none
                        border.width: root.viewMode === "day" && isSelected && !isToday ? 1 : 0
                        border.color: Theme.sliderAccent

                        Text {
                            anchors.centerIn: parent
                            text: dayNum
                            color: isCurrent ? Theme.textPrimary : Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeMedium
                            font.bold: isToday
                        }

                        Rectangle {
                            visible: isCurrent && (GoogleCalendar.events[GoogleCalendar._dateKey(root.displayYear, root.displayMonth, dayNum)] ?? []).length > 0
                            width: 4
                            height: 4
                            radius: 2
                            color: Theme.sliderAccent
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 3
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
