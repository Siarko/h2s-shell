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

            Item {
                width: 44
                height: 24
                visible: root.adapter !== null

                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: (root.adapter?.enabled ?? false) ? Theme.accent : Theme.textDisabled

                    Behavior on color {
                        ColorAnimation {
                            duration: Theme.duration("state")
                            easing: Theme.curve("state")
                        }
                    }

                    Rectangle {
                        width: 20
                        height: 20
                        radius: 10
                        color: Theme.textPrimary
                        anchors.verticalCenter: parent.verticalCenter
                        x: (root.adapter?.enabled ?? false) ? parent.width - width - 2 : 2

                        Behavior on x {
                            NumberAnimation {
                                duration: Theme.duration("state")
                                easing: Theme.curve("state")
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
                    color: Theme.accent
                }

                Rectangle {
                    implicitWidth: scanLabel.implicitWidth + 14
                    implicitHeight: 22
                    radius: 4
                    color: scanBtnArea.containsMouse ? Theme.surfaceHover : Theme.surface
                    Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

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
                        radius: 6
                        color: Theme.surface

                        Column {
                            id: _deviceRows
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.leftMargin: 8
                            anchors.rightMargin: 6
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
                                Rectangle {
                                    visible: modelData.state === BluetoothDeviceState.Disconnected && !modelData.pairing && !modelData.paired
                                    implicitWidth: pairLabel.implicitWidth + 10
                                    implicitHeight: 20
                                    radius: 4
                                    color: pairArea.containsMouse ? Theme.surfaceHover : Theme.surface
                                    Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

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
                                    color: connArea.containsMouse ? Theme.surfaceHover : Theme.surface
                                    Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

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
                                    color: forgetArea.containsMouse ? Theme.surfaceHover : Theme.surfaceHoverClear
                                    Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

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
