import QtQuick
import qs.components
import qs.singletons
import qs.singletons.network

PopupWidget {
    widgetType: "network"

    // One icon per link, each coloured by its own state: accent = carrying
    // traffic, white = powered on but not connected, dim = off/unavailable.
    Row {
        anchors.centerIn: parent
        spacing: 9

        // Ethernet — hidden when the machine has no managed port at all
        Text {
            visible: NetworkManager.ethernetDevice !== ""
            text: "󰈀"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeHeading
            // "unavailable" means the interface is up but has no carrier, i.e.
            // the cable is out — dim rather than white, since there is nothing
            // to connect to.
            color: NetworkManager.ethernetConnected
                ? Theme.sliderAccent
                : NetworkManager.ethernetState === "unavailable"
                    ? Theme.textDim
                    : Theme.textPrimary
            anchors.verticalCenter: parent.verticalCenter
        }

        // WiFi — hidden outright while the radio is off, so the bar only ever
        // shows a wifi glyph that stands for a usable adapter
        Text {
            visible: NetworkManager.wifiAvailable && WifiManager.wifiEnabled
            // Bars report signal strength once the link is up; disconnected
            // keeps the plain full glyph and lets the colour say the rest,
            // the same way the ethernet icon works.
            text: {
                if (!NetworkManager.wifiConnected)
                    return "󰤨"
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
            color: NetworkManager.wifiConnected ? Theme.sliderAccent : Theme.textPrimary
            anchors.verticalCenter: parent.verticalCenter
        }

        // VPN — shown only while a tunnel is actually up
        Text {
            visible: VpnManager.activeVpn !== ""
            text: VpnManager.activeVpnType === "wireguard" ? "󰒃" : "󰌾"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeHeading
            color: Theme.sliderAccent
            anchors.verticalCenter: parent.verticalCenter
        }

        // Placeholder so the cell is never empty — before the first nmcli poll
        // returns, and on a machine where no managed device turns up at all
        Text {
            visible: NetworkManager.ethernetDevice === ""
                     && !(NetworkManager.wifiAvailable && WifiManager.wifiEnabled)
            text: "󰤭"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeHeading
            color: Theme.textDim
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
