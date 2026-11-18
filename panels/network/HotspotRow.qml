import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.singletons
import qs.singletons.network

// "Hotspots": under "Connect to hidden network", when some are saved — a header that opens
// the saved hotspots, each with "Turn on". Turning on asks first when it would take the
// Wi-Fi off the network it is on with no cable or modem to share (WifiManager
// .hotspotQuestion), as on the settings page; making and editing them is the page's.
Rectangle {
    id: root

    property bool expanded: false

    // The saved hotspots, the most recently used first (none is on: the popup shows that
    // one instead of this row)
    readonly property var _hotspots: NetworkProfiles.hotspots

    visible: _hotspots.length > 0
    height: visible ? (expanded ? _column.implicitHeight + 6 : _header.height) : 0
    radius: Theme.row.radius
    color: "transparent"
    clip: true

    Behavior on height { NumberAnimation { duration: Theme.duration("expand"); easing: Theme.curve("expand") } }

    Column {
        id: _column
        width: parent.width
        spacing: 4

        Item {
            id: _header
            width: parent.width
            height: Math.max(30, _headerContent.implicitHeight + 6)

            RowLayout {
                id: _headerContent
                anchors.fill: parent
                spacing: 6

                Text {
                    text: "󰀃"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textMuted
                }

                Text {
                    text: "Hotspots"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textSecondary
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                Text {
                    text: root.expanded ? "󰅃" : "󰅀"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textMuted
                }
            }

            PointerArea {
                anchors.fill: parent
                centred: false
                cursorShape: Qt.PointingHandCursor
                onClicked: root.expanded = !root.expanded
            }
        }

        Repeater {
            // ScriptModel, never the bare array (CLAUDE.md)
            model: ScriptModel { values: root._hotspots; objectProp: "uuid" }

            Rectangle {
                id: _hotspot
                required property var modelData
                width: _column.width
                height: _row.implicitHeight + 8
                radius: Theme.row.radius
                color: Theme.surface

                RowLayout {
                    id: _row
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 8; rightMargin: 4 }
                    spacing: 6

                    Column {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: _hotspot.modelData.ssid
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            color: Theme.textPrimary
                        }
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: [Nmcli.securityName(_hotspot.modelData.security), Nmcli.bandName(_hotspot.modelData.band)]
                                .filter(part => part !== "").join(" · ")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXSmall
                            color: Theme.textMuted
                        }
                    }

                    SmallButton {
                        visible: WifiManager.hotspotQuestion === ""
                        label: "Turn on"
                        kind: "save"
                        available: !NetworkProfiles.connecting && NetworkManager.wifiDevice !== ""
                        onClicked: NetworkProfiles.activate(_hotspot.modelData.uuid, NetworkManager.wifiDevice)
                    }
                    // Asks first: the network in use would be left with nothing to share
                    DeleteButton {
                        visible: WifiManager.hotspotQuestion !== ""
                        kind: "save"
                        label: "Turn on"
                        fontSize: Theme.fontSizeBody
                        confirmLabel: "No internet to share. Turn on?"
                        cancelTip: "Stay on " + (WifiManager.wifiNetworks.find(network => network.inUse)?.ssid ?? "the network")
                        available: !NetworkProfiles.connecting && NetworkManager.wifiDevice !== ""
                        onConfirmed: NetworkProfiles.activate(_hotspot.modelData.uuid, NetworkManager.wifiDevice)
                    }
                }
            }
        }
    }
}
