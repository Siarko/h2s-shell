import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.singletons
import qs.singletons.network

// System → Network → Ethernet: each wired device with its connection (the Overview's card),
// or that its cable is out; and the wired profiles — which one is in use, connect
// automatically, priority, use one, forget (notes/plans/network.md). Several profiles make
// sense for one cable: home and an office with a fixed address, say. A profile's
// addresses and DNS are the connection editor's (NetworkConnectionEditor).
Item {
    id: root

    anchors.fill: parent
    clip: true

    Component.onCompleted: NetworkOverview.watch()
    Component.onDestruction: NetworkOverview.unwatch()

    // The profile open for its settings, by UUID
    property string _open: ""

    readonly property var _devices: NetworkOverview.devices.filter(device => device.kind === "ethernet" && device.state !== 10)

    // The ordinary wired profiles: not a bridge's or bond's port, not one NetworkManager
    // keeps for a device that is not a real wired one (a container's, a VM's) — in use
    // first, then the most recently used
    readonly property var _profiles: NetworkProfiles.profiles.filter(profile => profile.kind === "ethernet" && profile.port === ""
            && (!profile.active || _devices.some(device => device.device === profile.device)))
        .sort((a, b) => (b.active - a.active) || (b.lastUsed - a.lastUsed))

    // The device a profile is used on: the first ready to connect — a cable in, not out
    // (none: no "Use", which could only fail)
    readonly property string _usableDevice: (_devices.find(device => device.state >= 30 && device.carrier !== "off") ?? { device: "" }).device

    Flickable {
        id: _page
        anchors.fill: parent
        visible: root._editing === ""
        contentWidth: width
        contentHeight: _column.implicitHeight + 2 * Theme.settings.pageMargin
        flickableDirection: Flickable.VerticalFlick

        ColumnLayout {
            id: _column
            x: Theme.settings.pageMargin
            y: Theme.settings.pageMargin
            width: _page.width - 2 * Theme.settings.pageMargin
            spacing: 0

            Heading {
                text: "Ethernet"
                Layout.bottomMargin: 8
            }

            // A profile saved and reconnected, waiting for Keep (after leaving its editor)
            KeepSettingsBar {
                Layout.fillWidth: true
                Layout.bottomMargin: visible ? 10 : 0
            }

            // ── The devices ──
            Repeater {
                // ScriptModel, never the bare array (CLAUDE.md)
                model: ScriptModel { values: root._devices; objectProp: "device" }

                ColumnLayout {
                    id: _device
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.bottomMargin: 10
                    spacing: 6

                    NetworkDeviceCard {
                        Layout.fillWidth: true
                        device: _device.modelData
                    }

                    // Connecting is the profiles' (below): here only a missing cable is said — by
                    // the cable itself (carrier): "unavailable" also means no firmware, or disabled
                    Text {
                        visible: _device.modelData.carrier === "off"
                        text: "Cable unplugged"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        color: Theme.textMuted
                    }
                }
            }
            Text {
                visible: root._devices.length === 0
                text: "No wired network device."
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textMuted
            }

            // ── The wired profiles ──
            SectionTitle { text: "Wired profiles" }
            Text {
                visible: root._profiles.length === 0
                text: "None: NetworkManager makes one when a cable is plugged in."
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textMuted
            }

            Repeater {
                model: ScriptModel { values: root._profiles; objectProp: "uuid" }

                NetworkProfileCard {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.bottomMargin: 6
                    profile: modelData
                    subtitle: (modelData.active ? "In use on " + modelData.device
                            : modelData.lastUsed > 0 ? "Last used " + Format.ago(modelData.lastUsed) : "Never used")
                        + (modelData.autoconnect ? "" : " · Not automatic")
                    open: root._open === modelData.uuid
                    useDevice: root._usableDevice
                    useLabel: "Use"
                    autoconnectHint: "When a cable is plugged in"
                    onToggleRequested: root._open = open ? "" : modelData.uuid
                    onForgotten: root._open = ""
                    onEditRequested: root._editing = modelData.uuid
                }
            }
        }
    }

    // ── The connection editor, over the page, for the profile asked for ──
    // The profile being edited, by UUID ("" none)
    property string _editing: ""
    Loader {
        anchors.fill: parent
        active: root._editing !== ""
        sourceComponent: NetworkConnectionEditor {
            uuid: root._editing
            active: NetworkProfiles.profiles.some(profile => profile.uuid === root._editing && profile.active)
            onClosed: root._editing = ""
        }
    }
}
