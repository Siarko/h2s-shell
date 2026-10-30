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
    property color submitColor: Theme.confirmSecondary
    property color submitColorHover: Theme.confirmSecondaryHover

    property bool showCalendarPicker: false
    property string selectedCalendarId: ""
    property bool _pickerOpen: false

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
    property bool   _freqPickerOpen: false

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
        _pickerOpen = false;
        selectedColorId = "";
        _recurring = false;
        _rruleFreq = "WEEKLY"; _rruleInterval = 1; _rruleDays = []
        _rruleEndType = "never"; _rruleEndDate = ""; _rruleCount = 1
        _freqPickerOpen = false
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
        Rectangle {
            width: parent.width
            height: 28
            color: Theme.popupBackground
            border.color: _titleInput.activeFocus ? Theme.textSecondary : Theme.textDisabled
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
                font.pixelSize: Theme.fontSizeBody
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
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
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
                            color: Theme.textMuted
                            border.color: root.selectedColorId === "" ? Theme.textPrimary : "transparent"
                            border.width: 2

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
                                radius: 8
                                anchors.centerIn: parent
                                color: modelData.hex
                                border.color: root.selectedColorId === modelData.id ? Theme.textPrimary : "transparent"
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
                color: root._allDay ? Theme.accent : "transparent"
                border.color: activeFocus ? Theme.textSecondary : (root._allDay ? Theme.accent : Theme.textDisabled)
                border.width: 1
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
            radius: 4

            TextEdit {
                id: _descInput
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

        // Calendar picker button — visible only when showCalendarPicker
        Rectangle {
            width: parent.width
            height: 28
            visible: root.showCalendarPicker
            color: Theme.popupBackground
            border.color: Theme.textDisabled
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
                    color: parent.parent._selectedCal?.color ?? Theme.textDisabled
                }

                Text {
                    text: parent.parent._selectedCal?.name ?? "Select calendar"
                    color: Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 30
                    elide: Text.ElideRight
                }

                Text {
                    font.family: Theme.fontFamily
                    text: "▾"
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSizeXSmall
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
            border.color: Theme.textDisabled
            radius: 4

            Behavior on height {
                NumberAnimation {
                    duration: Theme.duration("expand")
                    easing: Theme.curve("expand")
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
                    // ScriptModel diffs old vs. new values so only changed delegates get
                    // added/removed — see MusicPanel.qml for why binding a plain live-model
                    // array straight to Repeater.model was crashing this app.
                    model: ScriptModel {
                        values: GoogleCalendar.enabledCalendarIds
                    }

                    Rectangle {
                        required property string modelData
                        readonly property var _cal: GoogleCalendar.calendars[modelData] ?? null

                        width: _pickerList.width
                        height: 24
                        color: modelData === root.selectedCalendarId ? Theme.surfaceHover : "transparent"
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
                                color: parent.parent._cal?.color ?? Theme.textDisabled
                            }

                            Text {
                                text: parent.parent._cal?.name ?? modelData
                                color: Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody
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

        // Recurring toggle
        Row {
            width: parent.width
            height: 22
            spacing: 6

            Rectangle {
                width: 14
                height: 14
                radius: 3
                anchors.verticalCenter: parent.verticalCenter
                color: root._recurring ? Theme.accent : "transparent"
                border.color: root._recurring ? Theme.accent : Theme.textDisabled
                border.width: 1

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

                    // Frequency dropdown button
                    Rectangle {
                        width: 76
                        height: 28
                        color: Theme.popupBackground
                        border.color: Theme.textDisabled
                        radius: 4

                        Row {
                            anchors {
                                fill: parent
                                leftMargin: 6
                                rightMargin: 4
                            }
                            spacing: 4

                            Text {
                                text: parent.parent.parent._freqLabels[root._rruleFreq] ?? root._rruleFreq
                                color: Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 14
                                elide: Text.ElideRight
                            }

                            Text {
                                font.family: Theme.fontFamily
                                text: "▾"
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSizeXSmall
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root._freqPickerOpen = !root._freqPickerOpen
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
                    Rectangle {
                        width: 40
                        height: 28
                        color: Theme.popupBackground
                        border.color: _intervalInput.activeFocus ? Theme.textSecondary : Theme.textDisabled
                        radius: 4

                        TextInput {
                            id: _intervalInput
                            anchors {
                                fill: parent
                                leftMargin: 4
                                rightMargin: 4
                                topMargin: 4
                                bottomMargin: 4
                            }
                            text: "1"
                            color: Theme.textPrimary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            verticalAlignment: TextInput.AlignVCenter
                            horizontalAlignment: TextInput.AlignHCenter
                            validator: IntValidator { bottom: 1; top: 999 }
                            onTextEdited: {
                                let value = parseInt(text)
                                if (!isNaN(value) && value >= 1) root._rruleInterval = value
                            }
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

                // Frequency dropdown list
                Rectangle {
                    width: parent.width
                    height: root._freqPickerOpen ? _freqList.implicitHeight + 4 : 0
                    clip: true
                    color: Theme.popupBackground
                    border.color: Theme.textDisabled
                    radius: 4

                    Behavior on height {
                        NumberAnimation {
                            duration: Theme.duration("expand")
                            easing: Theme.curve("expand")
                        }
                    }

                    Column {
                        id: _freqList
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: 2
                        }

                        Repeater {
                            model: ["DAILY", "WEEKLY", "MONTHLY", "YEARLY"]

                            Rectangle {
                                required property string modelData
                                readonly property var _labels: ({ "DAILY": "Daily", "WEEKLY": "Weekly", "MONTHLY": "Monthly", "YEARLY": "Yearly" })

                                width: _freqList.width
                                height: 24
                                color: modelData === root._rruleFreq ? Theme.surfaceHover : "transparent"
                                radius: 3

                                Text {
                                    anchors {
                                        fill: parent
                                        leftMargin: 6
                                    }
                                    text: parent._labels[modelData] ?? modelData
                                    color: Theme.textSecondary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeBody
                                    verticalAlignment: Text.AlignVCenter
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root._rruleFreq = modelData
                                        root._freqPickerOpen = false
                                    }
                                }
                            }
                        }
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
                Rectangle {
                    width: parent.width
                    height: 28
                    visible: root._rruleEndType === "date"
                    color: Theme.popupBackground
                    border.color: _endDateInput.activeFocus ? Theme.textSecondary : Theme.textDisabled
                    radius: 4

                    TextInput {
                        id: _endDateInput
                        anchors {
                            fill: parent
                            leftMargin: 6
                            rightMargin: 6
                            topMargin: 4
                            bottomMargin: 4
                        }
                        color: Theme.textPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        verticalAlignment: TextInput.AlignVCenter
                        onTextEdited: root._rruleEndDate = text
                    }

                    Text {
                        anchors {
                            fill: parent
                            leftMargin: 6
                            topMargin: 4
                            bottomMargin: 4
                        }
                        text: "YYYY-MM-DD"
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        verticalAlignment: Text.AlignVCenter
                        visible: !_endDateInput.text.length
                        enabled: false
                    }
                }

                // End count input — visible when ends = "count"
                Row {
                    width: parent.width
                    height: 28
                    spacing: 6
                    visible: root._rruleEndType === "count"

                    Rectangle {
                        width: 50
                        height: 28
                        color: Theme.popupBackground
                        border.color: _countInput.activeFocus ? Theme.textSecondary : Theme.textDisabled
                        radius: 4

                        TextInput {
                            id: _countInput
                            anchors {
                                fill: parent
                                leftMargin: 4
                                rightMargin: 4
                                topMargin: 4
                                bottomMargin: 4
                            }
                            text: "1"
                            color: Theme.textPrimary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            verticalAlignment: TextInput.AlignVCenter
                            horizontalAlignment: TextInput.AlignHCenter
                            validator: IntValidator { bottom: 1; top: 999 }
                            onTextEdited: {
                                let value = parseInt(text)
                                if (!isNaN(value) && value >= 1) root._rruleCount = value
                            }
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
                    font.pixelSize: Theme.fontSizeSmall
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
                color: _cancelArea.containsMouse ? Theme.surface : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }
                border.color: Theme.textDisabled
                radius: 4

                Text {
                    anchors.centerIn: parent
                    text: "Cancel"
                    color: Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
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
