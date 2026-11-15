import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.singletons
import qs.singletons.network

// The network panel's VPN section: a header with the VPNs up, a row per VPN to connect or
// disconnect it — several may be up at once — and a divider below. Hidden with no VPNs.
// VPNs by id (VpnManager): NetworkManager's by UUID, a provider's (components/VpnProvider
// .qml) by "<provider>:<entry>" — a provider's row adds what needs the user (its attention,
// with the action's button), the kill switch's note, and the provider's extras (slot
// network.vpn.row). A NetworkManager VPN's row is only the row.
Column {
    id: root

    visible: VpnManager.vpns.length > 0
    spacing: 4

    RowLayout {
        width: parent.width
        spacing: 8

        Text {
            text: VpnManager.activeGlyph
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
        // objectProp keys the diff by id instead of object identity — otherwise every
        // read would look like a full remove+insert (names may repeat: not by name).
        model: ScriptModel {
            objectProp: "uuid"
            values: VpnManager.vpns
        }

        delegate: Column {
            id: _vpn
            required property var modelData
            required property int index

            readonly property bool isActive: modelData.state === "activated"
            readonly property bool isChanging: modelData.state === "activating" || modelData.state === "deactivating"
            // A provider's lasting "needs the user" ({ reason, action }), else null
            readonly property var attention: modelData.attention ?? null
            readonly property string lockdownNote: VpnLockdown.noteFor(modelData)

            width: root.width
            spacing: 2

            Rectangle {
                width: parent.width
                height: 36
                radius: Theme.row.radius
                color: _vpn.isActive ? Theme.accentTint : Theme.surface

                RowLayout {
                    anchors { fill: parent; leftMargin: Theme.row.horizontalPadding; rightMargin: Theme.row.horizontalPadding }
                    spacing: 6

                    Text {
                        text: VpnManager.glyphOf(_vpn.modelData)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        color: _vpn.isActive ? Theme.accent : Theme.textMuted
                    }

                    Text {
                        text: _vpn.modelData.name
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        color: _vpn.isActive ? Theme.accent : Theme.textPrimary
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    PrivilegedMark {
                        need: VpnManager.needFor(_vpn.modelData)
                    }

                    SmallButton {
                        // Needing the user and off: its action in place of Connect
                        readonly property bool _attends: _vpn.attention !== null && _vpn.attention.action !== "" && !_vpn.modelData.active
                        label: _attends ? _vpn.attention.action
                            : _vpn.modelData.state === "activating" ? "Connecting…"
                            : _vpn.modelData.state === "deactivating" ? "Disconnecting…"
                            : _vpn.isActive ? "Disconnect" : "Connect"
                        kind: _vpn.isActive ? "delete" : "save"
                        visible: _attends || _vpn.attention === null || _vpn.modelData.active
                        // Not while an operation runs: for NetworkManager's, while any
                        // connecting runs — a second click before the list says
                        // "activating" would bring the tunnel down and up again
                        available: !_vpn.isChanging && !VpnManager.busyFor(_vpn.modelData)
                        onClicked: {
                            if (_attends)
                                VpnManager.attend(_vpn.modelData.uuid)
                            else if (_vpn.isActive)
                                VpnManager.disconnect(_vpn.modelData.uuid)
                            else
                                VpnManager.connect(_vpn.modelData.uuid)
                        }
                    }
                }
            }

            // What needs the user, lasting until it is done (a provider's)
            RowLayout {
                visible: _vpn.attention !== null
                width: parent.width
                spacing: 6
                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.row.horizontalPadding
                    wrapMode: Text.WordWrap
                    text: _vpn.attention?.reason ?? ""
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.warning
                }
                SmallButton {
                    // Shown here only while active (otherwise it is the row's button)
                    visible: _vpn.attention !== null && (_vpn.attention.action ?? "") !== "" && _vpn.modelData.active
                    label: _vpn.attention?.action ?? ""
                    available: !VpnManager.busyFor(_vpn.modelData)
                    onClicked: VpnManager.attend(_vpn.modelData.uuid)
                }
            }

            // The kill switch does not let a provider's VPN through: said while blocking
            Text {
                visible: _vpn.lockdownNote !== ""
                width: parent.width - Theme.row.horizontalPadding
                x: Theme.row.horizontalPadding
                wrapMode: Text.WordWrap
                text: _vpn.lockdownNote
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.warning
            }

            // The provider's extras under its row (slot network.vpn.row)
            VpnExtras {
                width: parent.width
                slot: VpnManager.slots.row
                vpn: _vpn.modelData
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
