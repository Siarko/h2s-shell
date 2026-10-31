import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.singletons
import qs.singletons.network
import qs.panels.network

// Network management popup: VPN (VpnSection), Ethernet and Wi-Fi with their details
// (LinkInfo), the network list (WifiNetworkRow) and a hidden network (HiddenNetworkRow)
Item {
    id: root

    // The most height the popup lets this panel take (Popup.availableContentHeight); the
    // network list is cut to fit it. Unlimited until the popup sets it.
    property real availableHeight: Infinity

    // The network row that is open, by SSID; the passwords typed, by SSID; whether the
    // open row shows its password (see WifiNetworkRow)
    property string _expandedSsid: ""
    property var _passwords: ({})
    property bool _showPassword: false

    function _toggleNetwork(ssid) {
        _expandedSsid = _expandedSsid === ssid ? "" : ssid;
        _showPassword = false;
    }

    function _setPassword(ssid, text) {
        const passwords = Object.assign({}, _passwords);
        passwords[ssid] = text;
        _passwords = passwords;
    }

    implicitWidth: Theme.popupWidth("network", 280)
    implicitHeight: col.implicitHeight

    Component.onCompleted: WifiManager.startScan()
    Component.onDestruction: WifiManager.stopScan()

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
                    if (!NetworkManager.wifiConnected) return "󰤮"
                    if (WifiManager.wifiSignal >= 75) return "󰤨"
                    if (WifiManager.wifiSignal >= 50) return "󰤤"
                    if (WifiManager.wifiSignal >= 25) return "󰤢"
                    return "󰤟"
                }
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeTitle
                color: NetworkManager.wifiConnected ? Theme.textPrimary : Theme.textDisabled
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
            visible: WifiManager.wifiEnabled && (WifiManager.wifiConnected || WifiManager.connecting)
            width: parent.width
            spacing: 6

            Text {
                text: WifiManager.wifiConnected
                    ? (WifiManager.wifiNetworks.find(n => n.inUse)?.ssid ?? "")
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

        LinkInfo {
            visible: WifiManager.wifiConnected
            width: parent.width
            speeds: WifiManager
            address: IpManager.wifiAddress
            dns: IpManager.wifiDns
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

        // ---- Available networks section ----
        Column {
            id: _wifiSection
            visible: WifiManager.wifiEnabled
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

            // Network list
            ListView {
                id: networkList
                width: parent.width
                // What the panel has left for it: everything above it, and below it the
                // hidden-network row (the empty-state text shows only with no list)
                height: {
                    const below = _wifiSection.spacing + _hiddenRow.height;
                    const room = root.availableHeight - _wifiSection.y - networkList.y - below;
                    return Math.min(contentHeight, Math.max(80, room));
                }
                clip: true
                // Keyed by "ssid", as WifiManager rebuilds wifiNetworks fresh on every
                // scan (see VpnSection for why)
                model: ScriptModel {
                    objectProp: "ssid"
                    values: WifiManager.wifiNetworks
                }
                spacing: 4
                boundsBehavior: Flickable.StopAtBounds
                // A network found by a scan fades in, and the list makes room for it;
                // rows re-sorted by signal slide to their new place
                add: Transition {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.duration("enter"); easing: Theme.curve("enter") }
                }
                displaced: Transition {
                    NumberAnimation { property: "y"; duration: Theme.duration("move"); easing: Theme.curve("move") }
                    NumberAnimation { property: "opacity"; to: 1; duration: Theme.duration("enter") }
                }
                move: Transition {
                    NumberAnimation { property: "y"; duration: Theme.duration("move"); easing: Theme.curve("move") }
                }

                delegate: WifiNetworkRow {
                    width: networkList.width
                    expanded: root._expandedSsid === ssid
                    passwordText: root._passwords[ssid] ?? ""
                    showPassword: expanded && root._showPassword
                    onToggleRequested: root._toggleNetwork(ssid)
                    onPasswordEdited: text => root._setPassword(ssid, text)
                    onRevealToggled: root._showPassword = !root._showPassword
                }
            }

            // Empty state
            Text {
                visible: WifiManager.wifiNetworks.length === 0
                text: "No networks found"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBodyLarge
                color: Theme.textMuted
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
            }

            HiddenNetworkRow {
                id: _hiddenRow
                width: parent.width
            }
        }
    }
}
