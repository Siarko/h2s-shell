import QtQuick
import QtQuick.Layouts
import qs.singletons

// Network management popup: WiFi toggle, connection status, speed, network list
Item {
    id: root
    implicitWidth: 280
    implicitHeight: col.implicitHeight

    Component.onDestruction: NetworkManager.stopScan()

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

        // ---- Ethernet section (always at the top) ----
        RowLayout {
            visible: NetworkManager.activeDeviceType === "ethernet"
            width: parent.width
            spacing: 6

            Text {
                text: "󰈀"
                font.family: Theme.fontFamily
                font.pixelSize: 20
                color: Theme.sliderAccent
            }

            Text {
                text: NetworkManager.activeConnection || "Ethernet"
                font.family: Theme.fontFamily
                font.pixelSize: 13
                color: Theme.textPrimary
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Text {
                text: "Connected"
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: Theme.sliderAccent
            }
        }

        RowLayout {
            visible: NetworkManager.activeDeviceType === "ethernet"
            width: parent.width

            Text {
                text: "↓ " + NetworkManager.formatSpeed(NetworkManager.rxSpeed)
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Theme.textSecondary
                Layout.fillWidth: true
            }

            Text {
                text: "↑ " + NetworkManager.formatSpeed(NetworkManager.txSpeed)
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Theme.textSecondary
            }
        }

        Rectangle {
            visible: NetworkManager.activeDeviceType === "ethernet"
            width: parent.width
            height: 28
            radius: 6
            color: ethDisconnectArea.containsMouse ? "#c0392b" : Theme.cellDefault

            Text {
                anchors.centerIn: parent
                text: "Disconnect"
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Theme.textPrimary
            }

            MouseArea {
                id: ethDisconnectArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: NetworkManager.disconnect()
            }
        }

        // Divider below ethernet section
        Rectangle {
            visible: NetworkManager.activeDeviceType === "ethernet"
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
                    if (!NetworkManager.wifiEnabled) return "󰤭"
                    if (!NetworkManager.isConnected) return "󰤮"
                    if (NetworkManager.wifiSignal >= 75) return "󰤨"
                    if (NetworkManager.wifiSignal >= 50) return "󰤤"
                    if (NetworkManager.wifiSignal >= 25) return "󰤢"
                    return "󰤟"
                }
                font.family: Theme.fontFamily
                font.pixelSize: 20
                color: (NetworkManager.activeDeviceType === "wifi" && NetworkManager.isConnected) ? Theme.textPrimary : Theme.textDim
            }

            Text {
                text: "WiFi"
                font.family: Theme.fontFamily
                font.pixelSize: 15
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
                    color: NetworkManager.wifiEnabled ? Theme.sliderAccent : Theme.textDim

                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }

                    Rectangle {
                        width: 20
                        height: 20
                        radius: 10
                        color: "white"
                        anchors.verticalCenter: parent.verticalCenter
                        x: NetworkManager.wifiEnabled ? parent.width - width - 2 : 2

                        Behavior on x {
                            NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: NetworkManager.toggleWifi()
                }
            }
        }

        // ---- WiFi connection info row ----
        RowLayout {
            visible: NetworkManager.activeDeviceType === "wifi" && NetworkManager.isConnected
            width: parent.width
            spacing: 6

            Text {
                text: NetworkManager.activeConnection
                font.family: Theme.fontFamily
                font.pixelSize: 13
                color: Theme.textPrimary
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Text {
                text: root.signalBars(NetworkManager.wifiSignal)
                font.family: Theme.fontFamily
                font.pixelSize: 13
                color: Theme.sliderAccent
            }

            Text {
                text: NetworkManager.wifiSignal + "%"
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: Theme.textSecondary
            }
        }

        // ---- WiFi live RX/TX speed ----
        RowLayout {
            visible: NetworkManager.activeDeviceType === "wifi" && NetworkManager.isConnected
            width: parent.width

            Text {
                text: "↓ " + NetworkManager.formatSpeed(NetworkManager.rxSpeed)
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Theme.textSecondary
                Layout.fillWidth: true
            }

            Text {
                text: "↑ " + NetworkManager.formatSpeed(NetworkManager.txSpeed)
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Theme.textSecondary
            }
        }

        // ---- WiFi disconnect button ----
        Rectangle {
            visible: NetworkManager.activeDeviceType === "wifi" && NetworkManager.isConnected
            width: parent.width
            height: 28
            radius: 6
            color: disconnectArea.containsMouse ? "#c0392b" : Theme.cellDefault

            Text {
                anchors.centerIn: parent
                text: "Disconnect"
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Theme.textPrimary
            }

            MouseArea {
                id: disconnectArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: NetworkManager.disconnect()
            }
        }

        // ---- Divider above available networks ----
        Rectangle {
            visible: NetworkManager.wifiEnabled
            width: parent.width
            height: 1
            color: Theme.textDim
            opacity: 0.3
        }

        // ---- Available networks section ----
        Column {
            visible: NetworkManager.wifiEnabled
            width: parent.width
            spacing: 4

            // Section header + scan toggle button
            RowLayout {
                width: parent.width
                spacing: 6

                Text {
                    text: "Available Networks"
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    color: Theme.textSecondary
                    Layout.fillWidth: true
                }

                // Status indicator while scan loop is active
                Text {
                    visible: NetworkManager.scanning
                    text: NetworkManager.scanInProgress ? "Scanning…" : "next scan…"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.sliderAccent
                }

                Rectangle {
                    implicitWidth: rescanLabel.implicitWidth + 14
                    implicitHeight: 22
                    radius: 4
                    color: rescanArea.containsMouse ? Theme.buttonHover : (NetworkManager.scanning ? Theme.sliderAccent : Theme.cellDefault)

                    Text {
                        id: rescanLabel
                        text: NetworkManager.scanning ? "Stop" : "Scan"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: Theme.textPrimary
                        anchors.centerIn: parent
                    }

                    MouseArea {
                        id: rescanArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (NetworkManager.scanning)
                                NetworkManager.stopScan()
                            else
                                NetworkManager.startScan()
                        }
                    }
                }
            }

            // Network list
            Repeater {
                model: NetworkManager.wifiNetworks

                delegate: Rectangle {
                    id: networkDelegate
                    required property var modelData
                    required property int index
                    property bool expanded: false
                    property string passwordText: ""

                    width: col.width
                    // 36px for main row; +4 spacing +36px for password row when expanded
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

                        // Main info row
                        Item {
                            width: parent.width
                            height: 36

                            RowLayout {
                                anchors.fill: parent
                                spacing: 6

                                // Signal strength color dot
                                Rectangle {
                                    width: 8
                                    height: 8
                                    radius: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: root.signalColor(networkDelegate.modelData.signal)
                                }

                                Text {
                                    text: networkDelegate.modelData.ssid
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    color: networkDelegate.modelData.inUse ? Theme.sliderAccent : Theme.textPrimary
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    text: root.signalBars(networkDelegate.modelData.signal)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: Theme.textSecondary
                                }

                                Text {
                                    visible: networkDelegate.modelData.security !== "--" && networkDelegate.modelData.security !== ""
                                    text: networkDelegate.modelData.security !== "--" ? networkDelegate.modelData.security : ""
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    color: Theme.textTertiary
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (networkDelegate.modelData.inUse) return
                                    var sec = networkDelegate.modelData.security
                                    if (sec === "--" || sec === "") {
                                        NetworkManager.connectToWifi(networkDelegate.modelData.ssid, "")
                                    } else {
                                        networkDelegate.expanded = !networkDelegate.expanded
                                    }
                                }
                            }
                        }

                        // Password row (revealed when expanded)
                        Item {
                            width: parent.width
                            height: 36

                            RowLayout {
                                anchors.fill: parent
                                spacing: 6

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 26
                                    radius: 6
                                    color: Theme.popupBackground
                                    border.color: Theme.textDim
                                    border.width: 1

                                    Text {
                                        anchors {
                                            left: parent.left
                                            right: parent.right
                                            leftMargin: 8
                                            rightMargin: 8
                                            verticalCenter: parent.verticalCenter
                                        }
                                        text: "Password"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        color: Theme.textDim
                                        visible: pwInput.text === ""
                                    }

                                    TextInput {
                                        id: pwInput
                                        anchors {
                                            fill: parent
                                            leftMargin: 8
                                            rightMargin: 8
                                        }
                                        echoMode: TextInput.Password
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        color: Theme.textPrimary
                                        verticalAlignment: TextInput.AlignVCenter
                                        clip: true
                                        onTextEdited: networkDelegate.passwordText = text
                                    }
                                }

                                Rectangle {
                                    implicitWidth: connectBtnLabel.implicitWidth + 14
                                    implicitHeight: 26
                                    radius: 6
                                    color: connectBtnArea.containsMouse ? Theme.sliderAccentHover : Theme.sliderAccent

                                    Text {
                                        id: connectBtnLabel
                                        text: "Connect"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        color: Theme.textPrimary
                                        anchors.centerIn: parent
                                    }

                                    MouseArea {
                                        id: connectBtnArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: NetworkManager.connectToWifi(networkDelegate.modelData.ssid, networkDelegate.passwordText)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Empty state
            Text {
                visible: NetworkManager.wifiNetworks.length === 0
                text: "No networks found"
                font.family: Theme.fontFamily
                font.pixelSize: 13
                color: Theme.textTertiary
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
