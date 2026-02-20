import QtQuick
import QtQuick.Layouts
import qs.components
import qs.singletons

// Monthly calendar with navigation arrows
Item {
    id: root
    implicitWidth: 280
    implicitHeight: 340

    property int displayMonth: new Date().getMonth()
    property int displayYear: new Date().getFullYear()

    property real _monthScrollAccum: 0
    property real _yearScrollAccum: 0

    readonly property var _today: new Date()
    readonly property var _monthNames: [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]
    readonly property var _dayNames: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    // Derived properties that QML can track for bindings
    // Day-of-week offset for the 1st (Monday=0 .. Sunday=6)
    readonly property int _startDow: (new Date(displayYear, displayMonth, 1).getDay() + 6) % 7
    readonly property int _daysInMonth: new Date(displayYear, displayMonth + 1, 0).getDate()
    readonly property int _prevMonthDays: new Date(displayYear, displayMonth, 0).getDate()

    function _prevMonth() {
        if (displayMonth === 0) {
            displayMonth = 11;
            displayYear--;
        } else {
            displayMonth--;
        }
    }

    function _nextMonth() {
        if (displayMonth === 11) {
            displayMonth = 0;
            displayYear++;
        } else {
            displayMonth++;
        }
    }

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
            visible: root.displayMonth !== root._today.getMonth()
                  || root.displayYear  !== root._today.getFullYear()

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
                        root.displayYear  = root._today.getFullYear();
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
                    property bool isCurrent: index >= root._startDow
                        && index < root._startDow + root._daysInMonth
                    property int dayNum: isCurrent
                        ? index - root._startDow + 1
                        : (index < root._startDow
                            ? root._prevMonthDays - root._startDow + index + 1
                            : index - root._startDow - root._daysInMonth + 1)
                    property bool isToday: isCurrent
                        && dayNum === root._today.getDate()
                        && root.displayMonth === root._today.getMonth()
                        && root.displayYear === root._today.getFullYear()

                    width: dateGrid.width / 7
                    height: dateGrid.height / 6
                    color: isToday ? Theme.todayHighlight : "transparent"
                    radius: 4

                    Text {
                        anchors.centerIn: parent
                        text: dayNum
                        color: isCurrent ? Theme.textPrimary : Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.bold: isToday
                    }
                }
            }
        }
    }
}
