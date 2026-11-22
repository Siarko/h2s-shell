import QtQuick
import Quickshell
import QtQuick.Layouts
import qs.components
import qs.singletons

// One monitor's times on the "When away" page, under "Set per monitor": "Same as all
// monitors" (a line repeats the default) or "Own times" — its own screensaver and
// screen-off, each a switch and its times. A monitor not connected keeps its times and can
// be forgotten. The page writes: `edited(times)` gives the monitor's whole entry
// (IdleRules.monitorTimes) or "default".
Rectangle {
    id: root

    // Its name and connector ("" not connected)
    property string name: ""
    property string connector: ""
    // Its own times as kept ({ screensaverEnabled, screensaverTimeout, screenOffEnabled,
    // screenOffTimeout }), or null: it follows the default
    property var own: null
    // The default's times, the same four fields
    property var defaults: ({})
    // The map is inherited in the edited profile: the picked choices dimmed
    property bool dimmed: false
    property bool canPowerOff: true
    signal edited(var times)

    readonly property bool connected: connector !== ""
    readonly property bool _own: own !== null && typeof own === "object"

    function _with(field, value) {
        const times = Object.assign({}, _own ? own : defaults);
        times[field] = value;
        edited(times);
    }

    function _defaultLine() {
        const saver = defaults.screensaverEnabled === true ? "Screensaver after " + Format.duration(defaults.screensaverTimeout) : "No screensaver";
        const off = defaults.screenOffEnabled === true ? "turned off after " + Format.duration(defaults.screenOffTimeout) : "not turned off";
        return saver + " · " + off;
    }

    Layout.fillWidth: true
    implicitHeight: _column.implicitHeight + 16
    radius: Theme.settings.cardRadius
    color: "transparent"
    border.width: Theme.border.width
    border.color: Theme.outline

    // Times as pills: the presets and the value set when it is not one of them
    component TimePills: Flow {
        id: _pills
        property int value: 0
        property bool dimmed: false
        signal picked(int value)
        spacing: 4

        Repeater {
            model: ScriptModel {
                values: SettingsSchema.idlePresets.concat(SettingsSchema.idlePresets.includes(_pills.value) ? [] : [_pills.value])
                    .sort((a, b) => a - b).map(String)
            }

            Pill {
                required property string modelData
                label: Format.duration(Number(modelData))
                picked: Number(modelData) === _pills.value
                fontSize: Theme.fontSizeBody
                size: "m"
                opacity: picked && _pills.dimmed ? 0.5 : 1
                onClicked: _pills.picked(Number(modelData))
            }
        }
    }

    // A stage: its switch on its line, its times sliding open under it while on
    component Stage: ColumnLayout {
        id: _stage
        property string label: ""
        property string hint: ""
        property bool on: false
        property int value: 0
        property bool dimmed: false
        signal switched()
        signal picked(int value)
        Layout.fillWidth: true
        spacing: 2

        SettingsRow {
            label: _stage.label
            hint: _stage.hint
            ToggleSwitch {
                checked: _stage.on
                opacity: _stage.dimmed ? 0.5 : 1
                onToggled: _stage.switched()
            }
        }
        Reveal {
            open: _stage.on
            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 4
                spacing: 8
                Text {
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 6
                    text: "after"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.textMuted
                }
                TimePills {
                    Layout.fillWidth: true
                    value: _stage.value
                    dimmed: _stage.dimmed
                    onPicked: value => _stage.picked(value)
                }
            }
        }
    }

    ColumnLayout {
        id: _column
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text {
                text: root.name
                textFormat: Text.PlainText
                elide: Text.ElideRight
                // Its whole name; the connector gives way
                Layout.maximumWidth: Math.ceil(implicitWidth)
                Layout.preferredWidth: Math.ceil(implicitWidth)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                font.bold: true
                color: root.connected ? Theme.textPrimary : Theme.textSecondary
            }
            Text {
                Layout.fillWidth: true
                text: root.connected ? root.connector : "Not connected"
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textMuted
            }
            DeleteButton {
                objectName: "forgetMonitor"
                visible: !root.connected
                label: "Forget"
                confirmLabel: "Forget?"
                onConfirmed: root.edited("default")
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: 4
            Pill {
                objectName: "sameTimes"
                label: "Same as all monitors"
                picked: !root._own
                fontSize: Theme.fontSizeBody
                size: "m"
                opacity: picked && root.dimmed ? 0.5 : 1
                onClicked: if (root._own) root.edited("default")
            }
            Pill {
                objectName: "ownTimes"
                label: "Own times"
                picked: root._own
                fontSize: Theme.fontSizeBody
                size: "m"
                opacity: picked && root.dimmed ? 0.5 : 1
                onClicked: if (!root._own) root.edited(Object.assign({}, root.defaults))
            }
        }

        Reveal {
            open: !root._own
            Text {
                Layout.fillWidth: true
                text: root._defaultLine()
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textMuted
            }
        }

        Reveal {
            open: root._own
            spacing: 2
            Stage {
                label: "Screensaver"
                on: root.own?.screensaverEnabled === true
                value: root.own?.screensaverTimeout ?? 300
                dimmed: root.dimmed
                onSwitched: root._with("screensaverEnabled", !root.own.screensaverEnabled)
                onPicked: value => root._with("screensaverTimeout", value)
            }
            Stage {
                label: "Turn off"
                hint: root.canPowerOff ? "" : "Not supported here: the screensaver instead"
                on: root.own?.screenOffEnabled === true
                value: root.own?.screenOffTimeout ?? 600
                dimmed: root.dimmed
                onSwitched: root._with("screenOffEnabled", !root.own.screenOffEnabled)
                onPicked: value => root._with("screenOffTimeout", value)
            }
        }
    }
}
