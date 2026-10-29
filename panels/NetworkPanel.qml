import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import qs.components
import qs.singletons
import qs.singletons.network

// Network management popup: WiFi toggle, connection status, speed, network list
Item {
    id: root
    implicitWidth: 280
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
        if (signal >= 75) return Theme.sliderAccent
        if (signal >= 50) return Theme.textWarning
        if (signal >= 25) return Theme.textTertiary
        return Theme.textDim
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
                    color: VpnManager.activeVpn !== "" ? Theme.sliderAccent : Theme.textDim
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
                    color: VpnManager.activeVpn !== "" ? Theme.sliderAccent : Theme.textDim
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
                    radius: 6
                    color: isActive ? Qt.rgba(0.27, 0.83, 0.48, 0.12) : Theme.cellDefault

                    RowLayout {
                        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                        spacing: 6

                        Text {
                            text: modelData.type === "wireguard" ? "󰒃" : "󰌾"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            color: isActive ? Theme.sliderAccent : Theme.textTertiary
                        }

                        Text {
                            text: modelData.name
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            color: isActive ? Theme.sliderAccent : Theme.textPrimary
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            implicitWidth: vpnBtnLabel.implicitWidth + 14
                            implicitHeight: 24
                            radius: 4
                            color: vpnBtnArea.containsMouse
                                ? (isActive ? "#c0392b" : Theme.sliderAccentHover)
                                : (isActive ? Qt.rgba(0.75, 0.2, 0.2, 0.6) : Theme.sliderAccent)

                            Text {
                                id: vpnBtnLabel
                                text: isActive ? "Disconnect" : "Connect"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody
                                color: Theme.textPrimary
                                anchors.centerIn: parent
                            }

                            MouseArea {
                                id: vpnBtnArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
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
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.textDim
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
                color: EthernetManager.ethernetConnected ? Theme.textPrimary : Theme.textDim
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

            Item {
                width: 44
                height: 24

                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: EthernetManager.ethernetConnected ? Theme.sliderAccent : Theme.textDim

                    Behavior on color { ColorAnimation { duration: 150 } }

                    Rectangle {
                        width: 20
                        height: 20
                        radius: 10
                        color: "white"
                        anchors.verticalCenter: parent.verticalCenter
                        x: EthernetManager.ethernetConnected ? parent.width - width - 2 : 2

                        Behavior on x {
                            NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: EthernetManager.ethernetConnected
                        ? EthernetManager.disconnect()
                        : EthernetManager.connect()
                }
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
            color: Theme.textTertiary
        }

        // Divider below ethernet section
        Rectangle {
            visible: NetworkManager.ethernetDevice !== ""
            width: parent.width
            height: 1
            color: Theme.textDim
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
                color: NetworkManager.wifiConnected ? Theme.textPrimary : Theme.textDim
            }

            Text {
                text: "WiFi"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSection
                color: Theme.textPrimary
                Layout.fillWidth: true
            }

            // WiFi toggle switch (same style as BluetoothPanel)
            Item {
                width: 44
                height: 24

                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: WifiManager.wifiEnabled ? Theme.sliderAccent : Theme.textDim

                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }

                    Rectangle {
                        width: 20
                        height: 20
                        radius: 10
                        color: "white"
                        anchors.verticalCenter: parent.verticalCenter
                        x: WifiManager.wifiEnabled ? parent.width - width - 2 : 2

                        Behavior on x {
                            NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: WifiManager.toggleWifi()
                }
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
                color: Theme.sliderAccent
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
            color: Theme.textTertiary
        }

        // ---- WiFi disconnect button ----
        Rectangle {
            visible: WifiManager.wifiConnected || WifiManager.disconnecting
            width: parent.width
            height: 28
            radius: 6
            color: WifiManager.disconnecting
                ? Theme.cellDefault
                : (disconnectArea.containsMouse ? "#c0392b" : Theme.cellDefault)

            Text {
                anchors.centerIn: parent
                text: WifiManager.disconnecting ? "Disconnecting…" : "Disconnect"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: WifiManager.disconnecting ? Theme.textDim : Theme.textPrimary
            }

            MouseArea {
                id: disconnectArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: WifiManager.disconnecting ? Qt.ArrowCursor : Qt.PointingHandCursor
                onClicked: { if (!WifiManager.disconnecting) WifiManager.disconnect() }
            }
        }

        // ---- Divider above available networks ----
        Rectangle {
            visible: WifiManager.wifiEnabled
            width: parent.width
            height: 1
            color: Theme.textDim
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
                    color: Theme.sliderAccent
                }

                Rectangle {
                    implicitWidth: rescanLabel.implicitWidth + 14
                    implicitHeight: 22
                    radius: 4
                    color: rescanArea.containsMouse ? Theme.buttonHover : (WifiManager.scanning ? Theme.sliderAccent : Theme.cellDefault)

                    Text {
                        id: rescanLabel
                        text: WifiManager.scanning ? "Stop" : "Scan"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        color: Theme.textPrimary
                        anchors.centerIn: parent
                    }

                    MouseArea {
                        id: rescanArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (WifiManager.scanning)
                                WifiManager.stopScan()
                            else
                                WifiManager.startScan()
                        }
                    }
                }
            }

            // Network list
            ListView {
                id: networkList
                width: parent.width
                height: {
                    // Popup content starts at y = topOffset + barHeight from screen top.
                    // Inside popup: paddingTop=10 above panel, paddingBottom=10 below.
                    // Below the list in _wifiSection: _hiddenRow + 8px spacing.
                    var panelTopY = (Profiles.value("bar.layout.topOffset") ?? 0) + (Profiles.value("bar.layout.barHeight") ?? 0)
                    var maxH = Screen.height - panelTopY - 10 - _wifiSection.y - networkList.y - _hiddenRow.height - 8 - 10 - 16
                    return Math.min(contentHeight, Math.max(80, maxH))
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

                delegate: Rectangle {
                    id: networkDelegate
                    required property var modelData
                    required property int index
                    property bool expanded: false
                    property string passwordText: ""
                    property bool _showPassword: false
                    onExpandedChanged: { if (!expanded) _showPassword = false }
                    readonly property bool isSaved: WifiManager.savedSsids.includes(modelData.ssid)
                    readonly property bool needsPassword: {
                        var sec = modelData.security
                        return sec !== "--" && sec !== "" && !isSaved
                    }

                    width: networkList.width
                    height: expanded ? 76 : 36
                    radius: 6
                    color: modelData.inUse ? Qt.rgba(0.27, 0.83, 0.48, 0.12) : Theme.cellDefault
                    clip: true

                    Behavior on height {
                        NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                    }

                    Column {
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            leftMargin: 8
                            rightMargin: 8
                        }
                        spacing: 4

                        // Main info row — always click to expand
                        Item {
                            width: parent.width
                            height: 36

                            RowLayout {
                                anchors.fill: parent
                                spacing: 6

                                Rectangle {
                                    width: 8
                                    height: 8
                                    radius: 4
                                    Layout.alignment: Qt.AlignVCenter
                                    color: root.signalColor(networkDelegate.modelData.signal)
                                }

                                Text {
                                    text: networkDelegate.modelData.ssid
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeBodyLarge
                                    color: networkDelegate.modelData.inUse ? Theme.sliderAccent : Theme.textPrimary
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
                                    color: (networkDelegate.modelData.band === "5G") ? Theme.sliderAccent : Theme.textTertiary
                                }

                                Text {
                                    visible: networkDelegate.modelData.security !== "--" && networkDelegate.modelData.security !== ""
                                    text: networkDelegate.modelData.security !== "--" ? networkDelegate.modelData.security : ""
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeXSmall
                                    color: Theme.textTertiary
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: networkDelegate.expanded = !networkDelegate.expanded
                            }
                        }

                        // Action row (revealed when expanded)
                        Item {
                            width: parent.width
                            height: 36

                            RowLayout {
                                anchors.fill: parent
                                spacing: 6

                                // Password field — only for unsaved secured networks
                                Rectangle {
                                    visible: networkDelegate.needsPassword
                                    Layout.fillWidth: true
                                    height: 26
                                    radius: 6
                                    color: Theme.popupBackground
                                    border.color: Theme.textDim
                                    border.width: 1

                                    Text {
                                        anchors { fill: parent; leftMargin: 8; rightMargin: 28 }
                                        text: "Password"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeBody
                                        color: Theme.textDim
                                        verticalAlignment: Text.AlignVCenter
                                        visible: pwInput.text === ""
                                    }

                                    TextInput {
                                        id: pwInput
                                        anchors { fill: parent; leftMargin: 8; rightMargin: 28 }
                                        echoMode: networkDelegate._showPassword ? TextInput.Normal : TextInput.Password
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeBody
                                        color: Theme.textPrimary
                                        verticalAlignment: TextInput.AlignVCenter
                                        clip: true
                                        onTextEdited: networkDelegate.passwordText = text
                                    }

                                    Text {
                                        anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                                        text: networkDelegate._showPassword ? "󰛐" : "󰛑"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeMedium
                                        color: Theme.textTertiary

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: networkDelegate._showPassword = !networkDelegate._showPassword
                                        }
                                    }
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
                                    color: Theme.textWarning
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                // Connect / Cancel button
                                Rectangle {
                                    visible: !networkDelegate.modelData.inUse
                                    implicitWidth: _connectLabel.implicitWidth + 14
                                    height: 26
                                    radius: 6

                                    readonly property bool _busy: WifiManager.connecting && WifiManager.connectingTo === networkDelegate.modelData.ssid
                                    color: _busy
                                        ? (_connectArea.containsMouse ? "#c0392b" : Theme.cellDefault)
                                        : (_connectArea.containsMouse ? Theme.sliderAccentHover : Theme.sliderAccent)

                                    Text {
                                        id: _connectLabel
                                        text: parent._busy ? "Cancel" : "Connect"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeBody
                                        color: parent._busy ? Theme.textSecondary : Theme.textPrimary
                                        anchors.centerIn: parent
                                    }

                                    MouseArea {
                                        id: _connectArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (parent._busy)
                                                WifiManager.cancelConnect()
                                            else
                                                WifiManager.connectToWifi(
                                                    networkDelegate.modelData.ssid,
                                                    networkDelegate.needsPassword ? networkDelegate.passwordText : ""
                                                )
                                        }
                                    }
                                }

                                // Forget button — only for saved networks
                                Rectangle {
                                    visible: networkDelegate.isSaved
                                    implicitWidth: _forgetLabel.implicitWidth + 14
                                    height: 26
                                    radius: 6
                                    color: _forgetArea.containsMouse ? "#c0392b" : Theme.cellDefault

                                    Text {
                                        id: _forgetLabel
                                        text: "Forget"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeBody
                                        color: _forgetArea.containsMouse ? Theme.textPrimary : Theme.textSecondary
                                        anchors.centerIn: parent
                                    }

                                    MouseArea {
                                        id: _forgetArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: WifiManager.forgetNetwork(networkDelegate.modelData.ssid)
                                    }
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
                color: Theme.textTertiary
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
            }

            // Hidden network section
            Rectangle {
                id: _hiddenRow
                property bool expanded: false
                property string ssidText: ""
                property string passwordText: ""
                property bool _showPassword: false

                width: parent.width
                height: expanded ? 102 : 30
                radius: 6
                color: "transparent"
                clip: true

                Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                Column {
                    width: parent.width
                    spacing: 4

                    // Header row
                    Item {
                        width: parent.width
                        height: 30

                        RowLayout {
                            anchors.fill: parent
                            spacing: 6

                            Text {
                                text: "󰀆"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody
                                color: Theme.textTertiary
                            }

                            Text {
                                text: "Connect to hidden network"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody
                                color: Theme.textSecondary
                                Layout.fillWidth: true
                            }

                            Text {
                                text: _hiddenRow.expanded ? "󰅃" : "󰅀"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody
                                color: Theme.textTertiary
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: _hiddenRow.expanded = !_hiddenRow.expanded
                        }
                    }

                    // SSID input
                    Rectangle {
                        width: parent.width
                        height: 28
                        radius: 6
                        color: Theme.popupBackground
                        border.color: Theme.textDim
                        border.width: 1

                        Text {
                            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                            text: "Network name (SSID)"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            color: Theme.textDim
                            verticalAlignment: Text.AlignVCenter
                            visible: _hiddenRow.ssidText === ""
                        }

                        TextInput {
                            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            color: Theme.textPrimary
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            onTextEdited: _hiddenRow.ssidText = text
                        }
                    }

                    // Password + Connect row
                    RowLayout {
                        width: parent.width
                        spacing: 6

                        Rectangle {
                            Layout.fillWidth: true
                            height: 28
                            radius: 6
                            color: Theme.popupBackground
                            border.color: Theme.textDim
                            border.width: 1

                            Text {
                                anchors { fill: parent; leftMargin: 8; rightMargin: 28 }
                                text: "Password (optional)"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody
                                color: Theme.textDim
                                verticalAlignment: Text.AlignVCenter
                                visible: _hiddenRow.passwordText === ""
                            }

                            TextInput {
                                anchors { fill: parent; leftMargin: 8; rightMargin: 28 }
                                echoMode: _hiddenRow._showPassword ? TextInput.Normal : TextInput.Password
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody
                                color: Theme.textPrimary
                                verticalAlignment: TextInput.AlignVCenter
                                clip: true
                                onTextEdited: _hiddenRow.passwordText = text
                            }

                            Text {
                                anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                                text: _hiddenRow._showPassword ? "󰛐" : "󰛑"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.textTertiary

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: _hiddenRow._showPassword = !_hiddenRow._showPassword
                                }
                            }
                        }

                        Rectangle {
                            implicitWidth: _hiddenConnectLabel.implicitWidth + 14
                            height: 28
                            radius: 6
                            opacity: _hiddenRow.ssidText === "" ? 0.4 : 1.0
                            color: _hiddenArea.containsMouse && _hiddenRow.ssidText !== ""
                                ? Theme.sliderAccentHover : Theme.sliderAccent

                            Text {
                                id: _hiddenConnectLabel
                                text: "Connect"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody
                                color: Theme.textPrimary
                                anchors.centerIn: parent
                            }

                            MouseArea {
                                id: _hiddenArea
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: _hiddenRow.ssidText !== ""
                                cursorShape: _hiddenRow.ssidText !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: WifiManager.connectToHiddenWifi(_hiddenRow.ssidText, _hiddenRow.passwordText)
                            }
                        }
                    }
                }
            }
        }
    }
}
