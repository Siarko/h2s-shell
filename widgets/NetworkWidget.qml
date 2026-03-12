import QtQuick
import qs.components
import qs.singletons

BarWidget {
    property var popup: null

    active: popup?.active && popup?.contentType === "network"
    onClicked: {
        if (popup?.active && popup?.contentType === "network")
            popup.close()
        else
            popup.open(this, true, "network")
    }

    Text {
        text: {
            if (NetworkManager.activeDeviceType === "ethernet")
                return "󰈀"
            if (!NetworkManager.wifiEnabled)
                return "󰤭"
            if (!NetworkManager.isConnected)
                return "󰤮"
            if (NetworkManager.wifiSignal >= 75)
                return "󰤨"
            if (NetworkManager.wifiSignal >= 50)
                return "󰤤"
            if (NetworkManager.wifiSignal >= 25)
                return "󰤢"
            return "󰤟"
        }
        font.family: Theme.fontFamily
        font.pixelSize: 18
        color: NetworkManager.isConnected ? Theme.textPrimary : Theme.textDim
        anchors.centerIn: parent
    }
}
