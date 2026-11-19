import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.singletons
import qs.singletons.network
import qs.panels.network

// System → Network → Wi-Fi: the radio, the network in use, and the saved networks —
// connect, autoconnect, which is preferred, the password, forget — this computer's
// hotspots (on, off, their password and devices, a new one), and joining a network that
// hides its name (notes/plans/network.md). "Find networks" slides in the networks in
// range from the right — the network popup's own list (WifiNetworkList), so connecting
// works the same in both. Profiles by UUID (NetworkProfiles); the networks in range from
// WifiManager.
Item {
    id: root

    anchors.fill: parent
    clip: true

    // The networks in range, slid in from the right
    property bool _finding: false

    // Permissions, the access point's details; and the networks in range kept fresh
    Component.onCompleted: {
        NetworkOverview.watch();
        WifiManager.holdScan();
    }
    Component.onDestruction: {
        NetworkOverview.unwatch();
        WifiManager.releaseScan();
    }

    // The saved network open for its settings, by UUID
    property string _open: ""
    // A shown password, by UUID, hidden again after a while
    property var _shownPasswords: ({})

    readonly property var _inRange: {
        const signals = {};
        for (const network of WifiManager.wifiNetworks)
            signals[network.ssid] = network.signal;
        return signals;
    }

    // The saved networks: the one in use, then those in range (strongest first), then the
    // rest (most recently used first)
    readonly property var _saved: NetworkProfiles.profiles.filter(profile => profile.kind === "wifi" && !NetworkProfiles.isHotspot(profile.uuid)).map(profile => {
        const details = NetworkProfiles.wifi[profile.uuid] ?? { ssid: profile.name, security: "", hidden: false };
        const signal = root._inRange[details.ssid];
        return Object.assign({}, profile, details, { signal: signal ?? -1 });
    }).sort((a, b) => (b.active - a.active) || ((b.signal >= 0) - (a.signal >= 0)) || (b.signal - a.signal) || (b.lastUsed - a.lastUsed))

    readonly property var _active: _saved.find(network => network.active) ?? null

    // This computer's hotspots (Wi-Fi profiles in access-point mode): the one on first
    readonly property var _hotspots: NetworkProfiles.hotspots


    function _togglePassword(uuid) {
        if (_shownPasswords[uuid] === undefined) {
            _showPassword(uuid);
            return;
        }
        const shown = Object.assign({}, _shownPasswords);
        delete shown[uuid];
        _shownPasswords = shown;
    }

    function _showPassword(uuid) {
        NetworkProfiles.readSecret(uuid, "802-11-wireless-security.psk", value => {
            const shown = Object.assign({}, root._shownPasswords);
            shown[uuid] = value;
            root._shownPasswords = shown;
            _hidePasswords.restart();
        });
    }

    Timer {
        id: _hidePasswords
        interval: 30000
        onTriggered: root._shownPasswords = {}
    }

    Flickable {
        id: _page
        anchors.fill: parent
        visible: root._editing === "" && !root._newHotspot
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
                text: "Wi-Fi"
                Layout.bottomMargin: 8
            }

            // A profile saved and reconnected, waiting for Keep (after leaving its editor)
            KeepSettingsBar {
                Layout.fillWidth: true
                Layout.bottomMargin: visible ? 10 : 0
            }

            SwitchRow {
                label: "Wi-Fi"
                hint: !WifiManager.wifiEnabled ? "Off"
                    : WifiManager.hotspot ? "Hotspot on: " + WifiManager.hotspot.ssid
                    : root._active
                    ? "Connected to " + root._active.ssid
                      + (NetworkOverview.wifiLink ? " · " + NetworkOverview.wifiLink.signal + " % · " + NetworkRules.speedText(NetworkOverview.wifiLink.rate) : "")
                    : "Not connected"
                need: NetworkOverview.need("enable-disable-wifi")
                checked: WifiManager.wifiEnabled
                onToggled: WifiManager.toggleWifi()
            }

            // The Wi-Fi device and its connection, as on the Overview
            KeyedModel {
                id: _devicesModel
                values: NetworkOverview.devices.filter(device => device.kind === "wifi" && device.state !== 10)
                keyProp: "device"
            }
            Repeater {
                model: _devicesModel.model
                NetworkDeviceCard {
                    required property string modelData
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    device: _devicesModel.byKey[modelData] ?? ({})
                }
            }

            // ── Saved networks, and finding others ──
            // A section named "saved": each card the place settings.network_wifi.saved.card,
            // its opened part …card.settings, whose `append` shows any module's elements under
            // the page's rows, and its buttons …card.actions, whose `append` shows any module's
            // buttons under "Edit connection…", above "Forget" — with the network in their
            // context (as Api.networks names it). A card is a place only while Api.networks
            // names its network: not while its details are unread (it could be a hotspot)
            SettingsSection {
                anchor: "saved"
                title: "Saved networks"
                topMargin: 14
                Layout.fillWidth: true
                buttons: SmallButton {
                    label: "Find networks"
                    available: WifiManager.wifiEnabled
                    tooltip: available ? "The networks in range, to connect to a new one" : "Wi-Fi is off"
                    onClicked: root._finding = true
                }

                Text {
                    visible: root._saved.length === 0
                    text: "None yet: networks are saved when you connect to them."
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textMuted
                }

                // Keyed by uuid: a card keeps its network (and what is typed into it) while the
                // list is rebuilt and re-sorted on every scan
                KeyedModel { id: _savedModel; values: root._saved; keyProp: "uuid" }
                Repeater {
                    model: _savedModel.model

                    NetworkProfileCard {
                        id: _network
                        objectName: "savedNetwork"
                        required property string modelData
                        readonly property var network: _savedModel.byKey[modelData] ?? ({})
                        readonly property bool _personal: network.security === "wpa-psk" || network.security === "sae"
                        readonly property var _shown: root._shownPasswords[network.uuid]
                        anchor: ModuleRules.networkListed(network, NetworkProfiles.wifi) ? "card" : ""
                        context: ModuleRules.networkContext(network)
                        markItem: context.networkId
                        Layout.fillWidth: true
                        Layout.bottomMargin: 6
                        profile: network
                        title: network.ssid + (network.name !== network.ssid ? "  (" + network.name + ")" : "")
                        subtitle: [
                            network.active ? "Connected" : network.signal >= 0 ? "In range · " + network.signal + " %" : "Out of range",
                            Nmcli.securityName(network.security),
                            network.hidden ? "Hidden" : "",
                            network.lastUsed > 0 ? "Last used " + Format.ago(network.lastUsed) : "Never used"
                        ].filter(part => part !== "").join(" · ")
                        open: root._open === network.uuid
                        // In range: on the Wi-Fi device
                        useDevice: network.signal >= 0 ? NetworkManager.wifiDevice : ""
                        autoconnectHint: "When in range"
                        priorityHint: "Higher wins when several are in range"
                        onToggleRequested: root._open = open ? "" : network.uuid
                        onForgotten: root._open = ""
                        onEditRequested: root._editing = network.uuid

                        // The password: shown for a while, or changed
                        ColumnLayout {
                            visible: _network._personal
                            Layout.fillWidth: true
                            spacing: 4
                            Text {
                                text: "Password"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody
                                color: Theme.textPrimary
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                InputField {
                                    id: _password
                                    objectName: "wifiPassword"
                                    Layout.fillWidth: true
                                    outlined: true
                                    // The eye shows the saved password for a while (read from
                                    // NetworkManager), and hides it again. Written into the field,
                                    // not bound to it: only into an empty field, and taken out only
                                    // while the field still holds it — what is typed is never
                                    // overwritten (the 30 s hiding wiped it), and clearing the field
                                    // after a save no longer stops the eye from working
                                    password: true
                                    revealed: _network._shown !== undefined
                                    ownsReveal: false
                                    onRevealToggled: root._togglePassword(_network.network.uuid)
                                    property string _written: ""
                                    readonly property var _secret: _network._shown
                                    on_SecretChanged: {
                                        if (_secret !== undefined && (text === "" || text === _written)) {
                                            text = _secret;
                                            _written = _secret;
                                        } else if (_secret === undefined && text === _written) {
                                            text = "";
                                            _written = "";
                                        }
                                    }
                                    placeholder: _network._shown === undefined ? "••••••••  (type a new one to change it)" : ""
                                    problem: text !== "" && text !== _written && !NetworkRules.isWifiPassword(text, _network.network.security)
                                }
                                SmallButton {
                                    label: "Save"
                                    kind: "save"
                                    available: !NetworkProfiles.busy && _password.text !== "" && _password.text !== _password._written
                                        && NetworkRules.isWifiPassword(_password.text, _network.network.security)
                                    onClicked: NetworkProfiles.setWifiPassword(_network.network.uuid, _password.text, ok => {
                                        if (!ok)
                                            return;
                                        const shown = Object.assign({}, root._shownPasswords);
                                        delete shown[_network.network.uuid];
                                        root._shownPasswords = shown;
                                        _password.text = "";
                                        _password._written = "";
                                    })
                                }
                            }
                            Hint {
                                visible: _password.problem
                                text: "8 to 63 characters."
                            }
                        }
                    }
                }
            }

            // ── Hotspots: this computer's own networks ──
            // A section named "hotspots", its cards named too; no place in it is published
            // (a hotspot is no network this computer joins)
            SettingsSection {
                anchor: "hotspots"
                title: "Hotspots"
                topMargin: 14
                Layout.fillWidth: true
                buttons: SmallButton {
                    label: "New hotspot"
                    tooltip: "Other devices join this computer and use its internet"
                    onClicked: root._newHotspot = true
                }

                Text {
                    visible: root._hotspots.length === 0
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: "None yet: a hotspot lets phones and other computers use this one's internet."
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textMuted
                }

                KeyedModel { id: _hotspotsModel; values: root._hotspots; keyProp: "uuid" }
                Repeater {
                    model: _hotspotsModel.model

                    NetworkProfileCard {
                        id: _hotspot
                        required property string modelData
                        readonly property var hotspot: _hotspotsModel.byKey[modelData] ?? ({})
                        readonly property var _shown: root._shownPasswords[hotspot.uuid]
                        readonly property int _devices: hotspot.active ? NetworkOverview.hotspotClients.length : 0
                        anchor: "card"
                        Layout.fillWidth: true
                        Layout.bottomMargin: 6
                        profile: hotspot
                        title: hotspot.ssid + (hotspot.name !== hotspot.ssid ? "  (" + hotspot.name + ")" : "")
                        subtitle: [
                            hotspot.active ? "On · " + _devices + (_devices === 1 ? " device" : " devices") : "Off",
                            Nmcli.securityName(hotspot.security),
                            Nmcli.bandName(hotspot.band),
                            hotspot.hidden ? "Hidden" : ""
                        ].filter(part => part !== "").join(" · ")
                        open: root._open === hotspot.uuid
                        useDevice: WifiManager.wifiEnabled ? NetworkManager.wifiDevice : ""
                        useLabel: "Turn on"
                        stopLabel: "Turn off"
                        stopsProfile: true
                        useQuestion: WifiManager.hotspotQuestion
                        autoconnectLabel: "Start automatically"
                        autoconnectHint: "When the computer starts"
                        showPriority: false
                        editTooltip: "Name, password, band, and the addresses handed out"
                        onToggleRequested: root._open = open ? "" : hotspot.uuid
                        onForgotten: root._open = ""
                        onEditRequested: root._editing = hotspot.uuid

                        // The password, to tell those who join
                        RowLayout {
                            visible: _hotspot.hotspot.security !== ""
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                text: "Password"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody
                                color: Theme.textPrimary
                            }
                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: _hotspot._shown ?? "••••••••"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody
                                color: Theme.textSecondary
                            }
                            SmallButton {
                                label: _hotspot._shown === undefined ? "Show" : "Hide"
                                onClicked: root._togglePassword(_hotspot.hotspot.uuid)
                            }
                        }

                        // Who is on it: the devices heard from lately, by address
                        ColumnLayout {
                            visible: _hotspot.hotspot.active
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: "Devices"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody
                                color: Theme.textPrimary
                            }
                            Hint {
                                visible: NetworkOverview.hotspotClients.length === 0
                                text: "None yet."
                            }
                            KeyedModel {
                                id: _clientsModel
                                values: _hotspot.hotspot.active ? NetworkOverview.hotspotClients : []
                                keyProp: "mac"
                            }
                            Repeater {
                                model: _clientsModel.model
                                RowLayout {
                                    required property string modelData
                                    readonly property var client: _clientsModel.byKey[modelData] ?? ({})
                                    Layout.fillWidth: true
                                    spacing: 12
                                    Text {
                                        text: client.address
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeBody
                                        color: Theme.textSecondary
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: client.mac
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.textMuted
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── A network that hides its name ──
            // The network popup's own form (HiddenNetworkRow), open here; its header names it
            HiddenNetworkRow {
                Layout.fillWidth: true
                Layout.topMargin: 14
                expanded: true
            }
        }
    }

    // ── Networks in range: a panel from the right, over the page ──
    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
        opacity: root._finding ? 0.35 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.duration("slide"); easing: Theme.curve("slide") } }
        // A click beside the panel closes it
        MouseArea {
            anchors.fill: parent
            onClicked: root._finding = false
        }
    }

    Rectangle {
        id: _drawer
        width: Math.min(420, root.width * 0.9)
        height: parent.height
        x: root._finding ? parent.width - width : parent.width
        visible: x < parent.width
        color: Theme.popupBackground
        border.width: Theme.border.width
        border.color: Theme.outline
        Behavior on x { NumberAnimation { duration: Theme.duration("slide"); easing: Theme.curve("slide") } }

        // Clicks on the panel stay on it
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors { fill: parent; margins: Theme.settings.pageMargin }
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Text {
                    Layout.fillWidth: true
                    text: "Networks in range"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    font.bold: true
                    color: Theme.textPrimary
                }
                Text {
                    visible: WifiManager.scanInProgress
                    text: "Scanning…"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.accent
                }
                SmallButton {
                    label: "Close"
                    onClicked: root._finding = false
                }
            }

            Text {
                visible: !WifiManager.wifiEnabled
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "Wi-Fi is off."
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textMuted
            }

            WifiNetworkList {
                visible: WifiManager.wifiEnabled
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                maximumHeight: _drawer.height - 2 * Theme.settings.pageMargin - 60
            }

            Item { Layout.fillHeight: true }
        }
    }

    // ── The connection editor, over the page, for the profile asked for ──
    // The profile being edited, by UUID ("" none); or a new hotspot being made
    property string _editing: ""
    property bool _newHotspot: false
    Loader {
        anchors.fill: parent
        active: root._editing !== "" || root._newHotspot
        sourceComponent: NetworkConnectionEditor {
            uuid: root._editing
            active: NetworkProfiles.profiles.some(profile => profile.uuid === root._editing && profile.active)
            // Read once, when the editor is made (a fresh password each time)
            template: root._newHotspot ? NetworkRules.hotspotTemplate(NetworkOverview.hostname, NetworkRules.hotspotPassword(Math.random)) : null
            onClosed: {
                root._editing = "";
                root._newHotspot = false;
            }
            onCreated: uuid => {
                root._newHotspot = false;
                root._open = uuid;
            }
        }
    }
}
