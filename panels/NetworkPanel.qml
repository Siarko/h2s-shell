import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.singletons
import qs.singletons.network
import qs.panels.network

// Network management popup: VPN (VpnSection), Ethernet and Wi-Fi with their details
// (LinkInfo), the network list (WifiNetworkRow), a hidden network (HiddenNetworkRow) and
// the saved hotspots to turn on (HotspotRow).
// While the Wi-Fi serves a hotspot it joins no network: the hotspot shows in the network's
// place — its devices, a button to turn it off — and the list gives way to a line saying
// so (the list is the one from before the hotspot, and joining would end it unasked).
Item {
    id: root

    // The most height the popup lets this panel take (Popup.availableContentHeight); the
    // network list is cut to fit it. Unlimited until the popup sets it.
    property real availableHeight: Infinity

    implicitWidth: Theme.popupWidth("network", 280)
    implicitHeight: col.implicitHeight

    Component.onCompleted: {
        WifiManager.holdScan();
        NetworkOverview.holdHotspotClients();
    }
    Component.onDestruction: {
        WifiManager.releaseScan();
        NetworkOverview.releaseHotspotClients();
    }

    Column {
        id: col
        width: parent.width
        spacing: 6

        VpnSection {
            width: parent.width
        }

        // ---- Ethernet section (visible whenever ethernet device is present) ----
        RowLayout {
            visible: NetworkManager.ethernetDevice !== ""
            width: parent.width
            spacing: 8

            Text {
                text: "󰈀"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeTitle
                color: EthernetManager.ethernetConnected ? Theme.textPrimary : Theme.textDisabled
            }

            Text {
                text: EthernetManager.ethernetConnected
                    ? (NetworkManager.ethernetConnection || "Ethernet")
                    : "Ethernet"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSection
                color: Theme.textPrimary
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            ToggleSwitch {
                implicitWidth: 44
                implicitHeight: 24
                offColor: Theme.textDisabled
                checked: EthernetManager.ethernetConnected
                onToggled: EthernetManager.ethernetConnected
                    ? EthernetManager.disconnect()
                    : EthernetManager.connect()
            }
        }

        LinkInfo {
            visible: EthernetManager.ethernetConnected
            width: parent.width
            speeds: EthernetManager
            address: IpManager.ethernetAddress
            dns: IpManager.ethernetDns
        }

        // Divider below ethernet section
        Rectangle {
            visible: NetworkManager.ethernetDevice !== ""
            width: parent.width
            height: 1
            color: Theme.textDisabled
            opacity: 0.3
        }

        // ---- WiFi header: icon + "WiFi" label + toggle (hidden when no adapter) ----
        RowLayout {
            visible: NetworkManager.wifiAvailable
            width: parent.width
            spacing: 8

            Text {
                text: {
                    if (!WifiManager.wifiEnabled) return "󰤭"
                    if (WifiManager.mode === "hotspot") return "󰀃"
                    if (WifiManager.mode !== "connected") return "󰤮"
                    if (WifiManager.wifiSignal >= 75) return "󰤨"
                    if (WifiManager.wifiSignal >= 50) return "󰤤"
                    if (WifiManager.wifiSignal >= 25) return "󰤢"
                    return "󰤟"
                }
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeTitle
                color: WifiManager.mode === "connected" || WifiManager.mode === "hotspot" ? Theme.textPrimary : Theme.textDisabled
            }

            Text {
                text: "WiFi"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSection
                color: Theme.textPrimary
                Layout.fillWidth: true
            }

            // WiFi toggle switch
            ToggleSwitch {
                implicitWidth: 44
                implicitHeight: 24
                offColor: Theme.textDisabled
                checked: WifiManager.wifiEnabled
                onToggled: WifiManager.toggleWifi()
            }
        }

        // ---- WiFi connection info row ----
        RowLayout {
            visible: WifiManager.mode === "connected" || (WifiManager.mode === "disconnected" && WifiManager.connecting)
            width: parent.width
            spacing: 6

            Text {
                text: WifiManager.wifiConnected
                    ? (WifiManager.wifiNetworks.find(network => network.inUse)?.ssid ?? "")
                    : ("Connecting to \"" + WifiManager.connectingTo + "\"…")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBodyLarge
                color: WifiManager.wifiConnected ? Theme.textPrimary : Theme.textSecondary
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            SignalBars {
                visible: WifiManager.wifiConnected
                strength: WifiManager.wifiSignal
                font.pixelSize: Theme.fontSizeBodyLarge
                color: Theme.accent
            }

            Text {
                visible: WifiManager.wifiConnected
                text: WifiManager.wifiSignal + "%"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textSecondary
            }
        }

        // ---- The hotspot in the network's place ----
        RowLayout {
            visible: WifiManager.mode === "hotspot"
            width: parent.width
            spacing: 6

            Text {
                text: "Hotspot \"" + (WifiManager.hotspot?.ssid ?? "") + "\""
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBodyLarge
                color: Theme.textPrimary
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Text {
                readonly property int _count: NetworkOverview.hotspotClients.length
                text: _count + (_count === 1 ? " device" : " devices")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textSecondary
            }
        }

        LinkInfo {
            visible: WifiManager.mode === "connected" || WifiManager.mode === "hotspot"
            width: parent.width
            speeds: WifiManager
            address: IpManager.wifiAddress
            dns: IpManager.wifiDns
        }

        SmallButton {
            visible: WifiManager.mode === "hotspot"
            width: parent.width
            label: "Turn off hotspot"
            kind: "delete"
            available: !NetworkProfiles.connecting
            onClicked: NetworkProfiles.deactivate(WifiManager.hotspot.uuid, "Turning off " + WifiManager.hotspot.ssid)
        }

        // ---- WiFi disconnect button ----
        SmallButton {
            visible: WifiManager.wifiConnected || WifiManager.disconnecting
            width: parent.width
            label: WifiManager.disconnecting ? "Disconnecting…" : "Disconnect"
            kind: "delete"
            available: !WifiManager.disconnecting
            onClicked: WifiManager.disconnect()
        }

        // ---- Divider above available networks ----
        Rectangle {
            visible: WifiManager.wifiEnabled
            width: parent.width
            height: 1
            color: Theme.textDisabled
            opacity: 0.3
        }

        Text {
            visible: WifiManager.mode === "hotspot"
            width: parent.width
            wrapMode: Text.WordWrap
            text: "The Wi-Fi serves the hotspot: turn it off to join a network."
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            color: Theme.textMuted
        }

        // ---- Available networks section ----
        Column {
            id: _wifiSection
            visible: WifiManager.mode === "connected" || WifiManager.mode === "disconnected"
            width: parent.width
            spacing: 4

            // Section header + scan toggle button
            RowLayout {
                width: parent.width
                spacing: 6

                Text {
                    text: "Available Networks"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textSecondary
                    Layout.fillWidth: true
                }

                // Status indicator while scan loop is active
                Text {
                    visible: WifiManager.scanning
                    text: WifiManager.scanInProgress ? "Scanning…" : "next scan…"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.accent
                }

                SmallButton {
                    label: WifiManager.scanning ? "Stop" : "Scan"
                    checked: WifiManager.scanning
                    onClicked: {
                        if (WifiManager.scanning)
                            WifiManager.stopScan()
                        else
                            WifiManager.startScan()
                    }
                }
            }

            // Network list (shared with Settings → System → Network → Wi-Fi), cut to what the
            // panel has left: everything above it, and below it the hidden-network row
            WifiNetworkList {
                id: networkList
                width: parent.width
                maximumHeight: root.availableHeight - _wifiSection.y - networkList.y
                    - (_wifiSection.spacing + _hiddenRow.height) - (_hotspotRow.visible ? _wifiSection.spacing + _hotspotRow.height : 0)
            }

            HiddenNetworkRow {
                id: _hiddenRow
                width: parent.width
            }

            // The saved hotspots, to turn one on (shown when there are some)
            HotspotRow {
                id: _hotspotRow
                width: parent.width
            }
        }
    }
}
