import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.singletons
import qs.singletons.network

// A saved profile's settings (System → Network → Wi-Fi or Ethernet → a profile → Edit
// connection): general, IPv4, IPv6, DNS, and the Wi-Fi's or the cable's own
// (docs/plans/network.md). Read once (NetworkProfiles.readSettings); Save sends only what
// changed, in one `nmcli connection modify` (NetworkRules.editorChanges); wrong fields
// are marked and keep Save off (NetworkRules.editorErrors). An active profile's changes
// apply when it connects again: "Save and reconnect" — then "Keep these settings?" for
// 20 s (NetworkProfiles.saveAndReconnect: kept there, so leaving the page does not drop
// it), and without an answer the old settings go back. What NetworkProfiles answers comes
// as signals (`saved`, `created`), never callbacks into this item, which may be gone.
Item {
    id: root

    property string uuid: ""
    // The profile is the one in use (its changes need a reconnect)
    property bool active: false
    // A new profile's settings (NetworkRules.hotspotTemplate) — then nothing is read, and
    // Save makes the profile (`created`, with its UUID)
    property var template: null
    readonly property bool _creating: template !== null
    signal closed()
    signal created(string uuid)

    // A hotspot: the computer's own network — its security and password here, no metered,
    // priority or IPv6, and its IPv4 always "Be the router"
    readonly property bool _hotspot: NetworkRules.isHotspot(_edited)
    // A WireGuard profile: its keys and peers here; IPv4 and IPv6 manual or off, no gateway
    readonly property bool _wireguard: (_edited?.wireguard ?? null) !== null

    // The public key of the private key in the form (`wg pubkey`), "" when there is none.
    // Worked out again when the key changes or `wg` turns out to be there; an answer for a
    // key no longer in the form is dropped.
    property string _publicKey: ""
    Timer {
        id: _publicKeyTimer
        interval: 300
        onTriggered: {
            const asked = root._privateKeyNow;
            if (!NetworkRules.isWireguardKey(asked)) {
                root._publicKey = "";
                return;
            }
            VpnManager.publicKeyOf(asked, key => {
                if (root?._alive && root._privateKeyNow === asked)
                    root._publicKey = key;
            });
        }
    }
    readonly property string _privateKeyNow: _edited?.wireguard?.privateKey ?? ""
    on_PrivateKeyNowChanged: _publicKeyTimer.restart()
    Connections {
        target: VpnManager
        function onWgAvailableChanged() {
            _publicKeyTimer.restart();
        }
    }
    // `wg` looked for once, when a WireGuard profile is open (VpnManager keeps the answer)
    on_WireguardChanged: if (_wireguard && !VpnManager.wgChecked)
        VpnManager.checkWg()

    function _setPeer(index, key, value) {
        const peers = JSON.parse(JSON.stringify(_edited.wireguard.peers));
        peers[index][key] = value;
        _set("wireguard.peers", peers);
    }

    function _copy(text) {
        Quickshell.clipboardText = text;
        Notifier.send("Public key copied", { body: text, urgency: "low", category: "x-qs-shell" });
    }

    property var _original: null
    property var _edited: null
    property bool _failed: false

    readonly property var _errors: _edited ? NetworkRules.editorErrors(_edited) : ({})
    readonly property bool _valid: Object.keys(_errors).length === 0
    readonly property var _changes: _original && _edited ? NetworkRules.editorChanges(_original, _edited, Quickshell.env("USER") ?? "") : []
    // The VPNs that come up with this network (VpnManager: the shell's setting, not the
    // profile's) — as read, and as picked; saved with the rest
    property var _vpnsOriginal: []
    property var _vpnsEdited: []
    readonly property bool _vpnsChanged: JSON.stringify(_vpnsOriginal.slice().sort()) !== JSON.stringify(_vpnsEdited.slice().sort())
    // A network a VPN can come up with: a Wi-Fi one joined, or a wired one
    readonly property bool _canHaveVpn: !_creating && _edited !== null && !_hotspot && !_wireguard
        && ((_edited.wifi ?? null) !== null || (_edited.ethernet ?? null) !== null)
    // Blocking traffic outside a VPN on this network (VpnLockdown; the shell's setting)
    property bool _lockOriginal: false
    property bool _lockEdited: false
    property var _lockToWrite: null
    readonly property bool _dirty: _changes.length > 0 || _vpnsChanged || _lockOriginal !== _lockEdited

    // "Keep these settings?": the changes to undo, seconds left
    // The create asked for, to know its answer (NetworkProfiles.created); 0 none
    property int _createToken: 0
    // Cleared when the item goes, so a read answered after that does nothing
    property bool _alive: true
    Component.onDestruction: _alive = false

    function _load() {
        _failed = false;
        if (_creating) {
            _original = template.wireguard ? NetworkRules.blankWireguard() : NetworkRules.blankWifi();
            _edited = JSON.parse(JSON.stringify(template));
            _form.active = false;
            _form.active = true;
            return;
        }
        NetworkProfiles.readSettings(uuid, settings => {
            if (!root?._alive)
                return;
            if (!settings) {
                root._failed = true;
                return;
            }
            root._original = settings;
            root._edited = JSON.parse(JSON.stringify(settings));
            // NetworkManager's VPNs there still are (one deleted would stay picked, unseen and
            // unremovable) and EVERY provider VPN stored, available or not — a not available
            // one shows as a removable pill (NetworkRules.editorVpnIds, unavailableVpnIds)
            root._vpnsOriginal = NetworkRules.editorVpnIds(VpnManager.vpnsWith(root.uuid), VpnManager.vpns);
            root._vpnsEdited = root._vpnsOriginal.slice();
            root._lockOriginal = VpnLockdown.isSetFor(root.uuid);
            root._lockEdited = root._lockOriginal;
            // The form made again: its text fields take their values when made
            _form.active = false;
            _form.active = true;
        });
    }

    Component.onCompleted: _load()

    // A change to one field: a fresh copy, so the bindings see it
    function _set(path, value) {
        const copy = JSON.parse(JSON.stringify(_edited));
        const keys = path.split(".");
        let target = copy;
        for (let i = 0; i < keys.length - 1; i++)
            target = target[keys[i]];
        target[keys[keys.length - 1]] = value;
        _edited = copy;
    }

    // A whole number typed, or `empty` for an empty field; -2 for anything else, which the
    // rules refuse (so the field is marked)
    function _number(text, empty) {
        const trimmed = String(text).trim();
        return trimmed === "" ? empty : /^\d+$/.test(trimmed) ? parseInt(trimmed) : -2;
    }

    function _list(text) {
        return String(text).split(/[\s,;]+/).filter(item => item !== "");
    }

    // The VPNs picked, written once the profile's own save went through (null: none to write)
    property var _vpnsToWrite: null

    function _save(reconnect) {
        // Never a list missing a provider VPN the user did not take out (NetworkRules.vpnsToWrite)
        _vpnsToWrite = _vpnsChanged ? NetworkRules.vpnsToWrite(VpnManager.vpnsWith(uuid), _vpnsOriginal, _vpnsEdited) : null;
        _lockToWrite = _lockOriginal !== _lockEdited ? _lockEdited : null;
        if (_creating)
            _createToken = NetworkProfiles.create(_edited, "Making " + _edited.name);
        else if (reconnect)
            NetworkProfiles.saveAndReconnect(uuid, _changes, _original, "Saving " + _original.name);
        else
            NetworkProfiles.save(uuid, _changes, "Saving " + _original.name);
    }

    Connections {
        target: NetworkProfiles
        function onSaved(savedUuid, ok) {
            if (savedUuid !== root.uuid || root._creating)
                return;
            if (ok && root._vpnsToWrite !== null)
                VpnManager.setVpnsWith(root.uuid, root._vpnsToWrite);
            if (ok && root._lockToWrite !== null)
                VpnLockdown.setFor(root.uuid, root._lockToWrite);
            root._vpnsToWrite = null;
            root._lockToWrite = null;
            // After a failure the form keeps what was typed
            if (ok)
                root._load();
        }
        function onCreated(token, createdUuid) {
            if (token === root._createToken && createdUuid !== "")
                root.created(createdUuid);
        }
    }

    // ── Small parts ──
    component Label: Text {
        Layout.topMargin: 6
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBody
        color: Theme.textPrimary
    }

    component Problem: Text {
        property string field: ""
        visible: (root._errors[field] ?? "") !== ""
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: root._errors[field] ?? ""
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.warning
    }

    // One of a few values, as pills. An option's `hint` says what it means: on hover, and
    // the picked one's under the pills — a tap cannot hover, so touch reads it there
    component Choice: ColumnLayout {
        id: _choice
        property var options: []
        property var value
        signal picked(var value)
        readonly property string _pickedHint: (options.find(option => option.value === value) ?? {}).hint ?? ""
        Layout.fillWidth: true
        spacing: 2
        Flow {
            Layout.fillWidth: true
            spacing: 4
            Repeater {
                model: ScriptModel { values: _choice.options }
                Pill {
                    required property var modelData
                    label: modelData.label
                    tooltip: modelData.hint ?? ""
                    fontSize: Theme.fontSizeBody
                    minimumHeight: 26
                    picked: modelData.value === _choice.value
                    onClicked: _choice.picked(modelData.value)
                }
            }
        }
        Hint {
            visible: text !== ""
            text: _choice._pickedHint
        }
    }

    // A text field written once from the settings, writing back as it is typed
    component Field: InputField {
        property string initial: ""
        property string field: ""
        Layout.fillWidth: true
        outlined: true
        problem: (root._errors[field] ?? "") !== ""
        input.inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
        Component.onCompleted: text = initial
    }

    // Save, and on the connection in use "Save and reconnect" — at the top and the bottom of
    // the page, so a long form need not be scrolled through to save it
    component SaveButtons: RowLayout {
        visible: root._edited !== null
        spacing: 8
        SmallButton {
            label: root._creating ? "Create" : "Save"
            kind: root.active ? "normal" : "save"
            available: (root._dirty || root._creating) && root._valid && !NetworkProfiles.busy && NetworkProfiles.pendingUndo === null
            tooltip: !root._valid ? "Fix the marked fields first" : root.active ? "Applies the next time it connects" : ""
            onClicked: root._save(false)
        }
        SmallButton {
            visible: root.active && !root._creating
            label: "Save and reconnect"
            kind: "save"
            // Only for the profile's own changes: the VPNs picked are the shell's, and a
            // reconnect for them would drop the network for nothing
            available: root._changes.length > 0 && root._valid && !NetworkProfiles.busy && !NetworkProfiles.connecting && NetworkProfiles.pendingUndo === null
            tooltip: !root._valid ? "Fix the marked fields first" : ""
            onClicked: root._save(true)
        }
    }

    // Which way traffic goes, for one family ("ipv4" | "ipv6"): only this network or the
    // internet too, the route's metric, and whether the connection needs an address of it
    component Routing: ColumnLayout {
        id: _routing
        property string family: "ipv4"
        readonly property var _config: root._edited[family]
        readonly property string _name: family === "ipv4" ? "IPv4" : "IPv6"
        Layout.fillWidth: true
        spacing: 4
        SwitchRow {
            Layout.topMargin: 6
            label: "Use only for its own network"
            hint: "Not for the internet: only addresses in this network go this way"
            checked: _routing._config.neverDefault
            onToggled: root._set(_routing.family + ".neverDefault", !checked)
        }
        Label { text: "Route metric" }
        Field {
            field: _routing.family + ".route-metric"
            initial: _routing._config.routeMetric >= 0 ? String(_routing._config.routeMetric) : ""
            placeholder: "Automatic"
            input.inputMethodHints: Qt.ImhDigitsOnly
            onTextEdited: root._set(_routing.family + ".routeMetric", root._number(text, -1))
        }
        Problem { field: _routing.family + ".route-metric" }
        Hint { text: "When several connections reach the internet, the lowest number wins. Automatic: 100 for a cable, 600 for Wi-Fi." }
        SwitchRow {
            Layout.topMargin: 6
            label: "Require " + _routing._name
            hint: "Off: the connection is up as long as the other family works"
            checked: !_routing._config.mayFail
            onToggled: root._set(_routing.family + ".mayFail", checked)
        }
    }

    readonly property var _macOptions: [
        { value: "", label: "Default", hint: "As NetworkManager is set up on this computer — usually the card's own address." },
        { value: "permanent", label: "The card's own", hint: "The address built into the network card." },
        { value: "random", label: "Random each time", hint: "A new address at every connection: the network cannot recognise this computer, but it may lose a reservation or a sign-in." },
        { value: "stable", label: "Stable per network", hint: "A made-up address, the same each time for this network and different on others: networks cannot follow this computer from one to another." }
    ]

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: _column.implicitHeight + 2 * Theme.settings.pageMargin
        flickableDirection: Flickable.VerticalFlick

        ColumnLayout {
            id: _column
            x: Theme.settings.pageMargin
            y: Theme.settings.pageMargin
            width: parent.width - 2 * Theme.settings.pageMargin
            spacing: 4

            // Back, with a question when changes would be lost
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                SmallButton {
                    visible: !root._dirty
                    label: "‹ Back"
                    onClicked: root.closed()
                }
                DeleteButton {
                    visible: root._dirty
                    label: "‹ Back"
                    // The plain Back's size, so the button does not shrink once something changes
                    fontSize: Theme.fontSizeBody
                    confirmLabel: "Discard changes?"
                    cancelTip: "Keep editing"
                    onConfirmed: root.closed()
                }
                Heading {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: root._creating ? (root.template?.wireguard ? "New WireGuard" : "New hotspot")
                        : root._original ? root._original.name : "Connection"
                }
                SaveButtons {}
            }

            // Keep these settings? (any profile's, while the countdown runs)
            KeepSettingsBar {
                Layout.fillWidth: true
                Layout.topMargin: 6
            }

            Text {
                visible: root._failed
                text: "This profile's settings could not be read."
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: Theme.warning
            }

            // The form, made once the settings are read (and again after a revert)
            Loader {
                id: _form
                Layout.fillWidth: true
                active: false
                sourceComponent: _formComponent
            }

            // Save
            RowLayout {
                visible: root._edited !== null
                Layout.fillWidth: true
                Layout.topMargin: 12
                spacing: 8
                Item { Layout.fillWidth: true }
                Text {
                    visible: !root._valid
                    text: "Fix the marked fields first."
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.warning
                }
                SaveButtons {}
            }
        }
    }

    // WireGuard's peers, each a box of fields matched to its peer by place: a peer added or
    // taken away changes the count, and the Repeater makes every box again from the peers
    Component {
        id: _peersComponent

        ColumnLayout {
            spacing: 8

            Repeater {
                // A count, not the live array: the boxes stay while their fields are typed in
                model: root._edited?.wireguard?.peers?.length ?? 0

                Rectangle {
                    id: _peer
                    required property int index
                    readonly property var _data: root._edited.wireguard.peers[index] ?? { publicKey: "", allowedIps: [], endpoint: "", presharedKey: "", keepalive: 0 }
                    readonly property bool _allTraffic: _data.allowedIps.includes("0.0.0.0/0") && _data.allowedIps.includes("::/0")
                    Layout.fillWidth: true
                    implicitHeight: _peerColumn.implicitHeight + 16
                    radius: Theme.settings.cardRadius
                    color: "transparent"
                    border.width: Theme.border.width
                    border.color: Theme.outline

                    ColumnLayout {
                        id: _peerColumn
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                Layout.topMargin: 0
                                Layout.fillWidth: true
                                text: "Peer " + (_peer.index + 1)
                            }
                            DeleteButton {
                                label: "Remove"
                                confirmLabel: "Remove?"
                                cancelTip: "Keep it"
                                onConfirmed: {
                                    const peers = JSON.parse(JSON.stringify(root._edited.wireguard.peers));
                                    peers.splice(_peer.index, 1);
                                    root._set("wireguard.peers", peers);
                                }
                            }
                        }
                        Label { text: "Public key" }
                        Field {
                            field: "wireguard.peers." + _peer.index + ".publicKey"
                            initial: _peer._data.publicKey
                            placeholder: "The server's, from the provider"
                            onTextEdited: root._setPeer(_peer.index, "publicKey", text.trim())
                        }
                        Problem { field: "wireguard.peers." + _peer.index + ".publicKey" }
                        Label { text: "Endpoint" }
                        Field {
                            field: "wireguard.peers." + _peer.index + ".endpoint"
                            initial: _peer._data.endpoint
                            placeholder: "vpn.example.com:51820"
                            onTextEdited: root._setPeer(_peer.index, "endpoint", text.trim())
                        }
                        Problem { field: "wireguard.peers." + _peer.index + ".endpoint" }
                        Label { text: "Allowed IPs" }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Field {
                                id: _allowedField
                                field: "wireguard.peers." + _peer.index + ".allowedIps"
                                initial: _peer._data.allowedIps.join(", ")
                                placeholder: "10.0.0.0/24"
                                onTextEdited: root._setPeer(_peer.index, "allowedIps", root._list(text))
                            }
                            SmallButton {
                                label: "All traffic"
                                checked: _peer._allTraffic
                                tooltip: "Every connection goes through the VPN (0.0.0.0/0 and ::/0)"
                                onClicked: {
                                    const all = ["0.0.0.0/0", "::/0"];
                                    root._setPeer(_peer.index, "allowedIps", all);
                                    _allowedField.text = all.join(", ");
                                }
                            }
                        }
                        Problem { field: "wireguard.peers." + _peer.index + ".allowedIps" }
                        Hint {
                            text: _peer._allTraffic ? "All traffic: every connection goes through this peer."
                                : "Only these networks go through this peer. Several: separate them with commas or spaces."
                        }
                        Label { text: "Preshared key" }
                        Field {
                            field: "wireguard.peers." + _peer.index + ".presharedKey"
                            initial: _peer._data.presharedKey
                            password: true
                            placeholder: "None (optional, the provider's)"
                            onTextEdited: root._setPeer(_peer.index, "presharedKey", text.trim())
                        }
                        Problem { field: "wireguard.peers." + _peer.index + ".presharedKey" }
                        Label { text: "Keepalive, in seconds" }
                        Field {
                            field: "wireguard.peers." + _peer.index + ".keepalive"
                            initial: _peer._data.keepalive > 0 ? String(_peer._data.keepalive) : ""
                            placeholder: "Off"
                            input.inputMethodHints: Qt.ImhDigitsOnly
                            onTextEdited: root._setPeer(_peer.index, "keepalive", root._number(text, 0))
                        }
                        Problem { field: "wireguard.peers." + _peer.index + ".keepalive" }
                        Hint { text: "Behind a router that forgets quiet connections: 25 keeps this one open." }
                    }
                }
            }
        }
    }

    Component {
        id: _formComponent

        ColumnLayout {
            spacing: 4

            // ── The medium's own: the profile's name, then what only a Wi-Fi or a cable has ──
            SectionTitle {
                text: root._hotspot ? "Hotspot" : root._wireguard ? "WireGuard" : root._edited.wifi !== null ? "Wi-Fi"
                    : root._edited.ethernet !== null ? "Ethernet" : "Profile"
            }
            Label { text: "Profile name" }
            Field {
                id: _profileName
                field: "connection.id"
                initial: root._edited.name
                onTextEdited: root._set("name", text)
            }
            Problem { field: "connection.id" }
            // Wi-Fi's own
            ColumnLayout {
                visible: root._edited.wifi !== null
                Layout.fillWidth: true
                spacing: 4
                Label { text: "Network name (SSID)" }
                Field {
                    field: "802-11-wireless.ssid"
                    initial: root._edited.wifi?.ssid ?? ""
                    // The profile's name follows the network's while the two are the same
                    onTextEdited: {
                        if (root._edited.name === root._edited.wifi.ssid) {
                            root._set("name", text);
                            _profileName.text = text;
                        }
                        root._set("wifi.ssid", text);
                    }
                }
                Problem { field: "802-11-wireless.ssid" }
                ColumnLayout {
                    visible: root._hotspot
                    Layout.fillWidth: true
                    spacing: 4
                    Label { text: "Security" }
                    Choice {
                        options: [
                            { value: "wpa-psk", label: "WPA2", hint: "A password; every device can join." },
                            { value: "sae", label: "WPA3", hint: "A password, better guarded; older devices cannot join." },
                            { value: "", label: "Open", hint: "No password: anyone in range can join and see the traffic." }
                        ]
                        value: root._edited.wifi?.security ?? ""
                        onPicked: value => root._set("wifi.security", value)
                    }
                    ColumnLayout {
                        visible: (root._edited.wifi?.security ?? "") !== ""
                        Layout.fillWidth: true
                        spacing: 4
                        Label { text: "Password" }
                        Field {
                            field: "802-11-wireless-security.psk"
                            initial: root._edited.wifi?.password ?? ""
                            password: true
                            // null: the saved one could not be read — kept unless one is typed
                            placeholder: root._original?.wifi?.password === null ? "Unchanged (it could not be read)" : ""
                            onTextEdited: root._set("wifi.password", text === "" && root._original?.wifi?.password === null ? null : text)
                        }
                        Problem { field: "802-11-wireless-security.psk" }
                    }
                }
                Label { text: "Band" }
                Choice {
                    options: [
                        { value: "", label: "Any", hint: "Whichever the access point offers best." },
                        { value: "a", label: "5 GHz", hint: "Only 5 GHz: faster, shorter range." },
                        { value: "bg", label: "2.4 GHz", hint: "Only 2.4 GHz: slower, reaches further through walls." }
                    ]
                    value: root._edited.wifi?.band ?? ""
                    onPicked: value => root._set("wifi.band", value)
                }
                Label { visible: !root._hotspot; text: "MAC address" }
                Choice {
                    visible: !root._hotspot
                    options: root._macOptions
                    value: root._edited.wifi?.mac ?? ""
                    onPicked: value => root._set("wifi.mac", value)
                }
                SwitchRow {
                    Layout.topMargin: 6
                    label: "Hidden network"
                    hint: root._hotspot ? "It does not broadcast its name: devices type it to join" : "It does not broadcast its name"
                    checked: root._edited.wifi?.hidden ?? false
                    onToggled: root._set("wifi.hidden", !checked)
                }
            }

            // WireGuard's own
            ColumnLayout {
                visible: root._wireguard
                Layout.fillWidth: true
                spacing: 4
                Label { text: "Interface" }
                Field {
                    field: "connection.interface-name"
                    initial: root._edited.wireguard?.iface ?? ""
                    onTextEdited: root._set("wireguard.iface", text.trim())
                }
                Problem { field: "connection.interface-name" }

                Label { text: "Private key" }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Field {
                        id: _privateKeyField
                        field: "wireguard.private-key"
                        initial: root._edited.wireguard?.privateKey ?? ""
                        password: true
                        // null: the saved one could not be read — kept unless one is given
                        placeholder: root._original?.wireguard?.privateKey === null ? "Unchanged (it could not be read)" : "Generate one, or paste the provider's"
                        onTextEdited: root._set("wireguard.privateKey",
                            text.trim() === "" && root._original?.wireguard?.privateKey === null ? null : text.trim())
                    }
                    SmallButton {
                        label: "Generate"
                        available: VpnManager.wgAvailable
                        tooltip: VpnManager.wgAvailable ? "A new key pair: give the server the public key below" : "wireguard-tools is not installed"
                        onClicked: VpnManager.generateKey(key => {
                            if (!root?._alive || key === "")
                                return;
                            root._set("wireguard.privateKey", key);
                            _privateKeyField.text = key;
                        })
                    }
                }
                Problem { field: "wireguard.private-key" }
                RowLayout {
                    visible: root._publicKey !== ""
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        text: "Public key"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        color: Theme.textPrimary
                    }
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideMiddle
                        text: root._publicKey
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        color: Theme.textSecondary
                    }
                    SmallButton {
                        label: "Copy"
                        tooltip: "The server needs it to let this computer in"
                        onClicked: root._copy(root._publicKey)
                    }
                }
                // wireguard-tools missing: named with what it is for, no install line
                Hint {
                    visible: VpnManager.wgChecked && !VpnManager.wgAvailable
                    text: "wireguard-tools is not installed: no key pair can be made or public key shown. A key from the VPN's provider can still be pasted."
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Label { text: "Listen port" }
                        Field {
                            field: "wireguard.listen-port"
                            initial: (root._edited.wireguard?.listenPort ?? 0) > 0 ? String(root._edited.wireguard.listenPort) : ""
                            placeholder: "Automatic"
                            input.inputMethodHints: Qt.ImhDigitsOnly
                            onTextEdited: root._set("wireguard.listenPort", root._number(text, 0))
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Label { text: "MTU" }
                        Field {
                            field: "wireguard.mtu"
                            initial: (root._edited.wireguard?.mtu ?? 0) > 0 ? String(root._edited.wireguard.mtu) : ""
                            placeholder: "Automatic"
                            input.inputMethodHints: Qt.ImhDigitsOnly
                            onTextEdited: root._set("wireguard.mtu", root._number(text, 0))
                        }
                    }
                }
                Problem { field: "wireguard.listen-port" }
                Problem { field: "wireguard.mtu" }

                // ── The peers: the servers it talks to ──
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 10
                    spacing: 8
                    Label {
                        Layout.fillWidth: true
                        text: "Peers"
                        font.bold: true
                    }
                    SmallButton {
                        visible: root._edited.wireguard?.peers !== null
                        label: "Add peer"
                        onClicked: {
                            const peers = JSON.parse(JSON.stringify(root._edited.wireguard.peers));
                            peers.push({ publicKey: "", allowedIps: [], endpoint: "", presharedKey: "", keepalive: 0 });
                            root._set("wireguard.peers", peers);
                        }
                    }
                }
                Hint {
                    visible: root._edited.wireguard?.peers === null
                    text: "The peers could not be read: they are kept as they are."
                }
                Loader {
                    Layout.fillWidth: true
                    sourceComponent: _peersComponent
                }
            }

            // The cable's own
            ColumnLayout {
                visible: root._edited.ethernet !== null
                Layout.fillWidth: true
                spacing: 4
                Label { text: "MAC address" }
                Choice {
                    options: root._macOptions
                    value: root._edited.ethernet?.mac ?? ""
                    onPicked: value => root._set("ethernet.mac", value)
                }
                Label { text: "MTU" }
                Field {
                    field: "802-3-ethernet.mtu"
                    initial: (root._edited.ethernet?.mtu ?? 0) > 0 ? String(root._edited.ethernet.mtu) : ""
                    placeholder: "Automatic"
                    input.inputMethodHints: Qt.ImhDigitsOnly
                    onTextEdited: root._set("ethernet.mtu", parseInt(text) || 0)
                }
                Problem { field: "802-3-ethernet.mtu" }
            }

            // ── Then what every kind of connection has, below a line ──
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 16
                implicitHeight: Theme.border.width
                color: Theme.outline
            }
            SectionTitle { text: "General" }
            SwitchRow {
                Layout.topMargin: 6
                label: root._hotspot ? "Start automatically" : "Connect automatically"
                hint: root._hotspot || root._wireguard ? "When the computer starts" : ""
                checked: root._edited.autoconnect
                onToggled: root._set("autoconnect", !checked)
            }
            RowLayout {
                visible: !root._hotspot && !root._wireguard
                Layout.fillWidth: true
                spacing: 8
                Label { Layout.fillWidth: true; text: "Priority" }
                SmallButton { label: "−"; available: root._edited.priority > -999; onClicked: root._set("priority", root._edited.priority - 1) }
                Text {
                    Layout.preferredWidth: 40
                    horizontalAlignment: Text.AlignHCenter
                    text: String(root._edited.priority)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textPrimary
                }
                SmallButton { label: "+"; available: root._edited.priority < 999; onClicked: root._set("priority", root._edited.priority + 1) }
            }
            Label { visible: !root._hotspot; text: "Metered" }
            Choice {
                visible: !root._hotspot
                options: [
                    { value: "auto", label: "Automatic", hint: "NetworkManager guesses: a phone's hotspot, for one, counts as metered." },
                    { value: "yes", label: "Yes", hint: "Paid by the amount of data: programs that ask are spared big downloads (updates, say)." },
                    { value: "no", label: "No", hint: "Not limited: programs download freely." }
                ]
                value: root._edited.metered
                onPicked: value => root._set("metered", value)
            }
            SwitchRow {
                Layout.topMargin: 6
                label: "Only for me"
                hint: "Other users of this computer cannot use it"
                checked: root._edited.onlyMe
                onToggled: root._set("onlyMe", !checked)
            }

            // The VPNs brought up with this network (the shell's doing: VpnManager)
            ColumnLayout {
                visible: root._canHaveVpn
                Layout.fillWidth: true
                spacing: 4
                Label { text: "Connect a VPN with it" }
                Flow {
                    visible: VpnManager.vpns.length > 0 || _unavailable.count > 0
                    Layout.fillWidth: true
                    spacing: 4
                    Repeater {
                        model: ScriptModel { values: VpnManager.vpns; objectProp: "uuid" }
                        Pill {
                            required property var modelData
                            label: modelData.name
                            tooltip: VpnManager.typeName(modelData)
                            fontSize: Theme.fontSizeBody
                            minimumHeight: 26
                            picked: root._vpnsEdited.includes(modelData.uuid)
                            onClicked: root._vpnsEdited = picked
                                ? root._vpnsEdited.filter(vpn => vpn !== modelData.uuid)
                                : root._vpnsEdited.concat([modelData.uuid])
                        }
                    }
                    // A provider's VPN picked for this network that is not available now
                    // (its provider away, not ready, logged out, the entry missing from a
                    // read: NetworkRules.unavailableVpnIds): kept, and taken out here (a
                    // click, then Save)
                    Repeater {
                        id: _unavailable
                        model: ScriptModel { values: NetworkRules.unavailableVpnIds(root._vpnsOriginal, VpnManager.vpns).map(vpn => ({ id: vpn })); objectProp: "id" }
                        Pill {
                            required property var modelData
                            label: VpnManager.labelOf(modelData.id)
                            tooltip: "Not available now (its provider not loaded, signed out or not listing it): kept until you take it out"
                            fontSize: Theme.fontSizeBody
                            minimumHeight: 26
                            picked: root._vpnsEdited.includes(modelData.id)
                            onClicked: root._vpnsEdited = picked
                                ? root._vpnsEdited.filter(vpn => vpn !== modelData.id)
                                : root._vpnsEdited.concat([modelData.id])
                        }
                    }
                }
                SwitchRow {
                    Layout.topMargin: 6
                    label: "Block traffic outside a VPN here"
                    hint: "On this network nothing gets out but through a VPN"
                    need: "auth"
                    checked: root._lockEdited
                    onToggled: root._lockEdited = !checked
                }
                // A provider's VPN picked here is not let through by the blocking
                Text {
                    readonly property var _kinds: root._lockEdited || VpnLockdown.always ? VpnManager.providerKindsAmong(root._vpnsEdited) : []
                    visible: _kinds.length > 0
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    // One kind known: by its name; else a plain sentence
                    text: _kinds.length === 1 && _kinds[0] !== "" ? _kinds[0] + " cannot connect while traffic is blocked."
                        : "A VPN picked here cannot connect while traffic is blocked."
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.warning
                }
                Hint {
                    text: VpnManager.vpns.length === 0 ? "No VPN set up yet: System → Network → VPN."
                        : "The VPNs picked connect and disconnect with this network, while the shell runs. A VPN that fails leaves the network up."
                }
            }

            // ── IPv4 ──
            SectionTitle { text: root._hotspot ? "Addresses" : "IPv4" }
            Hint {
                visible: root._hotspot
                text: "This computer hands addresses out to the devices that join, and is their gateway and DNS server."
            }
            Choice {
                visible: !root._hotspot
                options: [
                    { value: "auto", label: "Automatic (DHCP)", hint: "The network's router gives this computer its address, gateway and DNS servers. The usual choice." },
                    { value: "manual", label: "Manual", hint: "A fixed address you type in, with the gateway and DNS servers — for a network without DHCP, or a server that must keep its address." },
                    { value: "link-local", label: "Link-local only", hint: "Only a 169.254.x.x address, made up by this computer: it reaches devices on the same cable, nothing beyond. For two computers connected directly." },
                    { value: "shared", label: "Be the router", hint: "Devices connected here get their addresses from this computer, use it as their gateway and DNS server, and reach the internet through its other connection." },
                    { value: "disabled", label: "Off", hint: "No IPv4 on this connection." }
                ].filter(option => !root._wireguard || ["manual", "disabled", root._edited.ipv4.method].includes(option.value))
                    .map(option => root._wireguard && option.value === "manual"
                        ? Object.assign({}, option, { hint: "The address the VPN's provider gave this computer, with the DNS servers to use through it." })
                        : option)
                value: root._edited.ipv4.method
                onPicked: value => root._set("ipv4.method", value)
            }
            ColumnLayout {
                readonly property bool _router: root._edited.ipv4.method === "shared"
                id: _ipv4Own
                visible: root._edited.ipv4.method === "manual" || _router
                Layout.fillWidth: true
                spacing: 4
                Label { text: _ipv4Own._router ? "This computer's address" : "Addresses" }
                Field {
                    field: "ipv4.addresses"
                    initial: root._edited.ipv4.addresses.join(", ")
                    placeholder: _ipv4Own._router ? "Automatic (10.42.x.1/24)" : "192.168.1.50/24"
                    onTextEdited: root._set("ipv4.addresses", root._list(text))
                }
                Problem { field: "ipv4.addresses" }
                Hint {
                    text: _ipv4Own._router
                        ? "With its prefix, as 10.42.0.1/24: it sets the network handed out. The devices' gateway and DNS server."
                        : "Several: separate them with commas or spaces. Each with its prefix length, as 192.168.1.50/24."
                }
                ColumnLayout {
                    // A WireGuard tunnel has no gateway: its peers' allowed IPs are its routes
                    visible: !_ipv4Own._router && !root._wireguard
                    Layout.fillWidth: true
                    spacing: 4
                    Label { text: "Gateway" }
                    Field {
                        field: "ipv4.gateway"
                        initial: root._edited.ipv4.gateway
                        placeholder: "192.168.1.1"
                        onTextEdited: root._set("ipv4.gateway", text.trim())
                    }
                    Problem { field: "ipv4.gateway" }
                }
                ColumnLayout {
                    visible: _ipv4Own._router
                    Layout.fillWidth: true
                    spacing: 4
                    Label { text: "Addresses handed out" }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Field {
                            field: "ipv4.shared-dhcp-range"
                            initial: root._edited.ipv4.rangeStart
                            placeholder: "From"
                            onTextEdited: root._set("ipv4.rangeStart", text.trim())
                        }
                        Text {
                            text: "–"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            color: Theme.textSecondary
                        }
                        Field {
                            field: "ipv4.shared-dhcp-range"
                            initial: root._edited.ipv4.rangeEnd
                            placeholder: "To"
                            onTextEdited: root._set("ipv4.rangeEnd", text.trim())
                        }
                    }
                    Problem { field: "ipv4.shared-dhcp-range" }
                    Hint { text: "Empty: the whole network but this computer." }
                    Label { text: "Lease time, in minutes" }
                    Field {
                        field: "ipv4.shared-dhcp-lease-time"
                        initial: root._edited.ipv4.leaseTime > 0 ? String(Math.round(root._edited.ipv4.leaseTime / 60)) : ""
                        placeholder: "Default (an hour)"
                        input.inputMethodHints: Qt.ImhDigitsOnly
                        onTextEdited: {
                            const minutes = root._number(text, 0);
                            root._set("ipv4.leaseTime", minutes < 0 ? -1 : minutes * 60);
                        }
                    }
                    Problem { field: "ipv4.shared-dhcp-lease-time" }
                    Hint { text: "How long a device keeps its address before asking again." }
                }
            }
            ColumnLayout {
                visible: !["disabled", "shared"].includes(root._edited.ipv4.method)
                Layout.fillWidth: true
                spacing: 4
                Label { text: "DNS servers" }
                Field {
                    field: "ipv4.dns"
                    initial: root._edited.ipv4.dns.join(", ")
                    placeholder: root._edited.ipv4.method === "auto" ? "From DHCP" : "1.1.1.1, 9.9.9.9"
                    onTextEdited: root._set("ipv4.dns", root._list(text))
                }
                Problem { field: "ipv4.dns" }
                Hint { text: "Several: separate them with commas or spaces." }
                SwitchRow {
                    visible: root._edited.ipv4.method === "auto"
                    label: "Only these DNS servers"
                    hint: "Ignore the ones DHCP gives"
                    checked: root._edited.ipv4.ignoreAutoDns
                    onToggled: root._set("ipv4.ignoreAutoDns", !checked)
                }
                Label { text: "Search domains" }
                Field {
                    field: "ipv4.dns-search"
                    initial: root._edited.ipv4.dnsSearch.join(", ")
                    placeholder: "lan, example.com"
                    onTextEdited: root._set("ipv4.dnsSearch", root._list(text))
                }
                Hint {
                    text: "Names tried after a short one: with \"lan\", \"printer\" means printer.lan. Several: separate them with commas or spaces."
                        // "~" is NetworkManager's: this connection's DNS servers answer every name
                        + (root._edited.ipv4.dnsSearch.includes("~") ? " \"~\": every name is looked up through this connection's DNS servers." : "")
                }
            }
            Routing {
                visible: ["auto", "manual"].includes(root._edited.ipv4.method)
                family: "ipv4"
            }

            // ── IPv6 ── (a hotspot leaves it alone)
            ColumnLayout {
                visible: !root._hotspot
                Layout.fillWidth: true
                spacing: 4
                SectionTitle { text: "IPv6" }
                Choice {
                    options: [
                        { value: "auto", label: "Automatic", hint: "The address from the router's announcements (and DHCPv6 when it says so). The usual choice." },
                        { value: "dhcp", label: "DHCP only", hint: "The address only from a DHCPv6 server, not from the router's announcements." },
                        { value: "manual", label: "Manual", hint: "A fixed address you type in, with the gateway and DNS servers." },
                        { value: "link-local", label: "Link-local only", hint: "Only an fe80:: address: it reaches devices on the same cable, nothing beyond." },
                        { value: "ignore", label: "Ignore", hint: "NetworkManager leaves IPv6 alone: the system's own settings apply." },
                        { value: "disabled", label: "Off", hint: "No IPv6 on this connection." }
                    ].filter(option => !root._wireguard || ["manual", "disabled", root._edited.ipv6.method].includes(option.value))
                    value: root._edited.ipv6.method
                    onPicked: value => root._set("ipv6.method", value)
                }
                ColumnLayout {
                    visible: root._edited.ipv6.method === "manual"
                    Layout.fillWidth: true
                    spacing: 4
                    Label { text: "Addresses" }
                    Field {
                        field: "ipv6.addresses"
                        initial: root._edited.ipv6.addresses.join(", ")
                        placeholder: "2001:db8::50/64"
                        onTextEdited: root._set("ipv6.addresses", root._list(text))
                    }
                    Problem { field: "ipv6.addresses" }
                    Hint { text: "Several: separate them with commas or spaces. Each with its prefix length, as 2001:db8::50/64." }
                    Label { visible: !root._wireguard; text: "Gateway" }
                    Field {
                        visible: !root._wireguard
                        field: "ipv6.gateway"
                        initial: root._edited.ipv6.gateway
                        onTextEdited: root._set("ipv6.gateway", text.trim())
                    }
                    Problem { field: "ipv6.gateway" }
                }
                ColumnLayout {
                    visible: !["ignore", "disabled"].includes(root._edited.ipv6.method)
                    Layout.fillWidth: true
                    spacing: 4
                    Label { text: "DNS servers" }
                    Field {
                        field: "ipv6.dns"
                        initial: root._edited.ipv6.dns.join(", ")
                        placeholder: root._edited.ipv6.method === "auto" ? "From the network" : "2606:4700:4700::1111, 2620:fe::fe"
                        onTextEdited: root._set("ipv6.dns", root._list(text))
                    }
                    Problem { field: "ipv6.dns" }
                    Hint { text: "Several: separate them with commas or spaces." }
                    Routing {
                        visible: ["auto", "dhcp", "manual"].includes(root._edited.ipv6.method)
                        family: "ipv6"
                    }
                    Label { text: "Privacy" }
                    Choice {
                        options: [
                            { value: "-1", label: "Default", hint: "As the system is set up (often off)." },
                            { value: "0", label: "Off", hint: "One address, derived from the card or the network: sites may recognise this computer by it." },
                            { value: "1", label: "Temporary addresses", hint: "Extra addresses that change now and then, but connections go out from the fixed one." },
                            { value: "2", label: "Prefer temporary", hint: "Connections go out from addresses that change now and then, so sites cannot follow this computer by its address." }
                        ]
                        value: root._edited.ipv6.privacy
                        onPicked: value => root._set("ipv6.privacy", value)
                    }
                }
            }
        }
    }
}
