import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import qs.components
import qs.panels.battery
import qs.singletons

// The battery popup: the charge and what it is doing, the system power profile with an
// override (docs/plans/battery-popup.md, stage 1), and the history as UPower records it
// (stage 2). The override lasts until the shell's
// profiles next want another power profile — the rule Profiles keeps — and the popup says
// which profile that is.
Item {
    id: root
    // The charge, profile and history on the left; use per app beside them, as the calendar
    // puts its two columns — only with a battery
    readonly property real _scale: Theme.popupWidth("battery", 320) / 320
    readonly property int _leftWidth: Math.round(320 * _scale)
    readonly property int _rightWidth: Math.round(260 * _scale)
    readonly property int _gap: 14
    readonly property bool _showUsage: _present
    implicitWidth: _leftWidth + (_showUsage ? 2 * _gap + 1 + _rightWidth : 0)
    implicitHeight: Math.max(_col.implicitHeight, _showUsage ? _usage.implicitHeight : 0)

    readonly property var _device: UPower.displayDevice
    readonly property bool _present: _device.ready && _device.isPresent
    readonly property real _percent: Math.round(_device.percentage * 100)
    readonly property bool _charging: _device.state === UPowerDeviceState.Charging
        || _device.state === UPowerDeviceState.FullyCharged
        || _device.state === UPowerDeviceState.PendingCharge

    readonly property var _spans: [
        { value: 6 * 3600, label: "6 h" },
        { value: 24 * 3600, label: "24 h" },
        { value: 7 * 24 * 3600, label: "7 d" }
    ]

    // The history, fetched while the popup is open: at once, then every minute
    Component.onCompleted: BatteryHistory.refresh()
    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: BatteryHistory.refresh()
    }

    readonly property var _profiles: [
        { value: "power-saver", label: "Power saver" },
        { value: "balanced", label: "Balanced" },
        { value: "performance", label: "Performance" }
    ].filter(profile => profile.value !== "performance" || PowerProfiles.hasPerformanceProfile)

    function _label(name) {
        return _profiles.find(profile => profile.value === name)?.label ?? name;
    }

    // "4 h 18 min", "35 min"
    function _duration(seconds) {
        const minutes = Math.round(seconds / 60);
        const hours = Math.floor(minutes / 60);
        return hours > 0 ? hours + " h " + (minutes % 60) + " min" : minutes + " min";
    }

    readonly property string _stateText: {
        if (!_present)
            return "No battery";
        switch (_device.state) {
        case UPowerDeviceState.FullyCharged:
            return "Fully charged";
        case UPowerDeviceState.Charging:
            return _device.timeToFull > 0 ? "Charging · full in " + _duration(_device.timeToFull) : "Charging";
        case UPowerDeviceState.PendingCharge:
            return "Plugged in, not charging";
        case UPowerDeviceState.Discharging:
            return _device.timeToEmpty > 0 ? "On battery · " + _duration(_device.timeToEmpty) + " left" : "On battery";
        }
        return "";
    }

    // Who set the power profile, or that it is overridden and who will set it back
    readonly property string _profileNote: {
        const wanted = Profiles.wantedPowerProfile;
        const by = Profiles.setBy("system.powerProfile");
        if (wanted === "unchanged" || wanted === "")
            return "No profile sets it: it stays as chosen.";
        if (wanted === Profiles.currentPowerProfile)
            return by !== "" && by !== "global" ? "Set by the profile “" + by + "”." : "Set by the profiles.";
        return "Overridden. " + (by !== "" && by !== "global" ? "The profile “" + by + "”" : "The profiles")
            + " will set " + _label(wanted) + " again at its next change.";
    }

    Rectangle {
        visible: root._showUsage
        x: root._leftWidth + root._gap
        width: 1
        height: root.height
        color: Theme.textDisabled
        opacity: 0.3
    }

    // A stretch picked on the history graph narrows the use per app to it (seconds; NaN:
    // since the full charge)
    property real _rangeFrom: NaN
    property real _rangeTo: NaN

    EnergyUsageList {
        id: _usage
        visible: root._showUsage
        rangeFrom: root._rangeFrom
        rangeTo: root._rangeTo
        onRangeCleared: {
            root._rangeFrom = NaN;
            root._rangeTo = NaN;
        }
        x: root._leftWidth + 2 * root._gap + 1
        width: root._rightWidth
        height: root.height
    }

    Column {
        id: _col
        width: root._leftWidth
        spacing: 12

        // The charge and what it is doing
        RowLayout {
            width: parent.width
            spacing: 10

            Text {
                text: BatteryRules.icon(root._present, root._percent, root._charging)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeDisplay
                color: root._present ? Theme.textPrimary : Theme.textDisabled
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    visible: root._present
                    text: root._percent + "%"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeHeading
                    font.bold: true
                    color: Theme.textPrimary
                }
                Text {
                    Layout.fillWidth: true
                    text: root._stateText
                    wrapMode: Text.WordWrap
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textSecondary
                }
            }

            // What the laptop draws now, while it runs on the battery
            Text {
                Layout.alignment: Qt.AlignTop
                visible: root._present && root._device.state === UPowerDeviceState.Discharging && root._device.changeRate > 0
                text: root._device.changeRate.toFixed(1) + " W"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textSecondary
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.textDisabled
            opacity: 0.3
        }

        // The system power profile
        Text {
            text: "Power profile"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            font.bold: true
            color: Theme.textPrimary
        }

        Flow {
            width: parent.width
            spacing: 6

            Repeater {
                // ScriptModel, never the bare array (CLAUDE.md)
                model: ScriptModel { values: root._profiles }

                Pill {
                    required property var modelData
                    label: modelData.label
                    picked: modelData.value === Profiles.currentPowerProfile
                    fontSize: Theme.fontSizeBody
                    minimumHeight: 30
                    onClicked: Profiles.setPowerProfile(modelData.value)
                }
            }
        }

        Text {
            width: parent.width
            text: root._profileNote
            wrapMode: Text.WordWrap
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Profiles.wantedPowerProfile !== "unchanged" && Profiles.wantedPowerProfile !== Profiles.currentPowerProfile
                ? Theme.warning : Theme.textMuted
        }

        // The history
        Rectangle {
            visible: BatteryHistory.available
            width: parent.width
            height: 1
            color: Theme.textDisabled
            opacity: 0.3
        }

        RowLayout {
            visible: BatteryHistory.available
            width: parent.width
            spacing: 6

            Text {
                Layout.fillWidth: true
                text: "History"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                font.bold: true
                color: Theme.textPrimary
            }

            Repeater {
                model: ScriptModel { values: root._spans }

                Pill {
                    required property var modelData
                    label: modelData.label
                    picked: modelData.value === BatteryHistory.span
                    onClicked: BatteryHistory.span = modelData.value
                }
            }
        }

        BatteryHistoryChart {
            visible: BatteryHistory.available
            width: parent.width
            charge: BatteryHistory.charge
            rate: BatteryHistory.rate
            span: BatteryHistory.span
            active: visible
            selectionFrom: root._rangeFrom
            selectionTo: root._rangeTo
            onRangePicked: (from, to) => {
                root._rangeFrom = from;
                root._rangeTo = to;
            }
            onRangeCleared: {
                root._rangeFrom = NaN;
                root._rangeTo = NaN;
            }
        }

        // What the shading means; wrapped within the column, not run into the next
        RowLayout {
            visible: BatteryHistory.available
            width: parent.width
            spacing: 6

            Rectangle {
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 3
                implicitWidth: 10
                implicitHeight: 10
                radius: 2
                color: Qt.alpha(Theme.warning, 0.35)
            }
            Text {
                Layout.fillWidth: true
                text: "on the charger · beneath: power drawn · drag across to pick a stretch"
                wrapMode: Text.WordWrap
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textMuted
            }
        }
    }
}
