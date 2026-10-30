import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.singletons
import qs.singletons.network

// Network management popup: WiFi toggle, connection status, speed, network list
Item {
    id: root

    // The most height the popup lets this panel take (Popup.availableContentHeight); the
    // network list is cut to fit it. Unlimited until the popup sets it.
    property real availableHeight: Infinity

    // The network row that is open, by SSID; the passwords typed, by SSID; whether the
    // open row shows its password (see the network delegate)
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

    function signalBars(signal) {
        if (signal >= 75) return "▰▰▰▰"
        if (signal >= 50) return "▰▰▰▱"
        if (signal >= 25) return "▰▰▱▱"
        return "▰▱▱▱"
    }

    function signalColor(signal) {
        if (signal >= 75) return Theme.accent
        if (signal >= 50) return Theme.warning
        if (signal >= 25) return Theme.textMuted
        return Theme.textDisabled
    }

    Column {
        id: col
        width: parent.width
        spacing: 6

        // ---- VPN section ----
        Column {
            visible: VpnManager.vpnConnections.length > 0
            width: parent.width
            spacing: 4

            RowLayout {
                width: parent.width
                spacing: 8

                Text {
                    text: (VpnManager.activeVpn === "" || VpnManager.activeVpnType === "wireguard") ? "󰒃" : "󰌾"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeTitle
                    color: VpnManager.activeVpn !== "" ? Theme.accent : Theme.textDisabled
                }

                Text {
                    text: "VPN"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSection
                    color: Theme.textPrimary
                    Layout.fillWidth: true
                }

                Text {
                    text: VpnManager.activeVpn !== "" ? VpnManager.activeVpn : "Off"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: VpnManager.activeVpn !== "" ? Theme.accent : Theme.textDisabled
                    elide: Text.ElideRight
                    Layout.maximumWidth: 120
                }
            }

            Repeater {
                // ScriptModel diffs old vs. new values so only changed delegates get
                // added/removed — see MusicPanel.qml for why binding a plain live-model
                // array straight to Repeater.model was crashing this app. VpnManager
                // rebuilds vpnConnections as brand-new JS objects on every nmcli poll, so
                // objectProp keys the diff by "name" instead of object identity —
                // otherwise every poll would look like a full remove+insert.
                model: ScriptModel {
                    objectProp: "name"
                    values: VpnManager.vpnConnections
                }

                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    property bool isActive: VpnManager.activeVpn === modelData.name

                    width: col.width
                    height: 36
                    radius: Theme.row.radius
                    color: isActive ? Theme.accentTint : Theme.surface

                    RowLayout {
                        anchors { fill: parent; leftMargin: Theme.row.horizontalPadding; rightMargin: Theme.row.horizontalPadding }
                        spacing: 6

                        Text {
                            text: modelData.type === "wireguard" ? "󰒃" : "󰌾"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            color: isActive ? Theme.accent : Theme.textMuted
                        }

                        Text {
                            text: modelData.name
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            color: isActive ? Theme.accent : Theme.textPrimary
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        SmallButton {
                            label: isActive ? "Disconnect" : "Connect"
                            kind: isActive ? "delete" : "save"
                            onClicked: {
                                if (isActive)
                                    VpnManager.disconnectVpn()
                                else
                                    VpnManager.connectVpn(modelData.name)
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.textDisabled
                opacity: 0.3
            }
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

        LinkSpeedRow {
            visible: EthernetManager.ethernetConnected
            width: parent.width
            rxSpeed: EthernetManager.rxSpeed
            txSpeed: EthernetManager.txSpeed
            rxHistory: EthernetManager.rxHistory
            txHistory: EthernetManager.txHistory
        }

        // Ethernet IP and DNS
        Text {
            visible: EthernetManager.ethernetConnected && IpManager.ethernetAddress !== ""
            width: parent.width
            text: IpManager.ethernetAddress
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            color: Theme.textSecondary
        }
        Text {
            visible: EthernetManager.ethernetConnected && IpManager.ethernetDns !== ""
            width: parent.width
            text: "DNS: " + IpManager.ethernetDns
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXSmall
            color: Theme.textMuted
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

            Text {
                visible: WifiManager.wifiConnected
                text: root.signalBars(WifiManager.wifiSignal)
                font.family: Theme.fontFamily
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

        // ---- WiFi live RX/TX speed ----
        LinkSpeedRow {
            visible: WifiManager.wifiConnected
            width: parent.width
            rxSpeed: WifiManager.rxSpeed
            txSpeed: WifiManager.txSpeed
            rxHistory: WifiManager.rxHistory
            txHistory: WifiManager.txHistory
        }

        // WiFi IP and DNS
        Text {
            visible: WifiManager.wifiConnected && IpManager.wifiAddress !== ""
            width: parent.width
            text: IpManager.wifiAddress
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            color: Theme.textSecondary
        }
        Text {
            visible: WifiManager.wifiConnected && IpManager.wifiDns !== ""
            width: parent.width
            text: "DNS: " + IpManager.wifiDns
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXSmall
            color: Theme.textMuted
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
                // Same reasoning as the VPN Repeater above: keyed by "ssid" since
                // WifiManager also rebuilds wifiNetworks fresh on every scan poll.
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

                delegate: Rectangle {
                    id: networkDelegate
                    required property var modelData
                    required property int index
                    // The open row and its password belong to the network, kept by the
                    // panel under its SSID: a delegate is reused for another network when
                    // the list is rebuilt (each scan, a connection), and state kept here
                    // moved to whichever network took its place
                    readonly property string ssid: modelData.ssid
                    readonly property bool expanded: root._expandedSsid === ssid
                    readonly property string passwordText: root._passwords[ssid] ?? ""
                    readonly property bool _showPassword: expanded && root._showPassword
                    // A delegate now showing another network shows that network's password
                    onSsidChanged: if (pwInput.text !== passwordText) pwInput.text = passwordText
                    readonly property bool isSaved: WifiManager.savedSsids.includes(modelData.ssid)
                    readonly property bool needsPassword: {
                        var sec = modelData.security
                        return sec !== "--" && sec !== "" && !isSaved
                    }

                    width: networkList.width
                    // The info row, and with it the action row when open: as tall as they are
                    height: expanded ? _networkColumn.implicitHeight : _infoRow.height
                    radius: Theme.row.radius
                    color: modelData.inUse ? Theme.accentTint : Theme.surface
                    clip: true

                    Behavior on height {
                        NumberAnimation { duration: Theme.duration("expand"); easing: Theme.curve("expand") }
                    }

                    Column {
                        id: _networkColumn
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            leftMargin: Theme.row.horizontalPadding
                            rightMargin: Theme.row.horizontalPadding
                        }
                        spacing: 4

                        // Main info row — always click to expand
                        Item {
                            id: _infoRow
                            width: parent.width
                            height: Math.max(36, _infoContent.implicitHeight + 8)

                            RowLayout {
                                id: _infoContent
                                anchors.fill: parent
                                spacing: 6

                                Rectangle {
                                    width: 8
                                    height: 8
                                    radius: width / 2
                                    Layout.alignment: Qt.AlignVCenter
                                    color: root.signalColor(networkDelegate.modelData.signal)
                                }

                                Text {
                                    text: networkDelegate.modelData.ssid
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeBodyLarge
                                    color: networkDelegate.modelData.inUse ? Theme.accent : Theme.textPrimary
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    text: root.signalBars(networkDelegate.modelData.signal)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.textSecondary
                                }

                                Text {
                                    visible: networkDelegate.modelData.band !== "" && networkDelegate.modelData.band !== undefined
                                    text: networkDelegate.modelData.band ?? ""
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeXSmall
                                    color: (networkDelegate.modelData.band === "5G") ? Theme.accent : Theme.textMuted
                                }

                                Text {
                                    visible: networkDelegate.modelData.security !== "--" && networkDelegate.modelData.security !== ""
                                    text: networkDelegate.modelData.security !== "--" ? networkDelegate.modelData.security : ""
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeXSmall
                                    color: Theme.textMuted
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root._toggleNetwork(networkDelegate.ssid)
                            }
                        }

                        // Action row (revealed when expanded)
                        Item {
                            width: parent.width
                            height: Math.max(36, _actionContent.implicitHeight + 8)

                            RowLayout {
                                id: _actionContent
                                anchors.fill: parent
                                spacing: 6

                                // Password field — only for unsaved secured networks
                                InputField {
                                    id: pwInput
                                    visible: networkDelegate.needsPassword
                                    Layout.fillWidth: true
                                    fieldColor: Theme.popupBackground
                                    outlined: true
                                    placeholder: "Password"
                                    password: true
                                    // Shown or not per network, kept by the panel (see the delegate)
                                    ownsReveal: false
                                    revealed: networkDelegate._showPassword
                                    onRevealToggled: root._showPassword = !root._showPassword
                                    onTextEdited: root._setPassword(networkDelegate.ssid, text)
                                }

                                // Spacer for saved/open networks (no password field)
                                Item {
                                    visible: !networkDelegate.needsPassword
                                    Layout.fillWidth: true
                                }

                                // Error label for wrong password
                                Text {
                                    visible: WifiManager.connectFailed && WifiManager.failedSsid === networkDelegate.modelData.ssid
                                    text: "Wrong password"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeBody
                                    color: Theme.warning
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                // Connect / Cancel button
                                SmallButton {
                                    visible: !networkDelegate.modelData.inUse
                                    readonly property bool _busy: WifiManager.connecting && WifiManager.connectingTo === networkDelegate.modelData.ssid
                                    label: _busy ? "Cancel" : "Connect"
                                    kind: _busy ? "cancel" : "save"
                                    onClicked: {
                                        if (_busy)
                                            WifiManager.cancelConnect()
                                        else
                                            WifiManager.connectToWifi(
                                                networkDelegate.modelData.ssid,
                                                networkDelegate.needsPassword ? networkDelegate.passwordText : ""
                                            )
                                    }
                                }

                                // Forget button — only for saved networks
                                // Asks first, like every delete (DeleteButton)
                                DeleteButton {
                                    visible: networkDelegate.isSaved
                                    label: "Forget"
                                    confirmLabel: "Forget?"
                                    fontSize: Theme.fontSizeBody
                                    cancelTip: "Keep the network"
                                    onConfirmed: WifiManager.forgetNetwork(networkDelegate.modelData.ssid)
                                }
                            }
                        }
                    }
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

            // Hidden network section
            Rectangle {
                id: _hiddenRow
                property bool expanded: false
                property string ssidText: ""
                property string passwordText: ""

                width: parent.width
                // The header, and with it the fields when open: as tall as they are (with a
                // little room below)
                height: expanded ? _hiddenColumn.implicitHeight + 6 : _hiddenHeader.height
                radius: Theme.row.radius
                color: "transparent"
                clip: true

                Behavior on height { NumberAnimation { duration: Theme.duration("expand"); easing: Theme.curve("expand") } }

                Column {
                    id: _hiddenColumn
                    width: parent.width
                    spacing: 4

                    // Header row
                    Item {
                        id: _hiddenHeader
                        width: parent.width
                        height: Math.max(30, _hiddenHeaderContent.implicitHeight + 6)

                        RowLayout {
                            id: _hiddenHeaderContent
                            anchors.fill: parent
                            spacing: 6

                            Text {
                                text: "󰀆"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody
                                color: Theme.textMuted
                            }

                            Text {
                                text: "Connect to hidden network"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody
                                color: Theme.textSecondary
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            Text {
                                text: _hiddenRow.expanded ? "󰅃" : "󰅀"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody
                                color: Theme.textMuted
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: _hiddenRow.expanded = !_hiddenRow.expanded
                        }
                    }

                    // SSID input
                    InputField {
                        width: parent.width
                        fieldColor: Theme.popupBackground
                        outlined: true
                        placeholder: "Network name (SSID)"
                        onTextEdited: _hiddenRow.ssidText = text
                    }

                    // Password + Connect row
                    RowLayout {
                        width: parent.width
                        spacing: 6

                        InputField {
                            Layout.fillWidth: true
                            fieldColor: Theme.popupBackground
                            outlined: true
                            placeholder: "Password (optional)"
                            password: true
                            onTextEdited: _hiddenRow.passwordText = text
                        }

                        SmallButton {
                            label: "Connect"
                            kind: "save"
                            available: _hiddenRow.ssidText !== ""
                            onClicked: WifiManager.connectToHiddenWifi(_hiddenRow.ssidText, _hiddenRow.passwordText)
                        }
                    }
                }
            }
        }
    }
}
