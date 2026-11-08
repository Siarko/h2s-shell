import QtQuick
import Quickshell.Services.UPower
import qs.components
import qs.singletons

// The battery: an icon showing the charge in tens (BatteryRules), charging or not, and the
// percentage beside it. From the widget's preset (WidgetPresets): `percent` — "left",
// "right" or "none"; `thresholds` — [{ value, color }], colouring the icon at or below
// each value (the tightest wins). On a machine without a battery, or before UPower has
// answered, the no-battery icon, dimmed, and no percentage.
//
// It opens nothing, so it is not a button: no hover, no highlight, no pointing hand, and
// a tap goes nowhere (interactive: false).
BarWidget {
    id: root
    widgetType: "battery"
    interactive: false

    property string preset: ""
    readonly property string _percentSide: WidgetPresets.value("battery", preset, "percent") ?? "right"
    readonly property var _thresholds: WidgetPresets.value("battery", preset, "thresholds") ?? []

    readonly property var _device: UPower.displayDevice
    readonly property bool _present: _device.ready && _device.isPresent
    readonly property real _percent: Math.round(_device.percentage * 100)
    // Plugged in: charging, full on the charger, or holding off charging (PendingCharge)
    readonly property bool _charging: _device.state === UPowerDeviceState.Charging
        || _device.state === UPowerDeviceState.FullyCharged
        || _device.state === UPowerDeviceState.PendingCharge

    readonly property color _color: !_present ? Theme.textDisabled
        : BatteryRules.color(_percent, _thresholds, Theme.textPrimary)

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
