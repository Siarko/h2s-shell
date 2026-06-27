import QtQuick
import qs.components
import qs.singletons

BarWidget {
    property var popup: null
    property string widgetType: "power"

    readonly property string _popupMode: {
        var data = JSON.parse(Config.widgetProfiles || "{}")
        return data["power"]?.["_popupMode"] ?? "click"
    }

    active: popup?.active && popup?.contentType === "power"
    onClicked: {
        if (_popupMode !== "click") return
        if (popup?.active && popup?.contentType === "power") popup.close()
        else popup.open(this, false, "power")
    }
    onHover: state => {
        if (_popupMode !== "hover") return
        if (state) popup.open(this, false, "power")
    }

    Text {
        text: "⏻"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeTitle
        color: Theme.textPrimary
        anchors.centerIn: parent
    }
}
