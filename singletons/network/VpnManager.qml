pragma Singleton

import Quickshell
import QtQuick
import qs.singletons
import qs.singletons.io
import qs.singletons.network

// The VPNs: NetworkManager's WireGuard and plugin VPN profiles (NetworkProfiles), by UUID —
// several may be up at once — and those of VPN providers (components/VpnProvider.qml: the
// Tailscale module's), by "<provider>:<entry>". NetworkManager's connect and disconnect
// through NetworkProfiles, so failures are reported the same way (a polkit prompt for want of
// rights, else a notification with nmcli's words); a provider's through the provider, its
// failures turned into the same kind of notification. The contract is
// components/VpnProvider.qml. With no provider registered everything here is NetworkManager's
// alone, exactly as before providers.
Singleton {
    id: root

    // NetworkManager's VPN profiles: those up first, then the most recently used
    readonly property var nmVpns: NetworkProfiles.profiles.filter(profile => profile.kind === "vpn")
        .sort((a, b) => (b.active - a.active) || (b.lastUsed - a.lastUsed))
    // [{ uuid, name, type ("wireguard" | "vpn" | "provider"), active, state, device, … }]:
    // those up first, then the most recently used (VpnProviderRules.mergedVpns). A provider's
    // has `uuid` "<provider>:<entry>", and provider, entryId, typeName, glyph, attention.
    readonly property var vpns: !VpnProviders.hasProviders ? nmVpns : VpnProviderRules.mergedVpns(nmVpns, VpnProviders.providerVpns)
    readonly property var activeVpns: vpns.filter(vpn => vpn.state === "activated")
    // The kind the bar and the popup show a glyph for: WireGuard's when every VPN up is one
    readonly property string activeType: activeVpns.length === 0 ? ""
        : activeVpns.every(vpn => vpn.type === "wireguard") ? "wireguard" : "vpn"
    // The glyph for them (VpnProviderRules.activeVpnGlyph): WireGuard's, a provider's own, the padlock
    readonly property string activeGlyph: VpnProviderRules.activeVpnGlyph(activeVpns)

    // NetworkManager's VPNs' { uuid: { service, server, servers, iface, interfaceName,
    // addresses, dns } } (NetworkRules.vpnDetails): read again with the profiles. The kill
    // switch takes its interfaces and servers from these alone (VpnLockdown).
    property var nmDetails: ({})
    // Those and the providers' entries' (their `detail`, VpnProviderRules.vpnProviderDetail),
    // by VPN id: what the views read
    readonly property var details: {
        if (!VpnProviders.hasProviders)
            return nmDetails;
        const all = Object.assign({}, nmDetails);
        for (const read of VpnProviders.reads)
            for (const entry of read.entries)
                all[VpnProviderRules.vpnId(read.providerId, entry.id)] = entry.detail;
        return all;
    }
    // The details read once (or none to read): what depends on them waits for it
    property bool detailsRead: false

    // A VPN's kind as a person names it: WireGuard, its plugin's (OpenVPN…), its provider's
    function typeName(vpn): string {
        if (vpn?.type === "provider")
            return vpn.typeName || "VPN";
        return vpn?.type === "wireguard" ? "WireGuard" : NetworkRules.vpnTypeName(details[vpn?.uuid]?.service ?? "");
    }

    // A VPN's glyph: WireGuard's, its provider's own, else the padlock
    function glyphOf(vpn): string {
        return VpnProviderRules.vpnGlyph(vpn);
    }

    // Read again when the VPNs or their states change (an interface and addresses come
    // with being up) and after the editor saved one — not on every network event: their
    // settings change only when edited
    readonly property string _vpnKey: nmVpns.map(vpn => vpn.uuid + ":" + vpn.state).sort().join(" ")
    on_VpnKeyChanged: _readDetails()
    Connections {
        target: NetworkProfiles
        function onSaved(uuid, ok) {
            if (root.nmVpns.some(vpn => vpn.uuid === uuid))
                root._readDetails();
        }
    }

    // The fields an older nmcli refused (NetworkRules.vpnDetailFields): a refused field fails
    // the whole query, so it is asked again without it — only when nmcli names the field,
    // never on an empty answer (which may be a VPN going away under the query)
    property var _rejectedFields: []
    property string _detailsProblem: ""

    function _readDetails() {
        if (nmVpns.length === 0) {
            nmDetails = {};
            detailsRead = NetworkProfiles.listRead;
            return;
        }
        const command = ["nmcli", "-t", "-f", NetworkRules.vpnDetailFields(_rejectedFields).join(","), "connection", "show"];
        for (const vpn of nmVpns)
            command.push("uuid", vpn.uuid);
        _details.command = command;
        _details.request();
    }

    // A run asked for while one is going on drops that one's answer (LatestQuery): a VPN's
    // state changed meanwhile, and what it read may be from before
    LatestQuery {
        id: _details
        onAnswered: (lines, result) => {
            const problem = NetworkRules.readProblem(result, "nmcli");
            const refused = problem === "" ? "" : NetworkRules.rejectedField(result.stderr);
            if (refused !== "" && NetworkRules.vpnDetailOptionalFields.includes(refused) && !root._rejectedFields.includes(refused)) {
                console.warn("VpnManager: this nmcli does not know " + refused + ": the VPNs' details are read without it");
                root._rejectedFields = root._rejectedFields.concat([refused]);
                root._readDetails();
                return;
            }
            if (problem !== root._detailsProblem)
                console.warn("VpnManager: the VPNs' details " + (problem === "" ? "are read again" : "could not be read: " + problem));
            root._detailsProblem = problem;
            root.nmDetails = NetworkRules.vpnDetails(Nmcli.records(lines, "connection.uuid"));
            root.detailsRead = true;
        }
    }

    // Lists of routes longer than ModuleRules.maxRoutes make a VPN's routes unknown in
    // Api.vpnsUp: said once, when that changes
    readonly property string _routesProblem: ModuleRules.vpnRoutesProblems(nmVpns, nmDetails).join("; ")
    on_RoutesProblemChanged: {
        if (_routesProblem !== "")
            console.warn("VpnManager: " + _routesProblem);
    }

    // The interfaces NetworkManager's VPN profiles are set to: what the kill switch lets
    // through (VpnLockdown)
    readonly property var nmInterfaceNames: Object.values(nmDetails).map(detail => detail.interfaceName).filter(name => name !== "")
    // Those and the ones providers name (a new WireGuard profile takes another)
    readonly property var interfaceNames: Object.values(details).map(detail => detail.interfaceName).filter(name => name !== "")

    // Every interface that is a VPN's: those set in the profiles and named by providers, and
    // those the VPNs run on now — what Api.localNetworks leaves out
    readonly property var vpnInterfaces: Array.from(new Set(interfaceNames.concat(vpns.map(vpn => interfaceOf(vpn)).filter(name => name !== ""))))
    // The addresses the VPNs up now hold (their details'): left out of Api.localNetworks
    // where a VPN runs on a physical device (IPsec puts its address on the Wi-Fi's or the
    // Ethernet's interface)
    readonly property var vpnAddresses: [].concat(...activeVpns.map(vpn => details[vpn.uuid]?.addresses ?? [])).filter(address => typeof address === "string")

    // The interface a VPN runs on while up: its tunnel's (a plugin VPN's profile names the
    // link under it; a provider's `detail.iface`), else its profile's device (WireGuard's own)
    function interfaceOf(vpn): string {
        return details[vpn?.uuid]?.iface || (vpn?.type === "wireguard" ? vpn.device : "") || "";
    }

    // ── VPN providers ── their registry, reads, slots and pages are VpnProviders'; these
    // forward to it for the views and components/VpnProvider.qml
    readonly property var slots: VpnProviders.slots
    function registerProvider(provider): bool { return VpnProviders.registerProvider(provider); }
    function unregisterProvider(id: string, provider): void { VpnProviders.unregisterProvider(id, provider); }
    function providerOf(vpnOrId) { return VpnProviders.providerOf(vpnOrId); }
    function ownExtrasOf(place: string, vpn) { return VpnProviders.ownExtrasOf(place, vpn); }
    function contextFor(slot: string, vpn, extra) { return VpnProviders.contextFor(slot, vpn, extra); }
    function pageOf(vpn): string { return VpnProviders.pageOf(vpn); }
    function settingsPageOf(vpn): string { return VpnProviders.settingsPageOf(vpn); }
    function openSettingsPageOf(vpn): bool { return VpnProviders.openSettingsPageOf(vpn); }

    // An operation runs for this VPN: its buttons wait — NetworkManager's while any
    // connecting runs (a second click before the list says "activating" would bring the
    // tunnel down and up again), a provider's while it says it is busy or the entry does
    function busyFor(vpn): bool {
        if (vpn?.type === "provider") {
            const read = VpnProviders.providerOf(vpn);
            if (read === null)
                return true;
            return read.busy || (read.entries.find(entry => entry.id === vpn.entryId)?.busy ?? false);
        }
        return NetworkProfiles.connecting;
    }

    // polkit's answer for changing it, for PrivilegedMark: a provider that cannot change
    // without an administrator "auth"; NetworkManager's "" (nothing marked, as before)
    function needFor(vpn): string {
        if (vpn?.type === "provider")
            return (VpnProviders.providerOf(vpn)?.canChange ?? true) ? "" : "auth";
        return "";
    }

    // The other VPNs up beside `vpn`, as a VPN's context gives them: { names } (otherVpnsUp —
    // two VPNs may compete for routes and DNS) and { rows } (otherVpns: the same VPNs as
    // Api.vpnsUp's rows, { name, type, provider, fullTunnel, setsDns, routes }: whether they
    // do compete)
    function othersUp(vpn) {
        const others = activeVpns.filter(other => other.uuid !== (vpn?.uuid ?? ""));
        return { names: others.map(other => other.name),
                 rows: ModuleRules.frozenRows(JSON.stringify(ModuleRules.apiVpnsUp(others, details))) };
    }

    // The provider VPNs in "VPN with a network" that are not among `vpns` now — not
    // available, whatever the reason (VpnWithNetworkRules.unavailableVpnIds, the one definition):
    // kept, shown as such in the network's editor, where the user can take them out
    readonly property var unavailableVpnIds: VpnWithNetworkRules.unavailableVpnIds(withNetworks, vpns)

    // A VPN by its id as a person reads it: its name, or for one not available its provider
    // and entry, said not to be available
    function labelOf(id: string): string {
        const vpn = vpns.find(entry => entry.uuid === id);
        if (vpn)
            return vpn.name;
        const parts = VpnProviderRules.vpnIdParts(id);
        return parts !== null && parts.provider !== "" ? parts.provider + " · " + parts.entry + " (not available)" : id;
    }

    // The kinds of the provider VPNs among `ids` ("Tailscale"; "" for one whose provider is
    // not here), each once: those the blocking of traffic outside a VPN does not let through
    // (VpnLockdown), for the views to say so where a VPN is
    // linked to a network that blocks
    function providerKindsAmong(ids): var {
        const kinds = [];
        for (const id of ids ?? []) {
            const parts = VpnProviderRules.vpnIdParts(id);
            if (parts === null || parts.provider === "")
                continue;
            const vpn = vpns.find(entry => entry.uuid === id);
            const kind = vpn !== undefined ? typeName(vpn) : "";
            if (!kinds.includes(kind))
                kinds.push(kind);
        }
        return kinds;
    }

    // Who asked for a connect or disconnect, as handed to the provider: { origin } — "user"
    // (a button: the provider may prompt, open a browser) or "network" ("VPN with a
    // network": it must never prompt nor open a browser — attention instead). Anything else
    // is the user's. A fresh object each call.
    function _request(request) {
        return { origin: request?.origin === "network" ? "network" : "user" };
    }

    // The provider's action for a VPN that needs the user (its attention's action): always
    // the user's doing (a button), so it takes no request
    function attend(id: string): void {
        VpnProviders.call(id, "attend", "Attending to");
    }

    // ── Connect or the provider's action ── the core never connects an entry that needs the
    // user (components/VpnProvider.qml): the popup's row and the VPN page's card ask here what
    // to offer, and connect() refuses such an entry whoever asks.

    // What needs the user ({ reason, action }: a provider's attention), else null
    function attentionOf(vpn) {
        return vpn?.attention ?? null;
    }

    // Connect may be offered and done: nothing needs the user first
    function canConnect(vpn): bool {
        return vpn !== null && vpn !== undefined && attentionOf(vpn) === null;
    }

    // Needing the user and off, with an action to offer: that action in place of Connect
    function attendsInstead(vpn): bool {
        const attention = attentionOf(vpn);
        return attention !== null && (attention.action ?? "") !== "" && !vpn.active;
    }

    // The label of the row's one button: the attention's action, the state's, Disconnect or
    // Connect; "" for none (needing the user with no action to offer, and off)
    function primaryLabel(vpn): string {
        if (attendsInstead(vpn))
            return attentionOf(vpn).action;
        if (!vpn?.active && !canConnect(vpn))
            return "";
        return vpn.state === "activating" ? "Connecting…"
            : vpn.state === "deactivating" ? "Disconnecting…"
            : vpn.state === "activated" ? "Disconnect" : "Connect";
    }

    // ── A VPN with a network ── wanted while a network it is linked to is up
    // (VpnWithNetworkRules.vpnWithNetworkPlan): brought up then, taken down when none is if the shell brought it
    // up — the shell's doing, as NetworkManager's connection.secondaries takes no WireGuard,
    // so only while the shell runs (started with it, shell.qml). A VPN that fails leaves the
    // network up (NetworkProfiles reports it). What the shell brought up is remembered in
    // Config, so a restart still takes it down with its network. Provider VPNs take part
    // too, by their ids; one that needs the user is not retried in a loop.
    // The setting through its text: Profiles.value is a new object on every profile fact
    // (battery, fullscreen…), and the mapping would make every reader run again
    readonly property string _withNetworksText: JSON.stringify(Profiles.value("system.vpnWithNetworks") ?? {})
    readonly property var withNetworks: JSON.parse(_withNetworksText)
    on_WithNetworksTextChanged: Qt.callLater(_followNetworks)

    // The providers' VPNs and states changed, one came or went: followed again
    readonly property string _providerKey: VpnProviders.reads.map(read => read.providerId + (read.ready ? "+" : "-")).join(" ") + "|"
        + VpnProviders.providerVpns.map(vpn => vpn.uuid + ":" + vpn.state + (vpn.attention ? ":!" : "")).join(" ")
    on_ProviderKeyChanged: Qt.callLater(_followNetworks)

    Connections {
        target: NetworkProfiles
        function onListReadChanged() {
            if (root.nmVpns.length === 0 && NetworkProfiles.listRead)
                root.detailsRead = true;
        }
        function onProfilesChanged() {
            // No VPN profile at all: nothing to read, but read (the blocking need not wait;
            // a VPN outside NetworkManager, wg-quick's, has its server set by hand there)
            if (root.nmVpns.length === 0 && NetworkProfiles.listRead)
                root.detailsRead = true;
            root._followNetworks();
        }
    }

    // Each pending connection checked again after its 90 s, without waiting for an event —
    // only those of VPNs there are (one of a provider that is away waits for it to return)
    readonly property bool _pendingKnown: {
        let pending = {};
        try {
            pending = JSON.parse(Config.network.vpnMemory || "{}").pending ?? {};
        } catch (error) {
            pending = {};
        }
        return Object.keys(pending).some(id => NetworkProfiles.profiles.some(profile => profile.uuid === id)
            || VpnProviders.providerVpns.some(vpn => vpn.uuid === id));
    }
    Timer {
        interval: 30000
        running: root._pendingKnown
        repeat: true
        onTriggered: root._followNetworks()
    }

    function _followNetworks() {
        if (!Config.ready)
            return;
        const profiles = NetworkProfiles.profiles;
        // Profiles that are gone leave the setting (none read yet: nothing is pruned); a
        // provider's VPN is never pruned (VpnWithNetworkRules.prunedVpnMapping)
        const pruned = VpnWithNetworkRules.prunedVpnMapping(withNetworks, profiles);
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
        const plan = VpnWithNetworkRules.vpnWithNetworkPlan(profiles, withNetworks, memory, Date.now(), VpnProviders.providerVpns);
        const text = JSON.stringify(plan.memory);
        if (text !== Config.network.vpnMemory)
            Config.network.vpnMemory = text;
        _applyPlan(plan);
    }

    // The plan's connects and disconnects, as the network's doing (origin "network": a
    // provider must not prompt or open a browser for them)
    function _applyPlan(plan) {
        for (const uuid of plan.connect ?? [])
            connect(uuid, { origin: "network" });
        for (const uuid of plan.disconnect ?? [])
            disconnect(uuid, { origin: "network" });
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
        _startFakeProvider();
    }

    // A stand-in provider for looking at the views by hand (tests/FakeVpnProvider.qml, with
    // its IPC target "fakevpn"): only when H2S_FAKE_VPN_PROVIDER=1 is in the shell's
    // environment (TestSeams.fakeVpnProvider), never otherwise
    property var _fakeProvider: null
    // By a file URL, as a module's files are loaded (the shell's scanner does not reach
    // tests/; such a file gets the same singletons)
    readonly property string fakeProviderUrl: "file://" + Quickshell.shellDir + "/tests/FakeVpnProvider.qml"

    function _startFakeProvider() {
        if (!TestSeams.fakeVpnProvider || _fakeProvider !== null)
            return;
        const component = Qt.createComponent(fakeProviderUrl);
        if (component.status !== Component.Ready) {
            console.warn("VpnManager: H2S_FAKE_VPN_PROVIDER is set, but the stand-in provider cannot be loaded:", component.errorString());
            return;
        }
        _fakeProvider = component.createObject(root, { ipc: true });
        console.warn("VpnManager: the stand-in VPN provider \"fake\" is loaded (H2S_FAKE_VPN_PROVIDER=1); IPC target \"fakevpn\"");
    }

    // The VPNs that come up with a network, by their ids
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
    // `.name` files: in every shipped distribution's directories for them (their facts'
    // networkManagerVpnDirectories, as one list: DistributionRules.unionOf), whichever system
    // this is. Read once a page asks, and once Distribution has read the facts.
    property var plugins: []
    property bool pluginsRead: false

    function readPlugins(): void {
        Distribution.whenReady(() => _plugins.request());
    }

    CommandQuery {
        id: _plugins
        // Each file with a line end after it: one without would glue the next file's
        // "[VPN Connection]" to its last line. The directories are arguments, never code
        command: ["sh", "-c", "for dir; do for file in \"$dir\"/*.name; do [ -f \"$file\" ] && cat \"$file\" && echo; done; done; true", "sh"]
            .concat(DistributionRules.unionOf(Distribution.shipped, "networkManagerVpnDirectories"))
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

    // By id (VpnProviderRules.vpnIdParts): a provider's ("<provider>:<entry>") through its
    // provider; anything else is NetworkManager's UUID, as before providers. An id that is
    // neither, or a provider VPN not here, does nothing; nor does connecting a VPN that needs
    // the user (canConnect). `request` { origin: "user" | "network" } says who asked
    // (default the user — a button); a provider gets it as connect's second argument.
    function connect(uuid: string, request): void {
        const parts = VpnProviderRules.vpnIdParts(uuid);
        if (parts === null) {
            console.warn("VpnManager: connect " + uuid + ": not a VPN id");
            return;
        }
        const vpn = vpns.find(entry => entry.uuid === uuid);
        if (vpn !== undefined && !canConnect(vpn)) {
            console.warn("VpnManager: connect " + uuid + ": it needs the user first");
            return;
        }
        if (parts.provider !== "") {
            VpnProviders.call(uuid, "connect", "Connecting", _request(request));
            return;
        }
        NetworkProfiles.activate(uuid, "");
    }

    function disconnect(uuid: string, request): void {
        const parts = VpnProviderRules.vpnIdParts(uuid);
        if (parts === null) {
            console.warn("VpnManager: disconnect " + uuid + ": not a VPN id");
            return;
        }
        if (parts.provider !== "") {
            VpnProviders.call(uuid, "disconnect", "Disconnecting", _request(request));
            return;
        }
        NetworkProfiles.deactivate(uuid, "Disconnecting " + NetworkProfiles.nameOf(uuid));
    }
}
