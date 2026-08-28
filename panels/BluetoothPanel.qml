import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import qs.singletons

// Bluetooth management popup: adapter toggle, device list, scan
Item {
    id: root
    implicitWidth: 280
    implicitHeight: col.implicitHeight

    property var adapter: Bluetooth.defaultAdapter

    // Discovery is started/stopped via bluetoothctl — the only remaining process usage,
    // since Quickshell exposes adapter.discovering as read-only.
    Process {
        id: scanProcess
        command: ["bluetoothctl", "scan", "on"]
        onRunningChanged: {
            if (!running)
                scanTimer.stop();
        }
    }

    Timer {
        id: scanTimer
        interval: 30000
        onTriggered: {
            if (scanProcess.running)
                scanProcess.running = false;
        }
    }

    Column {
        id: col
        width: parent.width
        spacing: 6

        // ---- No adapter ----
        Text {
            visible: !root.adapter
            text: "No Bluetooth adapter found"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBodyLarge
            color: Theme.textTertiary
            width: col.width
            horizontalAlignment: Text.AlignHCenter
        }

        // ---- Header: icon + label + animated power toggle ----
        RowLayout {
            width: parent.width
            spacing: 8

            Text {
                text: (root.adapter?.enabled ?? false) ? "󰂯" : "󰂲"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeTitle
                color: (root.adapter?.enabled ?? false) ? Theme.textPrimary : Theme.textDim
            }

            Text {
                text: "Bluetooth"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSection
                color: Theme.textPrimary
                Layout.fillWidth: true
            }

            Item {
                width: 44
                height: 24
                visible: root.adapter !== null

                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: (root.adapter?.enabled ?? false) ? Theme.sliderAccent : Theme.textDim

                    Behavior on color {
                        ColorAnimation {
                            duration: 150
                        }
                    }

                    Rectangle {
                        width: 20
                        height: 20
                        radius: 10
                        color: "white"
                        anchors.verticalCenter: parent.verticalCenter
                        x: (root.adapter?.enabled ?? false) ? parent.width - width - 2 : 2

                        Behavior on x {
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutQuad
                            }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.adapter)
                            root.adapter.enabled = !root.adapter.enabled;
                    }
                }
            }
        }

        // ---- Device list (only when adapter is powered) ----
        Column {
            visible: root.adapter?.enabled ?? false
            width: parent.width
            spacing: 4

            // Section header + scan controls
            RowLayout {
                width: parent.width
                spacing: 6

                Text {
                    text: "Devices"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textSecondary
                    Layout.fillWidth: true
                }

                Text {
                    visible: root.adapter?.discovering ?? false
                    text: "Scanning…"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.sliderAccent
                }

                Rectangle {
                    implicitWidth: scanLabel.implicitWidth + 14
                    implicitHeight: 22
                    radius: 4
                    color: scanBtnArea.containsMouse ? Theme.buttonHover : Theme.cellDefault

                    Text {
                        id: scanLabel
                        text: root.adapter?.discovering ? "Stop" : "Scan"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        color: Theme.textPrimary
                        anchors.centerIn: parent
                    }

                    MouseArea {
                        id: scanBtnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (scanProcess.running) {
                                scanProcess.running = false;
                            } else {
                                scanTimer.restart();
                                scanProcess.running = true;
                            }
                        }
                    }
                }
            }

            // Device rows
            Repeater {
                // ScriptModel diffs old vs. new values so only changed delegates get
                // added/removed — see MusicPanel.qml for why binding a plain live-model
                // array straight to Repeater.model was crashing this app.
                model: ScriptModel {
                    values: root.adapter?.devices?.values ?? []
                }

                Rectangle {
                    required property var modelData
                    width: col.width
                    height: 52
                    radius: 6
                    color: Theme.cellDefault

                    Column {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 6
                        anchors.topMargin: 6
                        anchors.bottomMargin: 6
                        spacing: 4

                        // Name row
                        RowLayout {
                            width: parent.width
                            spacing: 6

                            Text {
                                text: modelData.name || modelData.deviceName
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBodyLarge
                                color: Theme.textPrimary
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Text {
                                visible: modelData.batteryAvailable
                                text: Math.round(modelData.battery * 100) + "%"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.textSecondary
                            }
                        }

                        // State + action buttons row
                        RowLayout {
                            width: parent.width
                            spacing: 4

                            Text {
                                text: {
                                    if (modelData.pairing)
                                        return "Pairing…";
                                    switch (modelData.state) {
                                    case BluetoothDeviceState.Connected:
                                        return "Connected";
                                    case BluetoothDeviceState.Connecting:
                                        return "Connecting…";
                                    case BluetoothDeviceState.Disconnecting:
                                        return "Disconnecting…";
                                    default:
                                        return "";
                                    }
                                }
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                color: modelData.state === BluetoothDeviceState.Connected ? Theme.sliderAccent : Theme.textSecondary
                                Layout.fillWidth: true
                            }

                            // Pair button (only when disconnected and not already pairing)
                            Rectangle {
                                visible: modelData.state === BluetoothDeviceState.Disconnected && !modelData.pairing && !modelData.paired
                                implicitWidth: pairLabel.implicitWidth + 10
                                implicitHeight: 20
                                radius: 4
                                color: pairArea.containsMouse ? Theme.buttonHover : Theme.cellDefault

                                Text {
                                    id: pairLabel
                                    text: "Pair"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.textPrimary
                                    anchors.centerIn: parent
                                }

                                MouseArea {
                                    id: pairArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: modelData.pair()
                                }
                            }

                            // Connect / Disconnect button (hidden while transitioning or pairing)
                            Rectangle {
                                visible: modelData.state !== BluetoothDeviceState.Connecting && modelData.state !== BluetoothDeviceState.Disconnecting && !modelData.pairing
                                implicitWidth: connLabel.implicitWidth + 10
                                implicitHeight: 20
                                radius: 4
                                color: connArea.containsMouse ? Theme.buttonHover : Theme.cellDefault

                                Text {
                                    id: connLabel
                                    text: modelData.state === BluetoothDeviceState.Connected ? "Disconnect" : "Connect"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.textPrimary
                                    anchors.centerIn: parent
                                }

                                MouseArea {
                                    id: connArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: modelData.connected = !modelData.connected
                                }
                            }

                            // Forget button
                            Rectangle {
                                implicitWidth: 22
                                implicitHeight: 20
                                radius: 4
                                color: forgetArea.containsMouse ? Theme.buttonHover : "transparent"

                                Text {
                                    text: "✕"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.textSecondary
                                    anchors.centerIn: parent
                                }

                                MouseArea {
                                    id: forgetArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: modelData.forget()
                                }
                            }
                        }
                    }
                }
            }

            // Empty state
            Text {
                visible: (root.adapter?.devices?.count ?? 0) === 0
                text: (root.adapter?.discovering ?? false) ? "Scanning for devices…" : "No devices"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBodyLarge
                color: Theme.textTertiary
                width: col.width
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
