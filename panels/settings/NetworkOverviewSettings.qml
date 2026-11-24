import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.singletons
import qs.singletons.network

// System → Network → Overview: the computer's network as NetworkManager has it — whether it
// is online, the radios and networking itself, each device with its details, and the
// settings above any one connection: hostname, a global DNS, the connectivity check
// (NetworkOverview). Changes apply at once.
Flickable {
    id: root

    anchors.fill: parent
    contentWidth: width
    contentHeight: _column.implicitHeight + 2 * Theme.settings.pageMargin
    flickableDirection: Flickable.VerticalFlick
    clip: true

    // The overview's watch (devices, connectivity),
    // held while the page is on screen, not while the window is hidden
    property bool _held: false
    PageShown {
        id: _onScreen
        onShownChanged: root._hold(shown)
    }
    Component.onCompleted: _hold(_onScreen.shown)
    Component.onDestruction: _hold(false)
    function _hold(wanted) {
        if (wanted === _held)
            return;
        _held = wanted;
        if (wanted) {
            NetworkOverview.watch();
        } else {
            NetworkOverview.unwatch();
        }
    }

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

    // The distribution's answers for the connectivity check's address (NetworkOverview's),
    // handed in by a suite
    property var uriCapability: NetworkOverview.connectivityUriCapability
    property var uriInForce: NetworkOverview.connectivityUriInForce
    property string uriBusy: NetworkOverview.connectivityUriBusy
    property bool uriUndoable: NetworkOverview.connectivityUriUndoable
    property string uriCurrent: NetworkOverview.connectivityCheckUri
    // What the address's row offers: Save, Default, Copy, Write anyway, Undo, labels and
    // effects, and the line under it
    readonly property var _uriOffer: ConnectivityRules.offer({
        field: _uriField.text.trim(), current: uriCurrent, capability: uriCapability,
        snippet: uriCapability.mode === "copy" || uriCapability.mode === "declare" ? NetworkOverview.connectivityUriSnippet(_uriField.text.trim()) : "",
        inForce: uriInForce, busy: uriBusy, undoable: uriUndoable
    })

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
                KeyedModel { id: _summaryModel; values: NetworkOverview.summary; keyProp: "kind" }
                Repeater {
                    model: _summaryModel.model
                    RowLayout {
                        id: _summaryLine
                        required property string modelData
                        readonly property var kindSummary: _summaryModel.byKey[modelData] ?? ({})
                        // The kind's own page, once it has one
                        readonly property string _page: root._pageOf(kindSummary.kind)
                        Layout.fillWidth: true
                        spacing: 8
                        Rectangle {
                            implicitWidth: 8
                            implicitHeight: 8
                            radius: 4
                            color: kindSummary.good ? Theme.success : Theme.textMuted
                        }
                        Text {
                            Layout.preferredWidth: 140
                            text: kindSummary.label
                            textFormat: Text.PlainText
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            color: Theme.textPrimary
                        }
                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: kindSummary.text
                            textFormat: Text.PlainText
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            color: kindSummary.good ? Theme.textSecondary : Theme.textMuted
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

        KeyedModel { id: _mainDevicesModel; values: NetworkOverview.mainDevices; keyProp: "device" }
        Repeater {
            model: _mainDevicesModel.model

            NetworkDeviceCard {
                required property string modelData
                readonly property var networkDevice: _mainDevicesModel.byKey[modelData] ?? ({})
                Layout.fillWidth: true
                Layout.bottomMargin: 8
                device: networkDevice
                page: root._pageOf(networkDevice.kind)
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
            KeyedModel { id: _otherDevicesModel; values: _others.open ? NetworkOverview.otherDevices : []; keyProp: "device" }
            Repeater {
                model: _otherDevicesModel.model
                DetailRow {
                    required property string modelData
                    readonly property var otherDevice: _otherDevicesModel.byKey[modelData] ?? ({})
                    label: otherDevice.device
                    value: otherDevice.type + " · " + otherDevice.stateText + (otherDevice.ipv4.length > 0 ? " · " + otherDevice.ipv4.join(", ") : "")
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
                onAccepted: if (root._uriOffer.save.button === "plain") _uriSave.clicked(); else if (root._uriOffer.copy.shown) _uriCopy.clicked()
                onEditingChanged: if (!editing && text === _current) text = Qt.binding(() => _current)
            }
            // Root always: the address is in NetworkManager's configuration (pkexec)
            PrivilegedMark { need: "auth"; visible: root._uriOffer.save.shown }
            SmallButton {
                id: _uriSave
                objectName: "connectivitySave"
                visible: root._uriOffer.save.shown && root._uriOffer.save.button === "plain"
                label: root._uriOffer.save.label
                kind: "save"
                available: root._uriOffer.save.available
                tooltip: root._uriOffer.save.tooltip
                onClicked: if (available) NetworkOverview.applyConnectivityUri(root._uriOffer.save.request)
            }
            // A setting the change would override (another file read before the shell's, the
            // shell's own changed outside it): it acts only on a second click
            DeleteButton {
                objectName: "connectivitySaveAsking"
                visible: root._uriOffer.save.shown && root._uriOffer.save.button === "ask"
                kind: "save"
                label: root._uriOffer.save.label
                confirmLabel: root._uriOffer.save.question
                available: root._uriOffer.save.available
                // The question is about this file and this address: another resets it
                readonly property string subject: JSON.stringify(root._uriOffer.save.request)
                onSubjectChanged: asking = false
                onConfirmed: NetworkOverview.applyConnectivityUri(root._uriOffer.save.request)
            }
            SmallButton {
                objectName: "connectivityUndo"
                visible: root._uriOffer.undo.shown
                label: root._uriOffer.undo.label
                available: root._uriOffer.undo.available
                onClicked: if (available) NetworkOverview.undoConnectivityUri()
            }
            // Where the system's configuration sets it: the line for it, to keep it declarative
            SmallButton {
                id: _uriCopy
                objectName: "connectivityCopy"
                visible: root._uriOffer.copy.shown
                label: root._uriOffer.copy.label
                kind: "save"
                available: root._uriOffer.copy.available && root._uriOffer.copy.text !== ""
                onClicked: if (available) root._copy(root._uriOffer.copy.text)
            }
        }
        RowLayout {
            visible: root._uriOffer.anyway.shown
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 6
            Hint {
                text: root._uriOffer.anyway.hint
            }
            PrivilegedMark { need: "auth" }
            SmallButton {
                objectName: "connectivityAnyway"
                visible: root._uriOffer.anyway.button === "plain"
                label: root._uriOffer.anyway.label
                available: root._uriOffer.anyway.available
                onClicked: if (available) NetworkOverview.applyConnectivityUri(root._uriOffer.anyway.request)
            }
            DeleteButton {
                objectName: "connectivityAnywayAsking"
                visible: root._uriOffer.anyway.button === "ask"
                kind: "save"
                label: root._uriOffer.anyway.label
                confirmLabel: root._uriOffer.anyway.question
                available: root._uriOffer.anyway.available
                readonly property string subject: JSON.stringify(root._uriOffer.anyway.request)
                onSubjectChanged: asking = false
                onConfirmed: NetworkOverview.applyConnectivityUri(root._uriOffer.anyway.request)
            }
        }
        Hint {
            objectName: "connectivityHint"
            text: root._uriOffer.hint
        }

    }
}
