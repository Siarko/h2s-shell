import QtQuick
import QtQuick.Controls
import qs.singletons
import qs.singletons.googlecalendar

// Reusable event form: title, start/end time, description, submit + cancel.
// implicitHeight = inner Column height (no padding — caller wraps with margins).
Item {
    id: root

    implicitHeight: _col.implicitHeight

    property string submitLabel: "Save"
    property color submitColor: "#1e3a5f"
    property color submitColorHover: "#2d4a6d"

    property bool showCalendarPicker: false
    property string selectedCalendarId: ""
    property bool _pickerOpen: false

    property string selectedColorId: ""
    property bool _allDay: false

    signal submitted(string title, string description, string startTime, string endTime)
    signal cancelled

    Component.onCompleted: {
        if (showCalendarPicker && selectedCalendarId === "") {
            let enabled = GoogleCalendar.enabledCalendarIds;
            if (enabled && enabled.length > 0)
                selectedCalendarId = enabled[0];
        }
    }

    readonly property var _colorEntries: {
        let keys = Object.keys(GoogleCalendar._colorMapEvents).sort((a, b) => parseInt(a) - parseInt(b));
        return keys.map(k => ({
                    id: k,
                    hex: GoogleCalendar._colorMapEvents[k]
                }));
    }

    function populate(title, startTime, endTime, description, allDay, colorId) {
        _titleInput.text = title;
        _startInput.setValue(startTime);
        _endInput.setValue(endTime);
        _descInput.text = description;
        _allDay = allDay ?? false;
        selectedColorId = colorId ?? "";
    }

    function reset() {
        _titleInput.text = "";
        _startInput.clear();
        _endInput.clear();
        _descInput.text = "";
        _allDay = false;
        _pickerOpen = false;
        selectedColorId = "";
    }

    Column {
        id: _col
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        spacing: 6

        // Title
        Rectangle {
            width: parent.width
            height: 28
            color: Theme.popupBackground
            border.color: _titleInput.activeFocus ? Theme.textSecondary : Theme.textDim
            radius: 4

            TextInput {
                id: _titleInput
                anchors {
                    fill: parent
                    leftMargin: 6
                    rightMargin: 6
                    topMargin: 4
                    bottomMargin: 4
                }
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: 12
                verticalAlignment: TextInput.AlignVCenter
            }
            Text {
                anchors {
                    fill: parent
                    leftMargin: 6
                    topMargin: 4
                    bottomMargin: 4
                }
                text: "Title"
                color: Theme.textTertiary
                font.family: Theme.fontFamily
                font.pixelSize: 12
                verticalAlignment: Text.AlignVCenter
                visible: !_titleInput.text.length
                enabled: false
            }
        }

        // Color picker row
        Item {
            width: parent.width
            height: 24 + _colorScrollBar.height

            Flickable {
                id: _colorFlickable
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                }
                height: 24
                contentWidth: _colorRow.implicitWidth
                contentHeight: height
                clip: true
                flickableDirection: Flickable.HorizontalFlick

                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse
                    onWheel: event => {
                        _colorFlickable.contentX = Math.max(0, Math.min(_colorFlickable.contentWidth - _colorFlickable.width, _colorFlickable.contentX - event.angleDelta.y / 2));
                    }
                }

                Row {
                    id: _colorRow
                    height: parent.height
                    spacing: 6

                    // Default swatch (no color override)
                    Item {
                        width: 20
                        height: 20
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            width: 16
                            height: 16
                            radius: 8
                            anchors.centerIn: parent
                            color: "#888888"
                            border.color: root.selectedColorId === "" ? "white" : "transparent"
                            border.width: 2

                            Text {
                                anchors.centerIn: parent
                                text: "×"
                                color: "white"
                                font.pixelSize: 10
                                font.bold: true
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectedColorId = ""
                        }
                    }

                    Repeater {
                        model: root._colorEntries

                        Item {
                            required property var modelData
                            width: 20
                            height: 20
                            anchors.verticalCenter: parent.verticalCenter

                            Rectangle {
                                width: 16
                                height: 16
                                radius: 8
                                anchors.centerIn: parent
                                color: modelData.hex
                                border.color: root.selectedColorId === modelData.id ? "white" : "transparent"
                                border.width: 2
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectedColorId = modelData.id
                            }
                        }
                    }
                }
            }

            ScrollBar {
                id: _colorScrollBar
                anchors {
                    left: parent.left
                    right: parent.right
                    top: _colorFlickable.bottom
                }
                orientation: Qt.Horizontal
                size: _colorFlickable.visibleArea.widthRatio
                position: _colorFlickable.visibleArea.xPosition
                onPositionChanged: if (active)
                    _colorFlickable.contentX = position * _colorFlickable.contentWidth
                policy: ScrollBar.AsNeeded
                contentItem: Rectangle {
                    implicitWidth: 5
                    implicitHeight: 5
                    radius: height / 2
                    color: Theme.textSecondary
                }
            }
        }

        // All day toggle
        Row {
            width: parent.width
            height: 22
            spacing: 6

            Rectangle {
                id: _allDayCheckbox
                width: 14
                height: 14
                radius: 3
                anchors.verticalCenter: parent.verticalCenter
                color: root._allDay ? Theme.sliderAccent : "transparent"
                border.color: activeFocus ? Theme.textSecondary : (root._allDay ? Theme.sliderAccent : Theme.textDim)
                border.width: 1
                activeFocusOnTab: true

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

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Space) {
                        root._allDay = !root._allDay;
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier)) {
                        if (root._allDay)
                            _descInput.forceActiveFocus();
                        else
                            _startInput.focusHours();
                        event.accepted = true;
                    }
                // Shift+Tab handled naturally by Qt via activeFocusOnTab (goes back to _titleInput)
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

                TimeField {
                    id: _startInput
                    width: (parent.width - 20) / 2
                    height: 28
                    onTabOutForward: _endInput.focusHours()
                    onTabOutBackward: _allDayCheckbox.forceActiveFocus()
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

                TimeField {
                    id: _endInput
                    width: (parent.width - 20) / 2
                    height: 28
                    onTabOutForward: _descInput.forceActiveFocus()
                    onTabOutBackward: _startInput.focusMinutes()
                }
            }
        }

        // Description
        Rectangle {
            width: parent.width
            height: Math.max(60, _descInput.implicitHeight + 8)
            color: Theme.popupBackground
            border.color: _descInput.activeFocus ? Theme.textSecondary : Theme.textDim
            radius: 4

            TextEdit {
                id: _descInput
                anchors {
                    fill: parent
                    margins: 4
                }
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: 12
                wrapMode: TextEdit.WordWrap

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier)) {
                        if (root._allDay)
                            _allDayCheckbox.forceActiveFocus();
                        else
                            _endInput.focusMinutes();
                        event.accepted = true;
                    }
                }
            }
            Text {
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    leftMargin: 4
                    topMargin: 4
                }
                text: "Description"
                color: Theme.textTertiary
                font.family: Theme.fontFamily
                font.pixelSize: 12
                visible: !_descInput.text.length
                enabled: false
            }
        }

        // Calendar picker button — visible only when showCalendarPicker
        Rectangle {
            width: parent.width
            height: 28
            visible: root.showCalendarPicker
            color: Theme.popupBackground
            border.color: Theme.textDim
            radius: 4

            readonly property var _selectedCal: GoogleCalendar.calendars[root.selectedCalendarId] ?? null

            Row {
                anchors {
                    fill: parent
                    leftMargin: 6
                    rightMargin: 6
                }
                spacing: 6

                Rectangle {
                    width: 10
                    height: 10
                    radius: 5
                    anchors.verticalCenter: parent.verticalCenter
                    color: parent.parent._selectedCal?.color ?? Theme.textDim
                }

                Text {
                    text: parent.parent._selectedCal?.name ?? "Select calendar"
                    color: Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 30
                    elide: Text.ElideRight
                }

                Text {
                    text: "▾"
                    color: Theme.textTertiary
                    font.pixelSize: 10
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root._pickerOpen = !root._pickerOpen
            }
        }

        // Calendar dropdown list
        Rectangle {
            width: parent.width
            height: root._pickerOpen && root.showCalendarPicker ? _pickerList.implicitHeight + 4 : 0
            visible: root.showCalendarPicker
            clip: true
            color: Theme.popupBackground
            border.color: Theme.textDim
            radius: 4

            Behavior on height {
                NumberAnimation {
                    duration: 120
                    easing.type: Easing.OutQuad
                }
            }

            Column {
                id: _pickerList
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 2
                }

                Repeater {
                    model: GoogleCalendar.enabledCalendarIds

                    Rectangle {
                        required property string modelData
                        readonly property var _cal: GoogleCalendar.calendars[modelData] ?? null

                        width: _pickerList.width
                        height: 24
                        color: modelData === root.selectedCalendarId ? Theme.cellHover : "transparent"
                        radius: 3

                        Row {
                            anchors {
                                fill: parent
                                leftMargin: 6
                            }
                            spacing: 6

                            Rectangle {
                                width: 10
                                height: 10
                                radius: 5
                                anchors.verticalCenter: parent.verticalCenter
                                color: parent.parent._cal?.color ?? Theme.textDim
                            }

                            Text {
                                text: parent.parent._cal?.name ?? modelData
                                color: Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 22
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.selectedCalendarId = modelData;
                                root._pickerOpen = false;
                            }
                        }
                    }
                }
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
                    onClicked: root.submitted(_titleInput.text, _descInput.text, root._allDay ? "" : _startInput.text, root._allDay ? "" : _endInput.text)
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
