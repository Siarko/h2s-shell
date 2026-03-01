import QtQuick
import qs.singletons

// Reusable event form: title, start/end time, description, submit + cancel.
// implicitHeight = inner Column height (no padding — caller wraps with margins).
Item {
    id: root

    implicitHeight: _col.implicitHeight

    property string submitLabel: "Save"
    property color submitColor: "#1e3a5f"
    property color submitColorHover: "#2d4a6d"

    property bool _allDay: false

    signal submitted(string title, string description, string startTime, string endTime)
    signal cancelled()

    function populate(title, startTime, endTime, description, allDay) {
        _titleInput.text = title
        _startInput.text = startTime
        _endInput.text   = endTime
        _descInput.text  = description
        _allDay = allDay ?? false
    }

    function reset() {
        _titleInput.text = ""
        _startInput.text = ""
        _endInput.text   = ""
        _descInput.text  = ""
        _allDay = false
    }

    Column {
        id: _col
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 6

        // Title
        Rectangle {
            width: parent.width
            height: 28
            color: Theme.popupBackground
            border.color: Theme.textDim
            radius: 4

            TextInput {
                id: _titleInput
                anchors { fill: parent; leftMargin: 6; rightMargin: 6; topMargin: 4; bottomMargin: 4 }
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: 12
                verticalAlignment: TextInput.AlignVCenter
            }
            Text {
                anchors { fill: parent; leftMargin: 6; topMargin: 4; bottomMargin: 4 }
                text: "Title"
                color: Theme.textTertiary
                font.family: Theme.fontFamily
                font.pixelSize: 12
                verticalAlignment: Text.AlignVCenter
                visible: !_titleInput.text.length
                enabled: false
            }
        }

        // All day toggle
        Row {
            width: parent.width
            height: 22
            spacing: 6

            Rectangle {
                width: 14
                height: 14
                radius: 3
                anchors.verticalCenter: parent.verticalCenter
                color: root._allDay ? Theme.sliderAccent : "transparent"
                border.color: root._allDay ? Theme.sliderAccent : Theme.textDim
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "✓"
                    color: Theme.textPrimary
                    font.pixelSize: 9
                    visible: root._allDay
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root._allDay = !root._allDay
                }
            }

            Text {
                text: "All day"
                color: Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: 12
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root._allDay = !root._allDay
                }
            }
        }

        // Start → End time row — hidden when all day
        Item {
            width: parent.width
            height: root._allDay ? 0 : 28
            clip: true

            Row {
                width: parent.width
                height: 28
                spacing: 4

                Rectangle {
                    width: (parent.width - 20) / 2
                    height: 28
                    color: Theme.popupBackground
                    border.color: Theme.textDim
                    radius: 4

                    TextInput {
                        id: _startInput
                        anchors { fill: parent; leftMargin: 6; rightMargin: 6; topMargin: 4; bottomMargin: 4 }
                        color: Theme.textPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        verticalAlignment: TextInput.AlignVCenter
                    }
                    Text {
                        anchors { fill: parent; leftMargin: 6; topMargin: 4; bottomMargin: 4 }
                        text: "HH:MM"
                        color: Theme.textTertiary
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        verticalAlignment: Text.AlignVCenter
                        visible: !_startInput.text.length
                        enabled: false
                    }
                }

                Text {
                    text: "→"
                    color: Theme.textTertiary
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    width: 12
                    height: 28
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                }

                Rectangle {
                    width: (parent.width - 20) / 2
                    height: 28
                    color: Theme.popupBackground
                    border.color: Theme.textDim
                    radius: 4

                    TextInput {
                        id: _endInput
                        anchors { fill: parent; leftMargin: 6; rightMargin: 6; topMargin: 4; bottomMargin: 4 }
                        color: Theme.textPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        verticalAlignment: TextInput.AlignVCenter
                    }
                    Text {
                        anchors { fill: parent; leftMargin: 6; topMargin: 4; bottomMargin: 4 }
                        text: "HH:MM"
                        color: Theme.textTertiary
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        verticalAlignment: Text.AlignVCenter
                        visible: !_endInput.text.length
                        enabled: false
                    }
                }
            }
        }

        // Description
        Rectangle {
            width: parent.width
            height: Math.max(60, _descInput.implicitHeight + 8)
            color: Theme.popupBackground
            border.color: Theme.textDim
            radius: 4

            TextEdit {
                id: _descInput
                anchors { fill: parent; margins: 4 }
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: 12
                wrapMode: TextEdit.WordWrap
            }
            Text {
                anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 4; topMargin: 4 }
                text: "Description"
                color: Theme.textTertiary
                font.family: Theme.fontFamily
                font.pixelSize: 12
                visible: !_descInput.text.length
                enabled: false
            }
        }

        // Submit / Cancel buttons
        Row {
            width: parent.width
            height: 28
            spacing: 6

            Rectangle {
                height: 28
                width: (parent.width - 6) / 2
                color: _submitArea.containsMouse ? root.submitColorHover : root.submitColor
                radius: 4

                Text {
                    anchors.centerIn: parent
                    text: root.submitLabel
                    color: Theme.textPrimary
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.bold: true
                }

                MouseArea {
                    id: _submitArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.submitted(_titleInput.text, _descInput.text,
                        root._allDay ? "" : _startInput.text,
                        root._allDay ? "" : _endInput.text)
                }
            }

            Rectangle {
                height: 28
                width: (parent.width - 6) / 2
                color: _cancelArea.containsMouse ? Theme.cellDefault : "transparent"
                border.color: Theme.textDim
                radius: 4

                Text {
                    anchors.centerIn: parent
                    text: "Cancel"
                    color: Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }

                MouseArea {
                    id: _cancelArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.cancelled()
                }
            }
        }
    }
}
