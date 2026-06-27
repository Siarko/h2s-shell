import QtQuick
import qs.components
import qs.singletons

BarWidget {
    property var popup: null
    property string profile: ""
    property string widgetType: "hardware"

    readonly property string _popupMode: {
        var data = JSON.parse(Config.widgetProfiles || "{}")
        return data["hardware"]?.["_popupMode"] ?? "click"
    }

    active: popup?.active && popup?.contentType === "hardware"
    onClicked: {
        if (_popupMode !== "click") return
        if (popup?.active && popup?.contentType === "hardware") popup.close()
        else popup.open(this, true, "hardware")
    }
    onHover: state => {
        if (_popupMode !== "hover") return
        if (state) popup.open(this, false, "hardware")
    }

    readonly property var _capsuleKeys: {
        if (profile !== "") {
            var data = JSON.parse(Config.widgetProfiles || "{}")
            var keys = data["hardware"]?.[profile]?.capsule
            if (keys && keys.length > 0) return keys
        }
        return ["cpu"]
    }

    readonly property var _customLabels: {
        var data = JSON.parse(Config.widgetProfiles || "{}")
        return data["hardware"]?.["_capsuleLabels"] ?? {}
    }

    readonly property string _capsuleText: {
        var parts = []
        for (var i = 0; i < _capsuleKeys.length; i++) {
            var src = Hardware.sourceForId(_capsuleKeys[i])
            if (src && src.available) {
                var label = _customLabels[src.sourceId] || src.label
                parts.push(label + " " + Math.round(src.value) + src.unit)
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
