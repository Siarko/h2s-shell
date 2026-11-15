import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.singletons
import qs.singletons.network

// The network panel's VPN section: a header with the VPNs up, a row per VPN to connect or
// disconnect it — several may be up at once — and a divider below. Hidden with no VPNs.
// VPNs by UUID (VpnManager).
Column {
    id: root

    visible: VpnManager.vpns.length > 0
    spacing: 4

    RowLayout {
        width: parent.width
        spacing: 8

        Text {
            text: VpnManager.activeType === "vpn" ? "󰌾" : "󰒃"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeTitle
            color: VpnManager.activeVpns.length > 0 ? Theme.accent : Theme.textDisabled
        }

        Text {
            text: "VPN"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSection
            color: Theme.textPrimary
            Layout.fillWidth: true
        }

        Text {
            text: VpnManager.activeVpns.length > 0 ? VpnManager.activeVpns.map(vpn => vpn.name).join(", ") : "Off"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: VpnManager.activeVpns.length > 0 ? Theme.accent : Theme.textDisabled
            elide: Text.ElideRight
            Layout.maximumWidth: 120
        }
    }

    Repeater {
        // ScriptModel, never the bare array — see "The Repeater crash" in
        // docs/ARCHITECTURE.md. The profiles are brand-new JS objects on every read, so
        // objectProp keys the diff by UUID instead of object identity — otherwise every
        // read would look like a full remove+insert (names may repeat: not by name).
        model: ScriptModel {
            objectProp: "uuid"
            values: VpnManager.vpns
        }

        delegate: Rectangle {
            required property var modelData
            required property int index

            readonly property bool isActive: modelData.state === "activated"
            readonly property bool isChanging: modelData.state === "activating" || modelData.state === "deactivating"

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
                    label: modelData.state === "activating" ? "Connecting…"
                        : modelData.state === "deactivating" ? "Disconnecting…"
                        : isActive ? "Disconnect" : "Connect"
                    kind: isActive ? "delete" : "save"
                    // Not while any connecting runs: a second click before the list says
                    // "activating" would bring the tunnel down and up again
                    available: !isChanging && !NetworkProfiles.connecting
                    onClicked: {
                        if (isActive)
                            VpnManager.disconnect(modelData.uuid)
                        else
                            VpnManager.connect(modelData.uuid)
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
