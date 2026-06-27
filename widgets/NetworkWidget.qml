import QtQuick
import qs.components
import qs.singletons
import qs.singletons.network

BarWidget {
    property var popup: null
    property string widgetType: "network"

    readonly property string _popupMode: {
        var data = JSON.parse(Config.widgetProfiles || "{}")
        return data["network"]?.["_popupMode"] ?? "click"
    }

    active: popup?.active && popup?.contentType === "network"
    onClicked: {
        if (_popupMode !== "click") return
        if (popup?.active && popup?.contentType === "network") popup.close()
        else popup.open(this, true, "network")
    }
    onHover: state => {
        if (_popupMode !== "hover") return
        if (state) popup.open(this, false, "network")
    }

    Text {
        text: {
            if (NetworkManager.activeDeviceType === "ethernet")
                return "󰈀"
            if (!WifiManager.wifiEnabled)
                return "󰤭"
            if (!NetworkManager.isConnected)
                return "󰤮"
            if (WifiManager.wifiSignal >= 75)
                return "󰤨"
            if (WifiManager.wifiSignal >= 50)
                return "󰤤"
            if (WifiManager.wifiSignal >= 25)
                return "󰤢"
            return "󰤟"
        }
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeHeading
        color: NetworkManager.isConnected ? Theme.textPrimary : Theme.textDim
        anchors.centerIn: parent
    }

    Text {
        visible: VpnManager.activeVpn !== ""
        text: "󰒃"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeXSmall
        color: Theme.sliderAccent
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 2
        anchors.bottomMargin: 2
    }
}
