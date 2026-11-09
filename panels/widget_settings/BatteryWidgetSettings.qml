import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.singletons

// The battery widget's preset (BatteryWidget): where the percentage stands, and the
// colour thresholds — any number of them, each a charge and a hex colour; the icon takes
// the colour of the tightest threshold at or above the charge (BatteryRules.color); and a
// colour while plugged in, which wins over them (BatteryRules.widgetColor).
Item {
    id: root
    property string presetName: ""
    property string widgetType: "battery"

    implicitHeight: _col.implicitHeight

    readonly property string _percentSide: WidgetPresets.value(widgetType, presetName, "percent") ?? "right"
    readonly property var _thresholds: WidgetPresets.value(widgetType, presetName, "thresholds") ?? []
    readonly property string _chargingColor: WidgetPresets.value(widgetType, presetName, "chargingColor") ?? ""

    readonly property var _sides: [
        { value: "left", label: "Left" },
        { value: "right", label: "Right" },
        { value: "none", label: "None" }
    ]

    // A copy of the thresholds with one changed (or removed), written to the preset
    function _writeThresholds(change) {
        const list = JSON.parse(JSON.stringify(root._thresholds));
        change(list);
        WidgetPresets.set(root.widgetType, root.presetName, "thresholds", list);
    }

    component Label: Text {
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBody
        color: Theme.textSecondary
        Layout.preferredWidth: 80
        // A label longer than the column (a larger font) is cut, not run into the control
        elide: Text.ElideRight
    }

    component Hint: Text {
        wrapMode: Text.WordWrap
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.textMuted
    }

    Column {
        id: _col
        width: parent.width
        topPadding: 4
        spacing: 10

        // Where the percentage stands
        RowLayout {
            width: _col.width
            spacing: 8

            Label { text: "Percentage" }

            Flow {
                Layout.fillWidth: true
                spacing: 4

                Repeater {
                    // ScriptModel, never the bare array (CLAUDE.md)
                    model: ScriptModel { values: root._sides }

                    Pill {
                        required property var modelData
                        label: modelData.label
                        picked: modelData.value === root._percentSide
                        fontSize: Theme.fontSizeBody
                        minimumHeight: 26
                        onClicked: WidgetPresets.set(root.widgetType, root.presetName, "percent", modelData.value)
                    }
                }
            }
        }

        Hint {
            width: _col.width
            text: root._percentSide === "none" ? "Only the icon on the bar."
                : "The charge in percent, " + (root._percentSide === "left" ? "before" : "after") + " the icon."
        }

        // The colour thresholds
        RowLayout {
            width: _col.width
            spacing: 8

            Label { text: "Colours" }

            Hint {
                Layout.fillWidth: true
                text: root._thresholds.length === 0
                    ? "No thresholds: the icon has the text colour. Add one to colour a low battery."
                    : "The icon takes the colour of the lowest threshold the charge is at or below; above them all, the text colour."
            }
        }

        Repeater {
            model: ScriptModel { values: root._thresholds.map((threshold, index) => ({ index: index, threshold: threshold })) }

            RowLayout {
                id: _row
                required property var modelData
                readonly property int _index: modelData.index
                readonly property var _threshold: modelData.threshold
                readonly property bool _colorValid: BatteryRules.isHexColor(String(_threshold.color ?? ""))

                width: _col.width
                spacing: 6

                Text {
                    Layout.leftMargin: 88
                    text: "At or below"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textSecondary
                }

                InputField {
                    implicitWidth: 52
                    text: String(_row._threshold.value ?? "")
                    outlined: true
                    input.horizontalAlignment: TextInput.AlignHCenter
                    input.validator: IntValidator { bottom: 0; top: 100 }
                    input.inputMethodHints: Qt.ImhDigitsOnly
                    problem: text === ""
                    onEditingFinished: {
                        const value = parseInt(text, 10);
                        if (isNaN(value) || value === _row._threshold.value)
                            return;
                        root._writeThresholds(list => list[_row._index].value = value);
                    }
                }

                Text {
                    text: "%"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textSecondary
                }

                // What the colour looks like; outlined only while the hex is not one
                Rectangle {
                    Layout.leftMargin: 6
                    implicitWidth: 22
                    implicitHeight: 22
                    radius: Theme.field.radius
                    color: _row._colorValid ? _row._threshold.color : "transparent"
                    border.width: Theme.border.width
                    border.color: Theme.outline
                }

                InputField {
                    id: _hex
                    implicitWidth: 96
                    text: String(_row._threshold.color ?? "")
                    placeholder: "#rrggbb"
                    outlined: true
                    problem: !BatteryRules.isHexColor(text)
                    input.maximumLength: 9
                    input.inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhPreferLowercase
                    onEditingFinished: {
                        if (text === _row._threshold.color)
                            return;
                        root._writeThresholds(list => list[_row._index].color = text);
                    }
                }

                Item { Layout.fillWidth: true }

                DeleteButton {
                    label: "Remove"
                    confirmLabel: "Remove?"
                    cancelTip: "Cancel — keep the threshold"
                    onConfirmed: root._writeThresholds(list => list.splice(_row._index, 1))
                }
            }
        }

        SmallButton {
            x: 88
            label: "Add threshold"
            // A new one starts low and in the warning colour, to be changed
            onClicked: root._writeThresholds(list => list.push({ value: 20, color: String(Theme.warning) }))
        }

        // The colour while plugged in
        RowLayout {
            width: _col.width
            spacing: 6

            Label { text: "Charging" }

            // What the colour looks like; outlined only while the hex is not one
            Rectangle {
                implicitWidth: 22
                implicitHeight: 22
                radius: Theme.field.radius
                color: BatteryRules.isHexColor(root._chargingColor) ? root._chargingColor : "transparent"
                border.width: Theme.border.width
                border.color: Theme.outline
            }

            InputField {
                implicitWidth: 96
                text: root._chargingColor
                placeholder: "#rrggbb"
                outlined: true
                // Empty is allowed: no colour of its own
                problem: text !== "" && !BatteryRules.isHexColor(text)
                input.maximumLength: 9
                input.inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhPreferLowercase
                onEditingFinished: {
                    if (text !== root._chargingColor)
                        WidgetPresets.set(root.widgetType, root.presetName, "chargingColor", text);
                }
            }

            Item { Layout.fillWidth: true }
        }

        Hint {
            x: 88
            width: _col.width - 88
            text: root._chargingColor === ""
                ? "Empty: plugged in, the icon follows the thresholds as on battery."
                : "Plugged in — charging, full on the charger or holding off — the icon and the percentage take this colour, over the thresholds."
        }
    }
}
