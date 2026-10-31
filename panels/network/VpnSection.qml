import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.singletons
import qs.singletons.network

// The network panel's VPN section: a header with the active VPN, a row per VPN
// connection to connect or disconnect it, and a divider below. Hidden with no VPNs.
Column {
    id: root

    visible: VpnManager.vpnConnections.length > 0
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
        // ScriptModel, never the bare array — see "The Repeater crash" in
        // docs/ARCHITECTURE.md. VpnManager rebuilds vpnConnections as brand-new JS
        // objects on every poll, so objectProp keys the diff by "name" instead of object
        // identity — otherwise every poll would look like a full remove+insert.
        model: ScriptModel {
            objectProp: "name"
            values: VpnManager.vpnConnections
        }

        delegate: Rectangle {
            required property var modelData
            required property int index

            property bool isActive: VpnManager.activeVpn === modelData.name

            width: root.width
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
