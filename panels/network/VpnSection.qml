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
// with the action's button), its status line, the kill switch's note (while it is up or
// coming up), and the provider's extras (slot network.vpn.row). A NetworkManager VPN's row
// is only the row. A popup section block named "vpn", each VPN's row a row block ("row"):
// named, not places yet (ModuleRules.anchorTable).
PopupSection {
    id: root

    anchor: "vpn"
    visible: VpnManager.vpns.length > 0
    spacing: 4
    divider: true

    header: Component {
        RowLayout {
            spacing: 8

            Text {
                text: VpnManager.activeGlyph
                textFormat: Text.PlainText
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
                textFormat: Text.PlainText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: VpnManager.activeVpns.length > 0 ? Theme.accent : Theme.textDisabled
                elide: Text.ElideRight
                Layout.maximumWidth: 120
            }
        }
    }

    // Keyed by uuid (names may repeat): the profiles are new objects on every read
    // ("The Repeater crash" in docs/ARCHITECTURE.md)
    KeyedModel { id: _vpnsModel; values: VpnManager.vpns; keyProp: "uuid" }

    Repeater {
        model: _vpnsModel.model

        delegate: PopupRow {
            id: _vpn
            required property string modelData
            readonly property var vpn: _vpnsModel.byKey[modelData] ?? ({})
            required property int index

            readonly property bool isActive: vpn.state === "activated"
            readonly property bool isChanging: vpn.state === "activating" || vpn.state === "deactivating"
            // A provider's lasting "needs the user" ({ reason, action }), else null
            readonly property var attention: VpnManager.attentionOf(vpn)
            readonly property string lockdownNote: VpnLockdown.noteFor(vpn)

            anchor: "row"
            width: root.width
            spacing: 2

            Rectangle {
                objectName: "vpnRow"
                width: parent.width
                // As tall as before for a row of one line (NetworkManager's VPNs); a status
                // line under the name makes it taller, as the hotspot rows' second line does
                height: Math.max(36, _names.implicitHeight + 8)
                radius: Theme.row.radius
                color: _vpn.isActive ? Theme.accentTint : Theme.surface

                RowLayout {
                    anchors { fill: parent; leftMargin: Theme.row.horizontalPadding; rightMargin: Theme.row.horizontalPadding }
                    spacing: 6

                    Text {
                        text: VpnManager.glyphOf(_vpn.vpn)
                        textFormat: Text.PlainText
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        color: _vpn.isActive ? Theme.accent : Theme.textMuted
                    }

                    // The name, and under it a provider's one line ("Tailnet only", "Via
                    // <exit node>", "Starting…") in the muted sub-line style of the hotspot
                    // rows — beside the name it squeezed both into one elided line
                    Column {
                        id: _names
                        Layout.fillWidth: true
                        spacing: 0

                        Text {
                            objectName: "vpnName"
                            width: parent.width
                            text: _vpn.vpn.name
                            textFormat: Text.PlainText
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            color: _vpn.isActive ? Theme.accent : Theme.textPrimary
                            elide: Text.ElideRight
                        }

                        Text {
                            objectName: "vpnStatus"
                            width: parent.width
                            visible: text !== ""
                            text: _vpn.vpn.status ?? ""
                            textFormat: Text.PlainText
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXSmall
                            color: Theme.textMuted
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }

                    PrivilegedMark {
                        need: VpnManager.needFor(_vpn.vpn)
                    }

                    SmallButton {
                        // Needing the user and off: its action in place of Connect, or no
                        // button when it has none (VpnManager.primaryLabel)
                        readonly property bool _attends: VpnManager.attendsInstead(_vpn.vpn)
                        label: VpnManager.primaryLabel(_vpn.vpn)
                        kind: _vpn.isActive ? "delete" : "save"
                        visible: label !== ""
                        // Not while an operation runs: for NetworkManager's, while any
                        // connecting runs — a second click before the list says
                        // "activating" would bring the tunnel down and up again
                        available: !_vpn.isChanging && !VpnManager.busyFor(_vpn.vpn)
                        onClicked: {
                            if (_attends)
                                VpnManager.attend(_vpn.vpn.uuid)
                            else if (_vpn.isActive)
                                VpnManager.disconnect(_vpn.vpn.uuid)
                            else
                                VpnManager.connect(_vpn.vpn.uuid)
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
                    // A provider's words, and through it a daemon's: never read as markup
                    textFormat: Text.PlainText
                    text: _vpn.attention?.reason ?? ""
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.warning
                }
                SmallButton {
                    // Shown here only while active (otherwise it is the row's button)
                    visible: _vpn.attention !== null && (_vpn.attention.action ?? "") !== "" && _vpn.vpn.active
                    label: _vpn.attention?.action ?? ""
                    available: !VpnManager.busyFor(_vpn.vpn)
                    onClicked: VpnManager.attend(_vpn.vpn.uuid)
                }
            }

            // The kill switch does not let a provider's VPN through: said while blocking
            Text {
                visible: _vpn.lockdownNote !== ""
                width: parent.width - Theme.row.horizontalPadding
                x: Theme.row.horizontalPadding
                wrapMode: Text.WordWrap
                text: _vpn.lockdownNote
                textFormat: Text.PlainText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.warning
            }

            // The provider's extras under its row (slot network.vpn.row)
            VpnExtras {
                width: parent.width
                slot: VpnManager.slots.row
                vpn: _vpn.vpn
            }
        }
    }
}
