import QtQuick
import QtQuick.Controls
import Quickshell
import qs.components
import qs.singletons
import qs.singletons.googlecalendar

// Reusable event form: title, start/end time, description, submit + cancel.
// implicitHeight = inner Column height (no padding — caller wraps with margins).
Item {
    id: root

    implicitHeight: _col.implicitHeight

    property string submitLabel: "Save"
    // The submit button's kind (SmallButton): "save" adding an event, "saveChange" editing one
    property string submitKind: "saveChange"

    property bool showCalendarPicker: false
    property string selectedCalendarId: ""

    property string selectedColorId: ""
    property bool _allDay: false

    // Recurrence state
    property bool   _recurring:      false
    property string _rruleFreq:      "WEEKLY"   // DAILY|WEEKLY|MONTHLY|YEARLY
    property int    _rruleInterval:  1
    property var    _rruleDays:      []          // ["MO","WE",...] — weekly only
    property string _rruleEndType:   "never"     // "never"|"date"|"count"
    property string _rruleEndDate:   ""          // "YYYY-MM-DD"
    property int    _rruleCount:     1

    readonly property string rrule: {
        if (!_recurring) return ""
        let rule = "RRULE:FREQ=" + _rruleFreq + ";INTERVAL=" + _rruleInterval
        if (_rruleFreq === "WEEKLY" && _rruleDays.length > 0)
            rule += ";BYDAY=" + _rruleDays.join(",")
        if (_rruleEndType === "count")
            rule += ";COUNT=" + _rruleCount
        else if (_rruleEndType === "date" && _rruleEndDate.length === 10)
            rule += ";UNTIL=" + _rruleEndDate.replace(/-/g, "")
        return rule
    }

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

    function populate(title, startTime, endTime, description, allDay, colorId, rrule) {
        _titleInput.text = title;
        _startInput.setValue(startTime);
        _endInput.setValue(endTime);
        _descInput.text = description;
        _allDay = allDay ?? false;
        selectedColorId = colorId ?? "";
        _parseRrule(rrule ?? "");
    }

    function _parseRrule(rruleStr) {
        if (!rruleStr) { _recurring = false; return }
        _recurring = true
        let params = {}
        rruleStr.replace("RRULE:", "").split(";").forEach(p => {
            let eq = p.indexOf("="); params[p.slice(0, eq)] = p.slice(eq + 1)
        })
        _rruleFreq     = params["FREQ"]     || "WEEKLY"
        _rruleInterval = parseInt(params["INTERVAL"]) || 1
        _rruleDays     = params["BYDAY"] ? params["BYDAY"].split(",") : []
        if (params["COUNT"]) {
            _rruleEndType = "count"; _rruleCount = parseInt(params["COUNT"])
        } else if (params["UNTIL"]) {
            _rruleEndType = "date"
            let u = params["UNTIL"]
            _rruleEndDate = u.slice(0, 4) + "-" + u.slice(4, 6) + "-" + u.slice(6, 8)
        } else {
            _rruleEndType = "never"
        }
        _intervalInput.text  = _rruleInterval.toString()
        _countInput.text     = _rruleCount.toString()
        _endDateInput.text   = _rruleEndDate
    }

    function reset() {
        _titleInput.text = "";
        _startInput.clear();
        _endInput.clear();
        _descInput.text = "";
        _allDay = false;
        selectedColorId = "";
        _recurring = false;
        _rruleFreq = "WEEKLY"; _rruleInterval = 1; _rruleDays = []
        _rruleEndType = "never"; _rruleEndDate = ""; _rruleCount = 1
        _intervalInput.text = "1"
        _countInput.text    = "1"
        _endDateInput.text  = ""
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
        InputField {
            id: _titleInput
            fieldColor: Theme.popupBackground
            outlined: true
            placeholder: "Title"
            width: parent.width
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
                            radius: width / 2
                            anchors.centerIn: parent
                            color: Theme.textMuted
                            border.color: root.selectedColorId === "" ? Theme.textPrimary : "transparent"
                            border.width: Theme.border.selectedWidth

                            Text {
                                font.family: Theme.fontFamily
                                anchors.centerIn: parent
                                text: "×"
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSizeXSmall
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
                        // ScriptModel diffs old vs. new values so only changed delegates
                        // get added/removed — see MusicPanel.qml for why binding a plain
                        // live-model array straight to Repeater.model was crashing this
                        // app. Keyed by "id" since _colorEntries rebuilds fresh objects.
                        model: ScriptModel {
                            objectProp: "id"
                            values: root._colorEntries
                        }

                        Item {
                            required property var modelData
                            width: 20
                            height: 20
                            anchors.verticalCenter: parent.verticalCenter

                            Rectangle {
                                width: 16
                                height: 16
                                radius: width / 2
                                anchors.centerIn: parent
                                color: modelData.hex
                                border.color: root.selectedColorId === modelData.id ? Theme.textPrimary : "transparent"
                                border.width: Theme.border.selectedWidth
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
                radius: Theme.checkbox.radius
                anchors.verticalCenter: parent.verticalCenter
                color: root._allDay ? Theme.accent : "transparent"
                border.color: activeFocus ? Theme.textSecondary : (root._allDay ? Theme.accent : Theme.textDisabled)
                border.width: Theme.border.width
                activeFocusOnTab: true

                Text {
                    font.family: Theme.fontFamily
                    anchors.centerIn: parent
                    text: "✓"
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSizeTiny
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
                font.pixelSize: Theme.fontSizeBody
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
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
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
            border.color: _descInput.activeFocus ? Theme.textSecondary : Theme.textDisabled
            radius: Theme.field.radius

            TextEdit {
                id: _descInput
                selectionColor: Theme.selection
                selectedTextColor: Theme.selectedText
                anchors {
                    fill: parent
                    margins: 4
                }
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
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
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                visible: !_descInput.text.length
                enabled: false
            }
        }

        // Which calendar a new event goes to — only when showCalendarPicker
        Dropdown {
            width: parent.width
            visible: root.showCalendarPicker
            placeholder: "Select calendar"
            options: GoogleCalendar.enabledCalendarIds.map(id => ({
                value: id,
                label: GoogleCalendar.calendars[id]?.name ?? id,
                color: GoogleCalendar.calendars[id]?.color ?? Theme.textDisabled
            }))
            value: root.selectedCalendarId
            onPicked: value => root.selectedCalendarId = value
        }

        // Recurring toggle
        Row {
            width: parent.width
            height: 22
            spacing: 6

            Rectangle {
                width: 14
                height: 14
                radius: Theme.checkbox.radius
                anchors.verticalCenter: parent.verticalCenter
                color: root._recurring ? Theme.accent : "transparent"
                border.color: root._recurring ? Theme.accent : Theme.textDisabled
                border.width: Theme.border.width

                Text {
                    font.family: Theme.fontFamily
                    anchors.centerIn: parent
                    text: "✓"
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSizeTiny
                    visible: root._recurring
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root._recurring = !root._recurring
                }
            }

            Text {
                text: "Recurring"
                color: Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root._recurring = !root._recurring
                }
            }
        }

        // Expandable recurrence section
        Item {
            width: parent.width
            height: root._recurring ? _recurSection.implicitHeight : 0
            clip: true

            Behavior on height {
                NumberAnimation {
                    duration: Theme.duration("expand")
                    easing: Theme.curve("expand")
                }
            }

            Column {
                id: _recurSection
                width: parent.width
                spacing: 6

                // Frequency row: [Freq ▾]  Every  [N]  unit(s)
                Row {
                    width: parent.width
                    height: 28
                    spacing: 6

                    readonly property var _freqLabels: ({ "DAILY": "Daily", "WEEKLY": "Weekly", "MONTHLY": "Monthly", "YEARLY": "Yearly" })
                    readonly property var _unitLabels: ({ "DAILY": "day(s)", "WEEKLY": "week(s)", "MONTHLY": "month(s)", "YEARLY": "year(s)" })

                    // Frequency
                    Dropdown {
                        width: Math.max(76, implicitWidth)
                        implicitWidth: _freqWidest.advanceWidth + 36
                        options: ["DAILY", "WEEKLY", "MONTHLY", "YEARLY"].map(code => ({ value: code, label: parent._freqLabels[code] }))
                        value: root._rruleFreq
                        onPicked: value => root._rruleFreq = value

                        TextMetrics {
                            id: _freqWidest
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            text: "Monthly"
                        }
                    }

                    Text {
                        text: "Every"
                        color: Theme.textSecondary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    // Interval input
                    InputField {
                        id: _intervalInput
                        fieldColor: Theme.popupBackground
                        outlined: true
                        width: 40
                        text: "1"
                        input.horizontalAlignment: TextInput.AlignHCenter
                        input.validator: IntValidator { bottom: 1; top: 999 }
                        onTextEdited: {
                            let value = parseInt(text)
                            if (!isNaN(value) && value >= 1) root._rruleInterval = value
                        }
                    }

                    Text {
                        text: parent._unitLabels[root._rruleFreq] ?? ""
                        color: Theme.textSecondary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // "Repeat on" days row — weekly only
                Row {
                    width: parent.width
                    height: 22
                    spacing: 4
                    visible: root._rruleFreq === "WEEKLY"

                    readonly property var _dayCodes:  ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
                    readonly property var _dayLabels: ["M",  "T",  "W",  "T",  "F",  "S",  "S" ]

                    Repeater {
                        model: 7

                        Pill {
                            required property int index
                            readonly property string dayCode: parent._dayCodes[index]
                            // All days as wide as the widest letter, so the row is even
                            implicitWidth: Math.max(22, implicitHeight)
                            anchors.verticalCenter: parent.verticalCenter
                            label: parent._dayLabels[index]
                            picked: root._rruleDays.indexOf(dayCode) >= 0
                            fontSize: Theme.fontSizeXSmall
                            onClicked: {
                                let days = root._rruleDays.slice()
                                let idx = days.indexOf(dayCode)
                                if (idx >= 0) days.splice(idx, 1)
                                else days.push(dayCode)
                                root._rruleDays = days
                            }
                        }
                    }
                }

                // Ends row — radio-style buttons
                Row {
                    width: parent.width
                    height: 22
                    spacing: 6

                    Text {
                        text: "Ends:"
                        color: Theme.textSecondary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Repeater {
                        model: [
                            { value: "never", label: "Never"   },
                            { value: "date",  label: "On date" },
                            { value: "count", label: "After N" }
                        ]

                        Pill {
                            required property var modelData
                            anchors.verticalCenter: parent.verticalCenter
                            label: modelData.label
                            picked: root._rruleEndType === modelData.value
                            onClicked: root._rruleEndType = modelData.value
                        }
                    }
                }

                // End date input — visible when ends = "date"
                InputField {
                    id: _endDateInput
                    fieldColor: Theme.popupBackground
                    outlined: true
                    placeholder: "YYYY-MM-DD"
                    width: parent.width
                    visible: root._rruleEndType === "date"
                    onTextEdited: root._rruleEndDate = text
                }

                // End count input — visible when ends = "count"
                Row {
                    width: parent.width
                    height: 28
                    spacing: 6
                    visible: root._rruleEndType === "count"

                    InputField {
                        id: _countInput
                        fieldColor: Theme.popupBackground
                        outlined: true
                        width: 50
                        text: "1"
                        input.horizontalAlignment: TextInput.AlignHCenter
                        input.validator: IntValidator { bottom: 1; top: 999 }
                        onTextEdited: {
                            let value = parseInt(text)
                            if (!isNaN(value) && value >= 1) root._rruleCount = value
                        }
                    }

                    Text {
                        text: "times"
                        color: Theme.textSecondary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }

        // Submit / Cancel buttons
        Row {
            width: parent.width
            spacing: 6

            SmallButton {
                width: (parent.width - 6) / 2
                label: root.submitLabel
                kind: root.submitKind
                onClicked: root.submitted(_titleInput.text, _descInput.text, root._allDay ? "" : _startInput.text, root._allDay ? "" : _endInput.text)
            }

            SmallButton {
                width: (parent.width - 6) / 2
                label: "Cancel"
                kind: "cancel"
                onClicked: root.cancelled()
            }
        }
    }
}
