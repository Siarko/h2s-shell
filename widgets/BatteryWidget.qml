import QtQuick
import Quickshell.Services.UPower
import qs.components
import qs.singletons

// The battery: an icon showing the charge in tens (BatteryRules), charging or not, and the
// percentage beside it. From the widget's preset (WidgetPresets): `percent` — "left",
// "right" or "none"; `thresholds` — [{ value, color }], colouring the icon at or below
// each value (the tightest wins); `chargingColor` — a hex colour while plugged in, or "" for
// the thresholds then too. On a machine without a battery, or before UPower has
// answered, the no-battery icon, dimmed, and no percentage. Opens the battery popup: the
// charge and the power profile (panels/BatteryPanel.qml).
PopupWidget {
    id: root
    widgetType: "battery"

    property string preset: ""
    readonly property string _percentSide: WidgetPresets.value("battery", preset, "percent") ?? "right"
    readonly property var _thresholds: WidgetPresets.value("battery", preset, "thresholds") ?? []
    readonly property string _chargingColor: WidgetPresets.value("battery", preset, "chargingColor") ?? ""

    readonly property var _device: UPower.displayDevice
    readonly property bool _present: _device.ready && _device.isPresent
    readonly property real _percent: Math.round(_device.percentage * 100)
    // Plugged in: charging, full on the charger, or holding off charging (PendingCharge)
    readonly property bool _charging: _device.state === UPowerDeviceState.Charging
        || _device.state === UPowerDeviceState.FullyCharged
        || _device.state === UPowerDeviceState.PendingCharge

    readonly property color _color: !_present ? Theme.textDisabled
        : BatteryRules.widgetColor(_percent, _thresholds, _charging, _chargingColor, Theme.textPrimary)

    BarRow {
        anchors.centerIn: parent
        spacing: 4

        BarText {
            visible: root._present && root._percentSide === "left"
            text: root._percent + "%"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeMedium
            color: root._color
        }

        Text {
            text: BatteryRules.icon(root._present, root._percent, root._charging)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeHeading
            color: root._color
            Behavior on color { ColorAnimation { duration: Theme.duration("state"); easing: Theme.curve("state") } }
        }

        BarText {
            visible: root._present && root._percentSide === "right"
            text: root._percent + "%"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeMedium
            color: root._color
        }
    }
}
