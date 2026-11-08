import QtQuick
import qs.components
import qs.singletons
import qs.singletons.googlecalendar

// The event form's "Recurring" checkbox and, below it while checked, how the event
// repeats: how often, every how many, on which days (weekly), and how it ends. `rrule` is
// the result as Google takes it ("" when not recurring); `setRule` shows an existing one,
// `reset` clears it. The rule's text is built and read by CalendarDates.
Column {
    id: root

    readonly property string rrule: _recurring ? CalendarDates.recurrenceRule({
        freq: _freq, interval: _interval, days: _days, endType: _endType, endDate: _endDate, count: _count
    }) : ""

    property bool   _recurring: false
    property string _freq:      "WEEKLY"   // DAILY|WEEKLY|MONTHLY|YEARLY
    property int    _interval:  1
    property var    _days:      []         // ["MO","WE",...] — weekly only
    property string _endType:   "never"    // "never"|"date"|"count"
    property string _endDate:   ""         // "YYYY-MM-DD"
    property int    _count:     1

    function setRule(ruleText) {
        const parsed = CalendarDates.parseRecurrence(ruleText);
        const recurrence = parsed ?? CalendarDates.defaultRecurrence;
        _recurring = parsed !== null;
        _freq = recurrence.freq;
        _interval = recurrence.interval;
        _days = recurrence.days;
        _endType = recurrence.endType;
        _endDate = recurrence.endDate;
        _count = recurrence.count;
        // The fields are typed into, so they hold their own text rather than a binding
        _intervalInput.text = _interval.toString();
        _countInput.text = _count.toString();
        _endDateInput.text = _endDate;
    }

    function reset() {
        setRule("");
    }

    spacing: 6

    Checkbox {
        label: "Recurring"
        checked: root._recurring
        onToggled: root._recurring = !root._recurring
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

            // Frequency row: [Freq ▾]  Every  [N]  unit(s) — wrapping onto a second line
            // when the card is too narrow for it
            Flow {
                id: _frequencyRow
                width: parent.width
                spacing: 6

                readonly property var _freqLabels: ({ "DAILY": "Daily", "WEEKLY": "Weekly", "MONTHLY": "Monthly", "YEARLY": "Yearly" })
                readonly property var _unitLabels: ({ "DAILY": "day(s)", "WEEKLY": "week(s)", "MONTHLY": "month(s)", "YEARLY": "year(s)" })

                // Frequency
                Dropdown {
                    width: Math.max(76, implicitWidth)
                    implicitWidth: _freqWidest.advanceWidth + 36
                    options: ["DAILY", "WEEKLY", "MONTHLY", "YEARLY"].map(code => ({ value: code, label: parent._freqLabels[code] }))
                    value: root._freq
                    onPicked: value => root._freq = value

                    TextMetrics {
                        id: _freqWidest
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        text: "Monthly"
                    }
                }

                Text {
                    height: _intervalInput.height
                    verticalAlignment: Text.AlignVCenter
                    text: "Every"
                    color: Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                }

                // Interval input
                InputField {
                    id: _intervalInput
                    fieldColor: Theme.popupBackground
                    outlined: true
                    width: Theme.scaled(40)
                    text: "1"
                    input.horizontalAlignment: TextInput.AlignHCenter
                    input.validator: IntValidator { bottom: 1; top: 999 }
                    input.inputMethodHints: Qt.ImhDigitsOnly
                    onTextEdited: {
                        const value = parseInt(text);
                        if (!isNaN(value) && value >= 1)
                            root._interval = value;
                    }
                }

                Text {
                    height: _intervalInput.height
                    verticalAlignment: Text.AlignVCenter
                    text: parent._unitLabels[root._freq] ?? ""
                    color: Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                }
            }

            // "Repeat on" days row — weekly only
            Row {
                width: parent.width
                height: 22
                spacing: 4
                visible: root._freq === "WEEKLY"

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
                        picked: root._days.indexOf(dayCode) >= 0
                        fontSize: Theme.fontSizeXSmall
                        onClicked: {
                            const days = root._days.slice();
                            const position = days.indexOf(dayCode);
                            if (position >= 0)
                                days.splice(position, 1);
                            else
                                days.push(dayCode);
                            root._days = days;
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
                        picked: root._endType === modelData.value
                        onClicked: root._endType = modelData.value
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
                visible: root._endType === "date"
                onTextEdited: root._endDate = text
            }

            // End count input — visible when ends = "count"
            Row {
                width: parent.width
                height: 28
                spacing: 6
                visible: root._endType === "count"

                InputField {
                    id: _countInput
                    fieldColor: Theme.popupBackground
                    outlined: true
                    width: 50
                    text: "1"
                    input.horizontalAlignment: TextInput.AlignHCenter
                    input.validator: IntValidator { bottom: 1; top: 999 }
                    input.inputMethodHints: Qt.ImhDigitsOnly
                    onTextEdited: {
                        const value = parseInt(text);
                        if (!isNaN(value) && value >= 1)
                            root._count = value;
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
}
