import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.singletons
import qs.singletons.network

// System → Network → Overview: the computer's network as NetworkManager has it — whether it
// is online, the radios and networking itself, each device with its details, and the
// settings above any one connection: hostname, a global DNS, the connectivity check
// (NetworkOverview; docs/plans/network.md). Changes apply at once.
Flickable {
    id: root

    anchors.fill: parent
    contentWidth: width
    contentHeight: _column.implicitHeight + 2 * Theme.settings.pageMargin
    flickableDirection: Flickable.VerticalFlick
    clip: true

    Component.onCompleted: NetworkOverview.watch()
    Component.onDestruction: NetworkOverview.unwatch()

    readonly property var _connectivityText: ({
        "full": "Online",
        "limited": "Connected, but the internet cannot be reached",
        "portal": "Behind a sign-in page (a hotel's or café's Wi-Fi)",
        "none": "Offline",
        "unknown": "Online status unknown"
    })

    // The page of a kind of connection, "" until it has one — by the same test the
    // sidebar shows that page by (SettingsWindow.pages' `shown`), so a link never leads to a
    // page the sidebar hides
    function _pageOf(kind) {
        if (kind === "wifi")
            return NetworkManager.wifiAvailable ? "network_wifi" : "";
        if (kind === "ethernet")
            return NetworkManager.ethernetDevice !== "" ? "network_ethernet" : "";
        if (kind === "vpn")
            return "network_vpn";
        return "";
    }

    function _copy(text) {
        Quickshell.clipboardText = text;
        Notifier.send("Copied for configuration.nix", { body: text, urgency: "low", category: "x-qs-shell" });
    }

    ColumnLayout {
        id: _column
        x: Theme.settings.pageMargin
        y: Theme.settings.pageMargin
        width: root.width - 2 * Theme.settings.pageMargin
        spacing: 0

        Heading {
            text: "Network"
            Layout.bottomMargin: 2
        }
        Text {
            Layout.fillWidth: true
            Layout.bottomMargin: 8
            wrapMode: Text.WordWrap
            text: root._connectivityText[NetworkOverview.connectivity] ?? ""
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            color: NetworkOverview.connectivity === "full" ? Theme.success
                : NetworkOverview.connectivity === "none" ? Theme.textMuted : Theme.warning
        }

        // ── Each kind of connection, in a line ──
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 4
            implicitHeight: _summary.implicitHeight + 16
            radius: Theme.settings.cardRadius
            color: Theme.fillSubtle
            border.width: Theme.border.width
            border.color: Theme.outline

            ColumnLayout {
                id: _summary
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                spacing: 4
                Repeater {
                    model: ScriptModel { values: NetworkOverview.summary; objectProp: "kind" }
                    RowLayout {
                        id: _summaryLine
                        required property var modelData
                        // The kind's own page, once it has one (docs/plans/network.md)
                        readonly property string _page: root._pageOf(modelData.kind)
                        Layout.fillWidth: true
                        spacing: 8
                        Rectangle {
                            implicitWidth: 8
                            implicitHeight: 8
                            radius: 4
                            color: modelData.good ? Theme.success : Theme.textMuted
                        }
                        Text {
                            Layout.preferredWidth: 140
                            text: modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            color: Theme.textPrimary
                        }
                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: modelData.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            color: modelData.good ? Theme.textSecondary : Theme.textMuted
                        }
                        Text {
                            visible: _summaryLine._page !== ""
                            text: "›"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            color: _summaryArea.lit ? Theme.textPrimary : Theme.textMuted
                            // The arrow, with the usual larger target around it
                            PointerArea {
                                id: _summaryArea
                                reach: 10
                                enabled: _summaryLine._page !== ""
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Shell.openSettings(_summaryLine._page)
                            }
                        }
                    }
                }
            }
        }

        // ── Everything at once ──
        SectionTitle { text: "Switches" }
        SwitchRow {
            label: "Airplane mode"
            hint: "All radios off"
            // The strictest of the radios it switches
            need: ["no", "auth"].find(answer => [NetworkOverview.need("enable-disable-wifi"),
                NetworkOverview.modemHardware ? NetworkOverview.need("enable-disable-wwan") : ""].includes(answer)) ?? ""
            checked: NetworkOverview.airplane
            onToggled: NetworkOverview.setAirplane(!checked)
        }
        SwitchRow {
            label: "Networking"
            hint: "All connections off"
            need: NetworkOverview.need("enable-disable-network")
            checked: NetworkOverview.networkingEnabled
            onToggled: NetworkOverview.setNetworking(!checked)
        }

        // ── Devices ──
        SectionTitle { text: "Devices" }
        Text {
            visible: NetworkOverview.mainDevices.length === 0
            text: "No network devices found."
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            color: Theme.textMuted
        }

        Repeater {
            // ScriptModel, never the bare array (CLAUDE.md)
            model: ScriptModel { values: NetworkOverview.mainDevices; objectProp: "device" }

            NetworkDeviceCard {
                required property var modelData
                Layout.fillWidth: true
                Layout.bottomMargin: 8
                device: modelData
                page: root._pageOf(modelData.kind)
            }
        }

        // The rest: bridges, tunnels, containers' — folded
        RowLayout {
            visible: NetworkOverview.otherDevices.length > 0
            Layout.fillWidth: true
            Layout.topMargin: 2
            spacing: 6
            SmallButton {
                label: (_others.open ? "▾ " : "▸ ") + "Other devices (" + NetworkOverview.otherDevices.length + ")"
                onClicked: _others.open = !_others.open
            }
            Item { Layout.fillWidth: true }
        }
        ColumnLayout {
            id: _others
            property bool open: false
            visible: open && NetworkOverview.otherDevices.length > 0
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 2
            Repeater {
                model: ScriptModel { values: _others.open ? NetworkOverview.otherDevices : []; objectProp: "device" }
                DetailRow {
                    required property var modelData
                    label: modelData.device
                    value: modelData.type + " · " + modelData.stateText + (modelData.ipv4.length > 0 ? " · " + modelData.ipv4.join(", ") : "")
                }
            }
        }

        // ── Above any one connection ──
        SectionTitle { text: "This computer" }

        Text {
            text: "Hostname"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            color: Theme.textPrimary
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8
            InputField {
                id: _hostnameField
                Layout.preferredWidth: 260
                outlined: true
                text: NetworkOverview.hostname
                problem: text !== "" && !NetworkRules.isHostname(text)
                input.inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhPreferLowercase
                onAccepted: _hostnameSave.clicked()
                onEditingChanged: if (!editing && text === NetworkOverview.hostname) text = Qt.binding(() => NetworkOverview.hostname)
            }
            PrivilegedMark { need: NetworkOverview.need("settings.modify.hostname") }
            SmallButton {
                id: _hostnameSave
                label: "Save"
                kind: "save"
                available: _hostnameField.text !== NetworkOverview.hostname && NetworkRules.isHostname(_hostnameField.text)
                    && NetworkOverview.need("settings.modify.hostname") !== "no"
                onClicked: if (available) NetworkOverview.setHostname(_hostnameField.text)
            }
            Item { Layout.fillWidth: true }
        }
        Hint {
            Layout.bottomMargin: 12
            text: _hostnameField.problem ? "Letters, digits and hyphens; dots between parts; not starting or ending with a hyphen."
                : "How this computer is named on the network."
        }

        Text {
            text: "Global DNS"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            color: Theme.textPrimary
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8
            InputField {
                id: _dnsField
                readonly property var _parsed: NetworkRules.parseServers(text)
                readonly property string _current: NetworkOverview.globalDns.join(", ")
                Layout.fillWidth: true
                outlined: true
                placeholder: "None: each connection's own DNS"
                text: _current
                problem: _parsed.bad.length > 0
                input.inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhPreferNumbers
                onAccepted: _dnsSave.clicked()
                onEditingChanged: if (!editing && _parsed.list.join(", ") === _current) text = Qt.binding(() => _current)
            }
            PrivilegedMark { need: NetworkOverview.need("settings.modify.global-dns") }
            SmallButton {
                id: _dnsSave
                label: _dnsField._parsed.list.length === 0 && NetworkOverview.globalDns.length > 0 ? "Clear" : "Save"
                kind: "save"
                available: _dnsField._parsed.bad.length === 0 && _dnsField._parsed.list.join(", ") !== _dnsField._current
                    && NetworkOverview.need("settings.modify.global-dns") !== "no"
                onClicked: if (available) NetworkOverview.setGlobalDns(_dnsField._parsed.list)
            }
        }
        Hint {
            Layout.bottomMargin: 12
            text: _dnsField.problem ? "Not an address: " + _dnsField._parsed.bad.join(", ")
                : "Over every connection's own, e.g. 1.1.1.1, 9.9.9.9."
        }

        SwitchRow {
            visible: NetworkOverview.connectivityCheckAvailable
            label: "Connectivity check"
            hint: "Tells online from behind a sign-in page"
            need: NetworkOverview.need("enable-disable-connectivity-check")
            checked: NetworkOverview.connectivityCheckEnabled
            onToggled: NetworkOverview.setConnectivityCheck(!checked)
        }
        Text {
            visible: !NetworkOverview.connectivityCheckAvailable
            text: "Connectivity check"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            color: Theme.textPrimary
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8
            InputField {
                id: _uriField
                readonly property string _current: NetworkOverview.connectivityCheckUri
                Layout.fillWidth: true
                outlined: true
                placeholder: "Not set up — e.g. http://nmcheck.gnome.org/check_network_status.txt"
                text: _current
                problem: text !== "" && !NetworkRules.isConnectivityUri(text)
                input.inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                onAccepted: _uriSave.clicked()
                onEditingChanged: if (!editing && text === _current) text = Qt.binding(() => _current)
            }
            // Root always: the address is in NetworkManager's configuration (pkexec)
            PrivilegedMark { need: "auth"; visible: !NetworkOverview.isNixos }
            SmallButton {
                id: _uriSave
                readonly property bool _changed: _uriField.text !== NetworkOverview.connectivityCheckUri && !_uriField.problem
                // NixOS: the line for configuration.nix, to keep the system declarative
                label: NetworkOverview.isNixos ? "Copy for configuration.nix"
                    : _uriField.text === "" && NetworkOverview.connectivityCheckUri !== "" ? "Default" : "Save"
                kind: "save"
                available: NetworkOverview.isNixos ? _uriField.text !== "" && !_uriField.problem : _changed && !NetworkOverview.busy
                tooltip: !NetworkOverview.isNixos && _uriField.text === "" ? "Back to the distribution's address (none on some)" : ""
                onClicked: {
                    if (!available)
                        return;
                    if (NetworkOverview.isNixos) {
                        root._copy("networking.networkmanager.settings.connectivity.uri = \"" + _uriField.text.trim() + "\";");
                        return;
                    }
                    NetworkOverview.setConnectivityUri(_uriField.text.trim());
                }
            }
        }
        RowLayout {
            visible: NetworkOverview.isNixos
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 6
            Hint {
                text: "Add the copied line to your configuration.nix and rebuild — or write NetworkManager's file here, outside the system's configuration:"
            }
            PrivilegedMark { need: "auth" }
            SmallButton {
                label: "Write anyway"
                available: _uriSave._changed && !NetworkOverview.busy
                onClicked: if (available) NetworkOverview.setConnectivityUri(_uriField.text.trim())
            }
        }
        Hint {
            text: _uriField.problem ? "An http:// or https:// address, without spaces or quotes."
                : NetworkOverview.isNixos ? "The address it fetches now and then."
                : "The address it fetches now and then; saved in " + NetworkOverview.connectivityConfigFile + "."
        }

    }
}
