pragma Singleton

import Quickshell
import QtQuick
import qs.singletons
import qs.singletons.io
import qs.singletons.network

// The VPNs: NetworkManager's WireGuard and plugin VPN profiles (NetworkProfiles), by UUID —
// several may be up at once. Connecting and disconnecting go through NetworkProfiles, so
// failures are reported the same way (a polkit prompt for want of rights, else a
// notification with nmcli's words).
Singleton {
    id: root

    // [{ uuid, name, type ("wireguard" | "vpn"), active, state, device, … }]: those up
    // first, then the most recently used
    readonly property var vpns: NetworkProfiles.profiles.filter(profile => profile.kind === "vpn")
        .sort((a, b) => (b.active - a.active) || (b.lastUsed - a.lastUsed))
    readonly property var activeVpns: vpns.filter(vpn => vpn.state === "activated")
    // The kind the bar and the popup show a glyph for: WireGuard's when every VPN up is one
    readonly property string activeType: activeVpns.length === 0 ? ""
        : activeVpns.every(vpn => vpn.type === "wireguard") ? "wireguard" : "vpn"

    // { uuid: { service, server } } (NetworkRules.vpnDetails): read again with the profiles
    property var details: ({})
    // The details read once (or none to read): what depends on them waits for it
    property bool detailsRead: false

    // A VPN's kind as a person names it: WireGuard, or its plugin's (OpenVPN…)
    function typeName(vpn): string {
        return vpn?.type === "wireguard" ? "WireGuard" : NetworkRules.vpnTypeName(details[vpn?.uuid]?.service ?? "");
    }

    // Read again when the VPNs or their states change (an interface and addresses come
    // with being up) and after the editor saved one — not on every network event: their
    // settings change only when edited
    readonly property string _vpnKey: vpns.map(vpn => vpn.uuid + ":" + vpn.state).sort().join(" ")
    on_VpnKeyChanged: _readDetails()
    Connections {
        target: NetworkProfiles
        function onSaved(uuid, ok) {
            if (root.vpns.some(vpn => vpn.uuid === uuid))
                root._readDetails();
        }
    }

    // nmcli before wireguard.peers existed refuses the field, and the whole query with it:
    // asked again without it
    property bool _withPeers: true

    function _readDetails() {
        if (vpns.length === 0) {
            details = {};
            detailsRead = NetworkProfiles.listRead;
            return;
        }
        const fields = ["connection.uuid", "connection.interface-name", "vpn.service-type", "vpn.data"].concat(_withPeers ? ["wireguard.peers"] : [])
            .concat(["GENERAL.IP-IFACE", "IP4.ADDRESS", "IP6.ADDRESS", "IP4.DNS", "IP6.DNS"]);
        const command = ["nmcli", "-t", "-f", fields.join(","), "connection", "show"];
        for (const vpn of vpns)
            command.push("uuid", vpn.uuid);
        _details.command = command;
        _details.request();
    }

    CommandQuery {
        id: _details
        onDone: lines => {
            if (lines.length === 0 && root.vpns.length > 0 && root._withPeers) {
                root._withPeers = false;
                root._readDetails();
                return;
            }
            root.details = NetworkRules.vpnDetails(Nmcli.records(lines, "connection.uuid"));
            root.detailsRead = true;
        }
    }

    // The interfaces the VPN profiles are set to (a new WireGuard one takes another)
    readonly property var interfaceNames: Object.values(details).map(detail => detail.interfaceName).filter(name => name !== "")

    // The interface a VPN runs on while up: its tunnel's (a plugin VPN's profile names the
    // link under it), else its profile's device (WireGuard's own)
    function interfaceOf(vpn): string {
        return details[vpn?.uuid]?.iface || (vpn?.type === "wireguard" ? vpn.device : "") || "";
    }

    // ── A VPN with a network ── wanted while a network it is linked to is up (NetworkRules
    // .vpnWithNetworkPlan): brought up then, taken down when none is if the shell brought it
    // up — the shell's doing, as NetworkManager's connection.secondaries takes no WireGuard,
    // so only while the shell runs (started with it, shell.qml). A VPN that fails leaves the
    // network up (NetworkProfiles reports it). What the shell brought up is remembered in
    // Config, so a restart still takes it down with its network.
    // The setting through its text: Profiles.value is a new object on every profile fact
    // (battery, fullscreen…), and the mapping would make every reader run again
    readonly property string _withNetworksText: JSON.stringify(Profiles.value("system.vpnWithNetworks") ?? {})
    readonly property var withNetworks: JSON.parse(_withNetworksText)
    on_WithNetworksTextChanged: Qt.callLater(_followNetworks)

    Connections {
        target: NetworkProfiles
        function onListReadChanged() {
            if (root.vpns.length === 0 && NetworkProfiles.listRead)
                root.detailsRead = true;
        }
        function onProfilesChanged() {
            // No VPN profile at all: nothing to read, but read (the blocking need not wait;
            // a VPN outside NetworkManager, wg-quick's, has its server set by hand there)
            if (root.vpns.length === 0 && NetworkProfiles.listRead)
                root.detailsRead = true;
            root._followNetworks();
        }
    }

    // Each pending connection checked again after its 90 s, without waiting for an event
    Timer {
        interval: 30000
        running: Object.keys(JSON.parse(Config.network.vpnMemory || "{}").pending ?? {}).length > 0
        repeat: true
        onTriggered: root._followNetworks()
    }

    function _followNetworks() {
        if (!Config.ready)
            return;
        const profiles = NetworkProfiles.profiles;
        // Profiles that are gone leave the setting (none read yet: nothing is pruned)
        const pruned = NetworkRules.prunedVpnMapping(withNetworks, profiles);
        if (JSON.stringify(pruned) !== _withNetworksText) {
            Profiles.setGlobal("system.vpnWithNetworks", pruned);
            return;
        }
        let memory = {};
        try {
            memory = JSON.parse(Config.network.vpnMemory || "{}");
        } catch (error) {
            memory = {};
        }
        const plan = NetworkRules.vpnWithNetworkPlan(profiles, withNetworks, memory, Date.now());
        const text = JSON.stringify(plan.memory);
        if (text !== Config.network.vpnMemory)
            Config.network.vpnMemory = text;
        for (const uuid of plan.connect)
            connect(uuid);
        for (const uuid of plan.disconnect)
            disconnect(uuid);
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready)
                root._followNetworks();
        }
    }

    // Started with the shell (shell.qml), not with the first thing that shows a VPN
    function start(): void {
        _followNetworks();
    }

    // The VPNs that come up with a network, by their UUIDs
    function vpnsWith(networkUuid: string): var {
        return withNetworks[networkUuid] ?? [];
    }

    // The networks a VPN comes up with (only profiles there are)
    function networksWith(vpnUuid: string): var {
        return Object.keys(withNetworks).filter(network => (withNetworks[network] ?? []).includes(vpnUuid)
            && NetworkProfiles.profiles.some(profile => profile.uuid === network));
    }

    function setVpnsWith(networkUuid: string, vpnUuids): void {
        const mapping = Object.assign({}, withNetworks);
        if (vpnUuids.length === 0)
            delete mapping[networkUuid];
        else
            mapping[networkUuid] = vpnUuids.slice();
        Profiles.setGlobal("system.vpnWithNetworks", mapping);
    }

    // ── WireGuard's keys ── made and turned into public ones by `wg` (wireguard-tools)
    // when it is there: NetworkManager makes none, and an own X25519 could hide a weak key
    // behind a randomness bug. Without it a key is pasted (the provider's), and no public
    // key is shown. The private key goes in on `wg pubkey`'s input, never its command line.
    property bool wgAvailable: false
    property bool wgChecked: false

    function checkWg(): void {
        _wgCheck.request();
    }

    CommandQuery {
        id: _wgCheck
        command: ["sh", "-c", "command -v wg"]
        onDone: lines => {
            root.wgAvailable = lines.length > 0;
            root.wgChecked = true;
        }
    }

    CommandAction {
        id: _keys
    }

    // A new private key, handed to `done(key)` ("" when it could not be made)
    function generateKey(done): void {
        _keys.run(["wg", "genkey"], result => done(result.ok ? (result.lines[0] ?? "").trim() : ""));
    }

    // The public key of `privateKey`, handed to `done(key)` ("" when it cannot be had)
    function publicKeyOf(privateKey: string, done): void {
        if (!wgAvailable || !NetworkRules.isWireguardKey(privateKey)) {
            done("");
            return;
        }
        _keys.run(["sh", "-c", 'printf "%s" "$H2S_KEY" | wg pubkey'], result => done(result.ok ? (result.lines[0] ?? "").trim() : ""),
            { H2S_KEY: privateKey });
    }

    // ── Plugins ── the VPN plugins NetworkManager has ([{ name, service }]), from their
    // `.name` files: where Arch, NixOS and others put them. Read once a page asks.
    property var plugins: []
    property bool pluginsRead: false

    function readPlugins(): void {
        _plugins.request();
    }

    CommandQuery {
        id: _plugins
        // Each file with a line end after it: one without would glue the next file's
        // "[VPN Connection]" to its last line
        command: ["sh", "-c", "for file in /usr/lib/NetworkManager/VPN/*.name /etc/NetworkManager/VPN/*.name "
            + "/run/current-system/sw/lib/NetworkManager/VPN/*.name; do [ -f \"$file\" ] && cat \"$file\" && echo; done; true"]
        onDone: lines => {
            root.plugins = NetworkRules.vpnPlugins(lines.join("\n"));
            root.pluginsRead = true;
        }
    }

    function hasPlugin(name: string): bool {
        return plugins.some(plugin => plugin.name === name);
    }

    // A file made into a profile (`nmcli connection import type <type> file <path>`):
    // "wireguard" for a WireGuard .conf, else a plugin's name
    function importFile(path: string, type: string): void {
        NetworkProfiles.importFile(path, type);
    }

    function connect(uuid: string): void {
        NetworkProfiles.activate(uuid, "");
    }

    function disconnect(uuid: string): void {
        NetworkProfiles.deactivate(uuid, "Disconnecting " + NetworkProfiles.nameOf(uuid));
    }
}
