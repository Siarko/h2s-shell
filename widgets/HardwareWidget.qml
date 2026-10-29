import QtQuick
import qs.components
import qs.singletons

PopupWidget {
    property string preset: ""
    widgetType: "hardware"

    // The capsule — which sources and their labels — comes from the widget's preset
    readonly property var _preset: preset !== "" ? (JSON.parse(Config.widgetPresets || "{}")["hardware"]?.[preset] ?? {}) : ({})
    readonly property var _capsuleKeys: _preset.capsule?.length > 0 ? _preset.capsule : ["cpu"]
    readonly property var _customLabels: _preset.capsuleLabels ?? {}

    readonly property string _capsuleText: {
        var parts = []
        for (var i = 0; i < _capsuleKeys.length; i++) {
            var src = Hardware.sourceForId(_capsuleKeys[i])
            if (src && src.available) {
                var label = Hardware.displayLabel(_customLabels, _capsuleKeys[i]).trim()
                parts.push((label !== "" ? label + " " : "") + Math.round(src.value) + src.unit)
            }
        }
        return parts.join("  ") || "—"
    }

    Text {
        anchors.centerIn: parent
        text: _capsuleText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeMedium
        color: Theme.textPrimary
    }
}
