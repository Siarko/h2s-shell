import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import qs.components
import qs.singletons
import qs.singletons.network

// System → Network → VPN: each VPN profile as a card like a saved network's — its kind,
// whether it is up, its server; connect, disconnect, edit, delete; and, while up, its
// interface, address, speed and the data it moved. "New WireGuard" opens the editor on a
// fresh profile; "Import…" makes a profile from a VPN's file (a WireGuard .conf, an OpenVPN .ovpn, another plugin's), and the plugins missing are
// named with what they are for (notes/plans/network.md, VPN). By UUID (VpnManager). A VPN
// provider's entries (the Tailscale module's) get the same card, connected through the
// provider, with its extras and a link to its own page instead of the editor and delete.
Item {
    id: root

    anchors.fill: parent
    clip: true

    Component.onCompleted: {
        NetworkOverview.watch();
        VpnManager.readPlugins();
    }
    Component.onDestruction: NetworkOverview.unwatch()

    // The VPN open for its settings, by UUID
    property string _open: ""

    // The blocking script shown in full (and its polkit rule)
    property bool _showScript: false
    property bool _showRule: false
    readonly property string _nixosModule: VpnLockdown.nixosModule

    // A file picked to import, and the kind it is imported as ("" until chosen)
    property string _importPath: ""
    property string _importType: ""

    // The kinds a file can be imported as: WireGuard always, and each plugin there is
    readonly property var _importTypes: [{ value: "wireguard", label: "WireGuard" }]
        .concat(VpnManager.plugins.map(plugin => ({ value: plugin.name, label: NetworkRules.vpnTypeName(plugin.name) })))

    // The list of what can be imported: the kinds the shell knows (NetworkRules
    // .vpnImportKinds), each ready or not, then the other plugins installed
    readonly property var _importKinds: NetworkRules.vpnImportKinds.map(kind => {
        const ready = NetworkRules.canImport(kind.name, VpnManager.plugins);
        return {
            name: kind.name, label: kind.label, ready: ready,
            files: kind.files.map(ending => "." + ending).join(", "),
            note: kind.builtIn ? "Ready: NetworkManager's own."
                : ready ? "Ready: its plugin is installed."
                : !VpnManager.pluginsRead ? "Looking for its plugin…"
                : "Not now: needs NetworkManager's " + kind.label + " plugin."
        };
    }).concat(VpnManager.plugins.filter(plugin => !NetworkRules.vpnImportKinds.some(kind => kind.name === plugin.name)).map(plugin => ({
        name: plugin.name, label: NetworkRules.vpnTypeName(plugin.name), ready: true, files: "",
        note: "Its plugin is installed. If it reads a file, pick it under \"As\" when importing."
    })))

    function _pathOf(url) {
        return decodeURIComponent(String(url).replace(/^file:\/\//, ""));
    }

    function _stateText(vpn) {
        return vpn.state === "activated" ? "Connected" : vpn.state === "activating" ? "Connecting…"
            : vpn.state === "deactivating" ? "Disconnecting…" : "Off";
    }

    FileDialog {
        id: _fileDialog
        title: "A VPN's file"
        currentFolder: "file://" + (Quickshell.env("HOME") ?? "")
        nameFilters: ["VPN files (" + Array.from(new Set(NetworkRules.vpnImportKinds.reduce((all, kind) => all.concat(kind.files), [])))
            .map(ending => "*." + ending).join(" ") + ")", "All files (*)"]
        onAccepted: {
            root._importPath = root._pathOf(selectedFile);
            root._importType = NetworkRules.importTypeOf(root._importPath, VpnManager.plugins);
        }
    }

    Flickable {
        id: _page
        anchors.fill: parent
        // A provider's page that fails to load leaves this page shown
        visible: root._editing === "" && !root._newWireguard && !_providerPageFrame.shown
        contentWidth: width
        contentHeight: _column.implicitHeight + 2 * Theme.settings.pageMargin
        flickableDirection: Flickable.VerticalFlick

        ColumnLayout {
            id: _column
            x: Theme.settings.pageMargin
            y: Theme.settings.pageMargin
            width: _page.width - 2 * Theme.settings.pageMargin
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 8
                spacing: 8
                Heading {
                    Layout.fillWidth: true
                    text: "VPN"
                }
                SmallButton {
                    label: "New WireGuard"
                    tooltip: "Set up by hand: keys, address, server"
                    onClicked: root._newWireguard = true
                }
                SmallButton {
                    label: "Import…"
                    tooltip: "A WireGuard .conf, an OpenVPN .ovpn, or another plugin's file"
                    onClicked: _fileDialog.open()
                }
            }

            // A profile saved and reconnected, waiting for Keep (after leaving its editor)
            KeepSettingsBar {
                Layout.fillWidth: true
                Layout.bottomMargin: visible ? 10 : 0
            }

            // ── Importing a file: its kind, then Import ──
            Rectangle {
                visible: root._importPath !== ""
                Layout.fillWidth: true
                Layout.bottomMargin: 10
                implicitHeight: _importColumn.implicitHeight + 16
                radius: Theme.settings.cardRadius
                color: Theme.surface
                border.width: Theme.border.width
                border.color: Theme.accent

                ColumnLayout {
                    id: _importColumn
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                    spacing: 6
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideMiddle
                        text: "Import " + root._importPath.split("/").pop()
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        font.bold: true
                        color: Theme.textPrimary
                    }
                    Text {
                        text: "As"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        color: Theme.textPrimary
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 4
                        Repeater {
                            model: ScriptModel { values: root._importTypes; objectProp: "value" }
                            Pill {
                                required property var modelData
                                label: modelData.label
                                fontSize: Theme.fontSizeBody
                                size: "m"
                                picked: root._importType === modelData.value
                                onClicked: root._importType = modelData.value
                            }
                        }
                    }
                    Hint {
                        visible: root._importType === "wireguard"
                        text: "Imported off: connect it when you want it."
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Item { Layout.fillWidth: true }
                        SmallButton {
                            label: "Cancel"
                            onClicked: root._importPath = ""
                        }
                        SmallButton {
                            label: "Import"
                            kind: "save"
                            available: root._importType !== "" && !NetworkProfiles.busy
                            onClicked: {
                                VpnManager.importFile(root._importPath, root._importType);
                                root._importPath = "";
                            }
                        }
                    }
                }
            }

            // ── The VPNs ──
            Text {
                visible: VpnManager.vpns.length === 0
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "No VPN yet: import a file from the VPN's provider."
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textMuted
            }

            // Keyed by uuid: a card keeps its VPN (an open card, its fields) while the list
            // is read again
            KeyedModel { id: _vpnsModel; values: VpnManager.vpns; keyProp: "uuid" }
            Repeater {
                model: _vpnsModel.model

                NetworkProfileCard {
                    id: _vpn
                    required property string modelData
                    readonly property var vpn: _vpnsModel.byKey[modelData] ?? ({})
                    readonly property bool _wireguard: vpn.type === "wireguard"
                    // A VPN provider's (VpnManager; components/VpnProvider.qml): connected
                    // through it, no NetworkManager editor, no delete — its extras and page
                    readonly property bool _provided: vpn.type === "provider"
                    readonly property var _attention: VpnManager.attentionOf(vpn)
                    // The page states the limit whenever blocking is on, connected or not
                    readonly property string _lockdownNote: VpnLockdown.noteFor(vpn, true)
                    // Its own page: an entry of the settings window's list to go to, else one
                    // framed over this page (VpnManager.settingsPageOf, pageOf)
                    readonly property string _settingsPage: _provided ? VpnManager.settingsPageOf(vpn) : ""
                    readonly property string _pageUrl: _provided ? VpnManager.pageOf(vpn) : ""
                    readonly property bool _up: vpn.state === "activated"
                    readonly property string _server: VpnManager.details[vpn.uuid]?.server ?? ""
                    // The tunnel's own interface and addresses (a plugin VPN's profile names
                    // the link under it as its device)
                    readonly property var _details: VpnManager.details[vpn.uuid] ?? null
                    readonly property string _iface: VpnManager.interfaceOf(vpn)
                    Layout.fillWidth: true
                    Layout.bottomMargin: 6
                    profile: vpn
                    // A provider's status line ("Via <exit node>") beside the state
                    subtitle: [VpnManager.typeName(vpn), root._stateText(vpn), vpn.status ?? "", _server]
                        .filter(part => part !== "").join(" · ")
                    open: root._open === vpn.uuid
                    usable: true
                    stopsProfile: true
                    // NetworkManager brings a WireGuard profile up by itself; a plugin VPN
                    // only with a network — the shell's "Connect a VPN with it"
                    // (system.vpnWithNetworks, VpnManager)
                    showAutoconnect: _wireguard
                    autoconnectHint: "When the computer starts"
                    showPriority: false
                    forgetLabel: "Delete"
                    forgetAction: "Deleting"
                    editTooltip: "Its name, addresses, DNS and the rest"
                    external: _provided
                    busy: VpnManager.busyFor(vpn)
                    need: VpnManager.needFor(vpn)
                    // Needing the user: no Connect, its action (if any) beside the notice
                    canUse: VpnManager.canConnect(vpn)
                    notice: [_attention?.reason ?? "", _lockdownNote].filter(line => line !== "").join("\n")
                    noticeAction: _attention?.action ?? ""
                    onToggleRequested: root._open = open ? "" : vpn.uuid
                    onForgotten: root._open = ""
                    onEditRequested: root._editing = vpn.uuid
                    onUseRequested: VpnManager.connect(vpn.uuid)
                    onStopRequested: VpnManager.disconnect(vpn.uuid)
                    onNoticeActionRequested: VpnManager.attend(vpn.uuid)
                    // A provider's page: "Settings…", under the card's primary button
                    hasSettings: _settingsPage !== "" || _pageUrl !== ""
                    settingsTooltip: "Its own settings: " + VpnManager.typeName(vpn)
                    onSettingsRequested: {
                        if (!VpnManager.openSettingsPageOf(vpn))
                            root._providerPage = vpn.uuid;
                    }

                    // A provider's own: its extras (slot network.vpn.card)
                    VpnExtras {
                        Layout.fillWidth: true
                        slot: VpnManager.slots.card
                        vpn: _vpn.vpn
                        extra: ({ open: _vpn.open })
                    }

                    // The networks it comes up with (set in their editors)
                    DetailRow {
                        readonly property var _networks: VpnManager.networksWith(_vpn.vpn.uuid)
                        label: "Comes up with"
                        value: _networks.length > 0 ? _networks.map(uuid => NetworkProfiles.nameOf(uuid)).join(", ")
                            : "No network — pick it in a Wi-Fi or wired profile's editor"
                    }

                    // While up: where it runs and what it moves
                    LinkSpeed {
                        id: _speed
                        device: _vpn._up ? _vpn._iface : ""
                        active: _vpn._up && _vpn.open
                    }
                    ColumnLayout {
                        visible: _vpn._up
                        Layout.fillWidth: true
                        spacing: 4
                        DetailRow {
                            visible: value !== ""
                            label: "Interface"
                            value: _vpn._iface
                        }
                        DetailRow {
                            visible: value !== ""
                            label: "Address"
                            value: (_vpn._details?.addresses ?? []).join(", ")
                        }
                        DetailRow {
                            visible: value !== ""
                            label: "DNS"
                            value: (_vpn._details?.dns ?? []).join(", ")
                        }
                        DetailRow {
                            visible: _speed.rxTotal >= 0
                            label: "Data"
                            value: Format.bytes(_speed.rxTotal) + " received · " + Format.bytes(_speed.txTotal) + " sent"
                        }
                        LinkSpeedRow {
                            Layout.fillWidth: true
                            rxSpeed: _speed.rxSpeed
                            txSpeed: _speed.txSpeed
                            rxHistory: _speed.rxHistory
                            txHistory: _speed.txHistory
                        }
                    }
                }
            }

            // ── Only through the VPN (a kill switch; VpnLockdown) ──
            SectionTitle { text: "Only through the VPN" }
            SwitchRow {
                label: "Block traffic outside a VPN, always"
                hint: "Without a VPN up, nothing gets out"
                // Firewall rules: root's, asked for with the administrator's password
                need: "auth"
                checked: VpnLockdown.always
                onToggled: Profiles.setGlobal("system.vpnLockdownAlways", !checked)
            }
            // A provider's VPN set to come up with a network is not let through by it
            Text {
                readonly property var _kinds: VpnLockdown.always
                    ? VpnManager.providerKindsAmong(Object.values(VpnManager.withNetworks).reduce((all, ids) => all.concat(ids ?? []), [])) : []
                visible: _kinds.length > 0
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                // One kind known: by its name; else a plain sentence
                text: _kinds.length === 1 && _kinds[0] !== "" ? _kinds[0] + " cannot come up with a network while traffic is blocked."
                    : "A VPN set to come up with a network cannot connect while traffic is blocked."
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.warning
            }
            SwitchRow {
                label: "Allow the local network"
                hint: "Printers, the router, other computers on the same network"
                checked: VpnLockdown.allowLan
                onToggled: Profiles.setGlobal("system.vpnLockdownLan", !checked)
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 8
                Rectangle {
                    implicitWidth: 8
                    implicitHeight: 8
                    radius: 4
                    color: VpnLockdown.state === "on" ? Theme.success : VpnLockdown.state === "failed" ? Theme.warning : Theme.textMuted
                }
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: VpnLockdown.state === "on"
                            ? "Blocking: only the VPNs, their servers" + (VpnLockdown.allowLan ? ", the local network" : "") + " and joining a network get out."
                        : VpnLockdown.state === "asking" ? "Waiting for the administrator's password…"
                        : VpnLockdown.state === "working" ? "Switching…"
                        : VpnLockdown.state === "failed" ? VpnLockdown.failure
                        : VpnLockdown.wanted ? "About to block…" : "Not blocking."
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: VpnLockdown.state === "failed" ? Theme.warning : Theme.textPrimary
                }
                SmallButton {
                    // Whenever what is loaded differs from what is wanted — a refused
                    // password, either way — or to find the servers anew while blocking
                    visible: VpnLockdown.mismatched || (VpnLockdown.wanted && VpnLockdown.state === "on")
                    label: "Apply again"
                    tooltip: "Load the rules anew: the VPN servers' addresses found again"
                    onClicked: VpnLockdown.apply()
                }
            }
            // Rules an older script loaded, kept until applied again (VpnLockdown.staleRules)
            Text {
                // Password-free, they are switched on again by themselves: nothing to say
                visible: VpnLockdown.wanted && VpnLockdown.staleRules && VpnLockdown.state === "on" && !VpnLockdown.passwordFree
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "These rules are from an older script. Apply them again."
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.warning
            }
            // Servers of VPNs NetworkManager does not know (wg-quick's…): by address
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 6
                spacing: 4
                Text {
                    text: "Other VPN servers"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textPrimary
                }
                InputField {
                    id: _extraServers
                    Layout.fillWidth: true
                    outlined: true
                    placeholder: "None — addresses, for a VPN outside NetworkManager (wg-quick's)"
                    input.inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                    readonly property var _typed: text.split(/[\s,;]+/).filter(item => item !== "")
                    // As the script takes them: IPv4 without leading zeros, IPv6 without an IPv4 tail
                    problem: _typed.some(item => !NetworkRules.isLockdownAddress(item))
                    Component.onCompleted: text = VpnLockdown.extraServers.join(", ")
                    onEditingFinished: if (!problem) VpnLockdown.setExtraServers(_typed)
                }
                Hint {
                    text: _extraServers.problem ? "Addresses only — IPv4 without leading zeros, or IPv6 — separated by commas or spaces."
                        : "Let through to set up their tunnels. NetworkManager's VPNs need no entry here."
                }
            }
            Hint {
                Layout.topMargin: 8
                readonly property var _names: VpnLockdown.networks.filter(uuid => NetworkProfiles.profiles.some(profile => profile.uuid === uuid))
                    .map(uuid => NetworkProfiles.nameOf(uuid))
                text: (_names.length > 0 ? "Also on " + _names.join(", ") + ": " : "Or only on some networks (set in a Wi-Fi or wired profile's editor): ")
                    + "there it starts a few seconds after the network is up and the password is given; only \"always\" leaves no gap. "
                    + "Name lookups (DNS) still go outside the VPN. "
                    + (VpnLockdown.tooManyServers ? "Over " + NetworkRules.lockdownMostAddresses + " VPN server addresses: the rest are left out. " : "")
                    + "A network's sign-in page (a hotel's) cannot be used while blocking."
            }

            // ── Password-free blocking: the script, installed in the open ──
            SectionTitle { text: "Password-free blocking" }
            Hint {
                text: "The blocking changes the firewall as root: each switch asks for the administrator's password, again after every reboot. "
                    + "Installed, the script h2s-vpn-lockdown, which only switches this blocking, runs without it through a polkit rule for "
                    + VpnLockdown.user + " alone; the shell then also reloads the blocking if it is dropped (checked on network changes and every 5 minutes)."
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 6
                spacing: 8
                Rectangle {
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 5
                    implicitWidth: 8
                    implicitHeight: 8
                    radius: 4
                    color: VpnLockdown.helperState === "ready" ? Theme.success
                        : VpnLockdown.helperState === "none" ? Theme.textMuted : Theme.warning
                }
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: !VpnLockdown.checked ? "Looking…"
                        : VpnLockdown.helperState === "ready" ? "Installed (version " + VpnLockdown.installedVersion + ", " + VpnLockdown.installedAt
                            + ") with its polkit rule: no password needed."
                        : VpnLockdown.helperState === "outdated" ? "Older than the shell's (version " + VpnLockdown.installedVersion
                            + ", the shell's " + VpnLockdown.scriptVersion + "): install it again. Until then the password is asked for."
                        : VpnLockdown.helperState === "asks" ? "Installed, but a password was still asked for: its polkit rule does not apply."
                        : VpnLockdown.installedVersion > 0 ? "The script is there (" + VpnLockdown.installedAt + "), but not its polkit rule for "
                            + VpnLockdown.user + ": the password is asked for."
                        : "Not installed: each switch asks for the password."
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textPrimary
                }
            }
            Text {
                visible: VpnLockdown.installFailure !== ""
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: VpnLockdown.installFailure
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.warning
            }
            // Installing: one password, here — or, on NixOS, a module for its configuration
            RowLayout {
                visible: !VpnLockdown.isNixos
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 8
                SmallButton {
                    label: VpnLockdown.helperState === "none" ? "Install…" : "Install again…"
                    kind: VpnLockdown.helperState === "ready" ? "normal" : "save"
                    tooltip: "Copies the script to " + VpnLockdown.installFolder + " and its polkit rule to " + VpnLockdown.polkitRulePath
                        + " — asks for the password once"
                    onClicked: VpnLockdown.install()
                }
                DeleteButton {
                    visible: VpnLockdown.installedVersion > 0 || VpnLockdown.ruleInstalled
                    label: "Remove…"
                    fontSize: Theme.fontSizeBody
                    confirmLabel: "Remove the script and its rule?"
                    cancelTip: "Keep them"
                    onConfirmed: VpnLockdown.uninstall()
                }
                Item { Layout.fillWidth: true }
                SmallButton {
                    label: root._showScript ? "Hide the script" : "Show the script"
                    onClicked: root._showScript = !root._showScript
                }
                SmallButton {
                    label: root._showRule ? "Hide the rule" : "Show the rule"
                    onClicked: root._showRule = !root._showRule
                }
            }
            ColumnLayout {
                visible: VpnLockdown.isNixos
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 4
                Hint {
                    text: "Save this module as /etc/nixos/h2s-vpn-lockdown.nix, add it to imports and rebuild; it holds the script, nftables and the polkit rule. "
                        + "To remove it, take it out of imports and rebuild."
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    SmallButton {
                        label: "Copy the module"
                        onClicked: {
                            Quickshell.clipboardText = root._nixosModule;
                            Notifier.send("Module copied", { body: "Save it as /etc/nixos/h2s-vpn-lockdown.nix", urgency: "low", category: "x-qs-shell" });
                        }
                    }
                    SmallButton {
                        label: root._showScript ? "Hide the module" : "Show the module"
                        onClicked: root._showScript = !root._showScript
                    }
                    SmallButton {
                        label: "Check again"
                        onClicked: VpnLockdown.checkScript()
                    }
                }
            }
            // What would run as root, in full
            Rectangle {
                visible: root._showScript || root._showRule
                Layout.fillWidth: true
                Layout.topMargin: 6
                implicitHeight: _code.implicitHeight + 16
                radius: Theme.settings.cardRadius
                color: Theme.surface
                border.width: Theme.border.width
                border.color: Theme.outline
                TextEdit {
                    id: _code
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.WrapAnywhere
                    text: VpnLockdown.isNixos ? root._nixosModule
                        : (root._showScript ? VpnLockdown.scriptText : "") + (root._showScript && root._showRule ? "\n" : "")
                          + (root._showRule ? VpnLockdown.polkitRule : "")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.textSecondary
                }
            }

            // ── What can be imported ── each kind of file, and whether it can be now: a
            // plugin missing is named with what it is for — how to install one differs from
            // one system to another, so no command
            SectionTitle { text: "Files you can import" }
            Repeater {
                model: ScriptModel { values: root._importKinds; objectProp: "name" }
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.bottomMargin: 4
                    spacing: 10
                    Rectangle {
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: 5
                        implicitWidth: 8
                        implicitHeight: 8
                        radius: 4
                        color: modelData.ready ? Theme.success : Theme.textMuted
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            Layout.fillWidth: true
                            text: modelData.label + (modelData.files !== "" ? "  ·  " + modelData.files : "")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            color: Theme.textPrimary
                        }
                        Hint { text: modelData.note }
                    }
                }
            }
        }
    }

    // ── A provider's own page, over this one (slot network.vpn.page) ── by the VPN's id
    // ("" none), in the settings pages' frame (VpnProviderPageFrame: Back, title, scrolling).
    // Only for a provider whose page has no entry in the settings window's list: one that has
    // goes there instead (VpnManager.settingsPageOf)
    property string _providerPage: ""

    VpnProviderPageFrame {
        id: _providerPageFrame
        anchors.fill: parent
        vpnId: root._providerPage
        onClosed: root._providerPage = ""
    }

    // ── The connection editor, over the page, for the profile asked for ──
    // The profile being edited, by UUID ("" none); or a new WireGuard one being made
    property string _editing: ""
    property bool _newWireguard: false
    Loader {
        anchors.fill: parent
        active: root._editing !== "" || root._newWireguard
        sourceComponent: NetworkConnectionEditor {
            uuid: root._editing
            active: VpnManager.vpns.some(vpn => vpn.uuid === root._editing && vpn.active)
            // Read once, when the editor is made
            template: root._newWireguard ? NetworkRules.wireguardTemplate(VpnManager.interfaceNames) : null
            onClosed: {
                root._editing = "";
                root._newWireguard = false;
            }
            onCreated: uuid => {
                root._newWireguard = false;
                root._open = uuid;
            }
        }
    }
}
