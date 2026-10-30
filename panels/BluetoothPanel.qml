import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import qs.components
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
            color: Theme.textMuted
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
                color: (root.adapter?.enabled ?? false) ? Theme.textPrimary : Theme.textDisabled
            }

            Text {
                text: "Bluetooth"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSection
                color: Theme.textPrimary
                Layout.fillWidth: true
            }

            ToggleSwitch {
                visible: root.adapter !== null
                implicitWidth: 44
                implicitHeight: 24
                offColor: Theme.textDisabled
                checked: root.adapter?.enabled ?? false
                onToggled: {
                    if (root.adapter)
                        root.adapter.enabled = !root.adapter.enabled;
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
                    color: Theme.accent
                }

                SmallButton {
                    label: root.adapter?.discovering ? "Stop" : "Scan"
                    checked: root.adapter?.discovering ?? false
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

            // Device rows, in a column of their own so its transitions touch only them: a
            // device found by a scan fades in, the rows below slide down to make room
            Column {
                width: col.width
                spacing: col.spacing
                add: Transition {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.duration("enter"); easing: Theme.curve("enter") }
                }
                move: Transition {
                    NumberAnimation { property: "y"; duration: Theme.duration("move"); easing: Theme.curve("move") }
                    NumberAnimation { property: "opacity"; to: 1; duration: Theme.duration("enter") }
                }

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
                        // As tall as its two rows need, never less than 52 px
                        height: Math.max(52, _deviceRows.implicitHeight + 12)
                        radius: Theme.row.radius
                        color: Theme.surface

                        Column {
                            id: _deviceRows
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.leftMargin: Theme.row.horizontalPadding
                            anchors.rightMargin: Theme.row.horizontalPadding
                            anchors.topMargin: 6
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
                                    color: modelData.state === BluetoothDeviceState.Connected ? Theme.accent : Theme.textSecondary
                                    Layout.fillWidth: true
                                }

                                // Pair button (only when disconnected and not already pairing)
                                SmallButton {
                                    visible: modelData.state === BluetoothDeviceState.Disconnected && !modelData.pairing && !modelData.paired
                                    label: "Pair"
                                    fontSize: Theme.fontSizeSmall
                                    onClicked: modelData.pair()
                                }

                                // Connect / Disconnect button (hidden while transitioning or pairing)
                                SmallButton {
                                    visible: modelData.state !== BluetoothDeviceState.Connecting && modelData.state !== BluetoothDeviceState.Disconnecting && !modelData.pairing
                                    readonly property bool _connected: modelData.state === BluetoothDeviceState.Connected
                                    label: _connected ? "Disconnect" : "Connect"
                                    kind: _connected ? "delete" : "normal"
                                    fontSize: Theme.fontSizeSmall
                                    onClicked: modelData.connected = !modelData.connected
                                }

                                // Forget button
                                // Forgets the device: asks first, like every delete (DeleteButton)
                                DeleteButton {
                                    label: "✕"
                                    confirmLabel: "Forget?"
                                    cancelTip: "Keep the device"
                                    onConfirmed: modelData.forget()
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
                color: Theme.textMuted
                width: col.width
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
