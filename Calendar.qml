import QtQuick

// Monthly calendar with navigation arrows
Item {
    id: root

    property int displayMonth: new Date().getMonth()
    property int displayYear: new Date().getFullYear()

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

    Column {
        anchors.fill: parent
        spacing: 4

        // Header: < Month Year >
        Row {
            width: parent.width
            height: 30

            Text {
                width: 30
                height: parent.height
                text: "<"
                color: "#aaaaaa"
                font.pixelSize: 18
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root._prevMonth()
                }
            }

            Text {
                width: parent.width - 60
                height: parent.height
                text: root._monthNames[root.displayMonth] + " " + root.displayYear
                color: "white"
                font.pixelSize: 16
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            Text {
                width: 30
                height: parent.height
                text: ">"
                color: "#aaaaaa"
                font.pixelSize: 18
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root._nextMonth()
                }
            }
        }

        // Day-of-week labels
        Row {
            width: parent.width
            height: 20

            Repeater {
                model: root._dayNames
                Text {
                    required property string modelData
                    width: parent.width / 7
                    height: parent.height
                    text: modelData
                    color: "#aaaaaa"
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        // 6-row date grid
        Grid {
            id: dateGrid
            width: parent.width
            height: parent.height - 54
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
                    color: isToday ? "#666666" : "transparent"
                    radius: 4

                    Text {
                        anchors.centerIn: parent
                        text: dayNum
                        color: isCurrent ? "white" : "#777777"
                        font.pixelSize: 14
                        font.bold: isToday
                    }
                }
            }
        }
    }
}
