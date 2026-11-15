pragma Singleton

import Quickshell
import QtQuick
import qs.singletons
import qs.singletons.io
import qs.singletons.network

// The VPNs: NetworkManager's WireGuard and plugin VPN profiles (NetworkProfiles), by UUID —
// several may be up at once — and those of VPN providers (components/VpnProvider.qml: the
// Tailscale module's), by "<provider>:<entry>". NetworkManager's connect and disconnect
// through NetworkProfiles, so failures are reported the same way (a polkit prompt for want
// of rights, else a notification with nmcli's words); a provider's through the provider,
// its failures turned into the same kind of notification. The contract is in docs/plans
// /tailscale.md §3. With no provider registered everything here is NetworkManager's alone,
// exactly as before providers.
Singleton {
    id: root

    // NetworkManager's VPN profiles: those up first, then the most recently used
    readonly property var nmVpns: NetworkProfiles.profiles.filter(profile => profile.kind === "vpn")
        .sort((a, b) => (b.active - a.active) || (b.lastUsed - a.lastUsed))
    // [{ uuid, name, type ("wireguard" | "vpn" | "provider"), active, state, device, … }]:
    // those up first, then the most recently used (NetworkRules.mergedVpns). A provider's
    // has `uuid` "<provider>:<entry>", and provider, entryId, typeName, glyph, attention.
    readonly property var vpns: _providers.length === 0 ? nmVpns : NetworkRules.mergedVpns(nmVpns, providerVpns)
    readonly property var activeVpns: vpns.filter(vpn => vpn.state === "activated")
    // The kind the bar and the popup show a glyph for: WireGuard's when every VPN up is one
    readonly property string activeType: activeVpns.length === 0 ? ""
        : activeVpns.every(vpn => vpn.type === "wireguard") ? "wireguard" : "vpn"
    // The glyph for them (NetworkRules.activeVpnGlyph): WireGuard's, a provider's own, the padlock
    readonly property string activeGlyph: NetworkRules.activeVpnGlyph(activeVpns)

    // NetworkManager's VPNs' { uuid: { service, server, servers, iface, interfaceName,
    // addresses, dns } } (NetworkRules.vpnDetails): read again with the profiles. The kill
    // switch takes its interfaces and servers from these alone (VpnLockdown).
    property var nmDetails: ({})
    // Those and the providers' entries' (their `detail`, NetworkRules.vpnProviderDetail),
    // by VPN id: what the views read
    readonly property var details: {
        if (_providers.length === 0)
            return nmDetails;
        const all = Object.assign({}, nmDetails);
        for (const read of _providerReads)
            for (const entry of read.entries)
                all[NetworkRules.vpnId(read.providerId, entry.id)] = entry.detail;
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
        return NetworkRules.vpnGlyph(vpn);
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

    // nmcli before wireguard.peers existed refuses the field, and the whole query with it:
    // asked again without it
    property bool _withPeers: true

    function _readDetails() {
        if (nmVpns.length === 0) {
            nmDetails = {};
            detailsRead = NetworkProfiles.listRead;
            return;
        }
        const fields = ["connection.uuid", "connection.interface-name", "vpn.service-type", "vpn.data"].concat(_withPeers ? ["wireguard.peers"] : [])
            .concat(["GENERAL.IP-IFACE", "IP4.ADDRESS", "IP6.ADDRESS", "IP4.DNS", "IP6.DNS"]);
        const command = ["nmcli", "-t", "-f", fields.join(","), "connection", "show"];
        for (const vpn of nmVpns)
            command.push("uuid", vpn.uuid);
        _details.command = command;
        _details.request();
    }

    CommandQuery {
        id: _details
        onDone: lines => {
            if (lines.length === 0 && root.nmVpns.length > 0 && root._withPeers) {
                root._withPeers = false;
                root._readDetails();
                return;
            }
            root.nmDetails = NetworkRules.vpnDetails(Nmcli.records(lines, "connection.uuid"));
            root.detailsRead = true;
        }
    }

    // The interfaces NetworkManager's VPN profiles are set to: what the kill switch lets
    // through (VpnLockdown)
    readonly property var nmInterfaceNames: Object.values(nmDetails).map(detail => detail.interfaceName).filter(name => name !== "")
    // Those and the ones providers name (a new WireGuard profile takes another)
    readonly property var interfaceNames: Object.values(details).map(detail => detail.interfaceName).filter(name => name !== "")

    // The interface a VPN runs on while up: its tunnel's (a plugin VPN's profile names the
    // link under it; a provider's `detail.iface`), else its profile's device (WireGuard's own)
    function interfaceOf(vpn): string {
        return details[vpn?.uuid]?.iface || (vpn?.type === "wireguard" ? vpn.device : "") || "";
    }

    // ── VPN providers ── objects registered here (components/VpnProvider.qml registers
    // itself), each read through NetworkRules.vpnProviderEntries: what is wrong is dropped
    // and logged, never shown. A provider destroyed while registered (a module disabled)
    // reads as gone and is dropped; a second one with a taken id is refused.

    // [{ id, object, handler }] in the order registered
    property var _providers: []

    // The slots a provider fills, by name (the module host's slot names, modules.md §3a; in
    // ModuleRules.slotTable since module API 1.1). A module's provider (providerId = its
    // module id) fills them through its manifest's `slots`; a provider that is no module's
    // (the stand-in) hands its Components over itself (rowExtras, cardExtras, pageUrl) —
    // extrasFor and pageOf ask the module host first, then the provider.
    //   network.vpn.row  — under the VPN's row in the network popup; context { slot, vpnId,
    //                      entryId, vpn, provider, otherVpnsUp }
    //   network.vpn.card — on the VPN's card in Settings → System → Network → VPN, while the
    //                      card is open; context { slot, vpnId, entryId, vpn, provider,
    //                      otherVpnsUp, open }
    //   network.vpn.page — a page of the provider's own, opened over the VPN page from the
    //                      card, in the settings pages' frame (title, Back, scrolling) — only
    //                      when the provider has no settingsPage the settings window knows
    //                      (settingsPageOf, pageOf); context { slot, vpnId, entryId, vpn, provider, otherVpnsUp, close }
    //   (contextFor makes them)
    readonly property var slots: ({ row: "network.vpn.row", card: "network.vpn.card", page: "network.vpn.page" })

    // Takes `provider` (a VpnProvider, or an object of its shape); false when refused: no
    // valid providerId, or the id taken by another provider still there
    function registerProvider(provider): bool {
        let id;
        try {
            id = provider?.providerId;
        } catch (error) {
            id = undefined;
        }
        if (!NetworkRules.isVpnProviderId(id)) {
            console.warn("VpnManager: a VPN provider refused: its providerId " + JSON.stringify(String(id)).slice(0, 60)
                + " is not a lower-case letter and up to 31 of a-z 0-9 - _");
            return false;
        }
        const live = _providers.filter(entry => _alive(entry));
        if (live.some(entry => entry.object === provider))
            return true;
        if (live.some(entry => entry.id === id)) {
            console.warn("VpnManager: a second VPN provider \"" + id + "\" refused: the id is taken");
            return false;
        }
        for (const gone of _providers.filter(entry => !live.includes(entry)))
            _disconnectHandler(gone);
        const handler = (entryId, what, reason) => root._providerFailed(id, entryId, what, reason);
        try {
            if (typeof provider.failed?.connect === "function")
                provider.failed.connect(handler);
        } catch (error) {
            console.warn("VpnManager: VPN provider \"" + id + "\": its failed signal cannot be connected:", error);
        }
        _providers = live.concat([{ id: id, object: provider, handler: handler }]);
        return true;
    }

    // Lets the provider `id` go; with `provider` given, only if it is that object (a
    // refused duplicate going away must not take the registered one with it)
    function unregisterProvider(id: string, provider): void {
        const leaving = _providers.filter(entry => entry.id === id && (provider === undefined || provider === null || entry.object === provider));
        if (leaving.length === 0)
            return;
        leaving.forEach(entry => _disconnectHandler(entry));
        _providers = _providers.filter(entry => !leaving.includes(entry));
    }

    function _disconnectHandler(entry) {
        try {
            if (typeof entry.object?.failed?.disconnect === "function")
                entry.object.failed.disconnect(entry.handler);
        } catch (error) {
            // Destroyed: its connections went with it
        }
    }

    // Still the object that registered under that id (a destroyed one reads no id)
    function _alive(entry) {
        try {
            return entry.object !== null && entry.object !== undefined && entry.object.providerId === entry.id;
        } catch (error) {
            return false;
        }
    }

    // Each provider as read now: { providerId, alive, typeName, glyph, busy, canChange,
    // ready, lockdownNote, rowExtras, cardExtras, settingsPage, pageUrl, entries, problems, object }
    readonly property var _providerReads: _providers.map(entry => _readProvider(entry))
    // A provider's `ready`: its entries were read successfully at least once. The core no
    // longer judges anything by it (nothing is pruned); kept in the read for the views.

    function _readProvider(entry) {
        const gone = problem => ({
            providerId: entry.id, alive: false, typeName: "", glyph: "", busy: false, canChange: true, ready: false,
            lockdownNote: "", rowExtras: null, cardExtras: null, settingsPage: "", pageUrl: "", entries: [], problems: [problem], object: null
        });
        try {
            const provider = entry.object;
            if (!_alive(entry))
                return gone(entry.id + ": gone, or its providerId changed");
            const checked = NetworkRules.vpnProviderEntries(entry.id, provider.entries);
            const text = (value, most) => typeof value === "string" ? value.slice(0, most) : "";
            const component = value => value !== null && value !== undefined && typeof value.createObject === "function" ? value : null;
            return {
                providerId: entry.id, alive: true, typeName: text(provider.typeName, 60) || "VPN", glyph: text(provider.glyph, 8),
                busy: provider.busy === true, canChange: provider.canChange !== false, ready: provider.ready === true,
                lockdownNote: text(provider.lockdownNote, 300), rowExtras: component(provider.rowExtras),
                cardExtras: component(provider.cardExtras), settingsPage: text(provider.settingsPage, 200),
                pageUrl: text(provider.pageUrl, 1000),
                entries: checked.entries, problems: checked.problems, object: provider
            };
        } catch (error) {
            return gone(entry.id + ": reading it threw: " + error);
        }
    }

    // The providers' entries as VPNs (NetworkRules.vpnProviderVpns), providers in the order
    // registered
    readonly property var providerVpns: _providerReads.reduce((all, read) => all.concat(NetworkRules.vpnProviderVpns(read)), [])

    // { providerId: [problem…] }: what was dropped from each, logged when it changes
    readonly property var providerProblems: {
        const problems = {};
        for (const read of _providerReads)
            if (read.problems.length > 0)
                problems[read.providerId] = read.problems;
        return problems;
    }
    readonly property string _problemsText: JSON.stringify(providerProblems)
    on_ProblemsTextChanged: {
        for (const id in providerProblems)
            console.warn("VpnManager: VPN provider \"" + id + "\": " + providerProblems[id].join("; "));
    }

    // The provider's read for a VPN ({ provider } or its id), or null (NetworkManager's,
    // or its provider not there)
    function providerOf(vpnOrId) {
        const parts = NetworkRules.vpnIdParts(typeof vpnOrId === "string" ? vpnOrId : (vpnOrId?.uuid ?? ""));
        if (parts === null || parts.provider === "")
            return null;
        return _providerReads.find(read => read.alive && read.providerId === parts.provider) ?? null;
    }

    // An operation runs for this VPN: its buttons wait — NetworkManager's while any
    // connecting runs (a second click before the list says "activating" would bring the
    // tunnel down and up again), a provider's while it says it is busy or the entry does
    function busyFor(vpn): bool {
        if (vpn?.type === "provider") {
            const read = providerOf(vpn);
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
            return (providerOf(vpn)?.canChange ?? true) ? "" : "auth";
        return "";
    }

    // The provider's component for a slot (VpnManager.slots), null when there is none: the
    // module host's — the contribution to that slot of the module whose id is the provider's
    // (Modules.slotComponent: built in the module's guard, given its handle, following its
    // module on and off) — else the provider's own rowExtras / cardExtras (a provider that is
    // no module's: the stand-in)
    function extrasFor(slot: string, vpn) {
        const read = providerOf(vpn);
        if (read === null || (slot !== slots.row && slot !== slots.card))
            return null;
        return Modules.slotComponent(slot, read.providerId)
            ?? (slot === slots.row ? read.rowExtras : read.cardExtras);
    }

    // Where a provider VPN's card's "Settings…" leads. One place for the provider's page: its
    // own entry in the settings window's list when it has one (settingsPageOf: the window goes
    // there, the list selects it), else the page in the frame over the VPN page (pageOf),
    // else nowhere (no button).

    // The provider's settingsPage when the settings window has that page now (Shell
    // .settingsPageIds), else "" — a wrong id or a dropped page falls back to the frame
    function settingsPageOf(vpn): string {
        const page = providerOf(vpn)?.settingsPage ?? "";
        return page !== "" && (Shell.settingsPageIds ?? []).includes(page) ? page : "";
    }

    // The framed page's URL of a provider's VPN ("" none) — slot network.vpn.page: the module
    // host's (Modules.slotUrl), else the provider's own pageUrl; "" while settingsPageOf
    // names a page (never two ways to the same content)
    function pageOf(vpn): string {
        const read = providerOf(vpn);
        if (read === null || settingsPageOf(vpn) !== "")
            return "";
        return Modules.slotUrl(slots.page, read.providerId) || read.pageUrl || "";
    }

    // "Settings…" with a settings page to go to: opens the settings window there through the
    // path Api.openSettings takes (Shell.openSettings) and answers true; false when there is
    // none (the card opens pageOf's frame, if any)
    function openSettingsPageOf(vpn): bool {
        const page = settingsPageOf(vpn);
        if (page === "")
            return false;
        Shell.openSettings(page);
        return true;
    }

    // The context a slot's contribution gets (VpnManager.slots): { slot, vpnId, entryId,
    // vpn, provider, otherVpnsUp } and `extra` ({ open } on the card, { close } on the page).
    // `provider` is the provider object itself, so a contribution can call its functions and
    // read its state; `otherVpnsUp` the names of the other VPNs up now (two VPNs may compete
    // for routes and DNS).
    function contextFor(slot: string, vpn, extra) {
        return Object.assign({ slot: slot, vpnId: vpn?.uuid ?? "", entryId: vpn?.entryId ?? "", vpn: vpn,
            provider: providerOf(vpn)?.object ?? null,
            otherVpnsUp: activeVpns.filter(other => other.uuid !== (vpn?.uuid ?? "")).map(other => other.name) }, extra ?? {});
    }

    // The provider VPNs in "VPN with a network" that are not among `vpns` now — not
    // available, whatever the reason (NetworkRules.unavailableVpnIds, the one definition):
    // kept, shown as such in the network's editor, where the user can take them out
    readonly property var unavailableVpnIds: NetworkRules.unavailableVpnIds(withNetworks, vpns)

    // A VPN by its id as a person reads it: its name, or for one not available its provider
    // and entry, said not to be available
    function labelOf(id: string): string {
        const vpn = vpns.find(entry => entry.uuid === id);
        if (vpn)
            return vpn.name;
        const parts = NetworkRules.vpnIdParts(id);
        return parts !== null && parts.provider !== "" ? parts.provider + " · " + parts.entry + " (not available)" : id;
    }

    // The last provider failure turned into a notification ({ title, body }), for the tests
    property var lastProviderNotice: null

    function _notify(notice) {
        lastProviderNotice = notice;
        Notifier.send(notice.title, { body: notice.body });
    }

    function _providerFailed(providerId, entryId, what, reason) {
        _notify(NetworkRules.vpnFailureNotice(String(what ?? ""), String(reason ?? "")));
    }

    // Who asked for a connect or disconnect, as handed to the provider: { origin } — "user"
    // (a button: the provider may prompt, open a browser) or "network" ("VPN with a
    // network": it must never prompt nor open a browser — attention instead). Anything else
    // is the user's. A fresh object each call.
    function _request(request) {
        return { origin: request?.origin === "network" ? "network" : "user" };
    }

    // Calls `action` ("connect", "disconnect", "attend") of a provider VPN, inside a guard:
    // only for an entry the provider reports; a throw is logged and said as a failure.
    // `request` (connect, disconnect) goes along as the second argument.
    function _callProvider(id, action, what, request) {
        const parts = NetworkRules.vpnIdParts(id);
        const read = providerOf(id);
        if (parts === null || read === null) {
            console.warn("VpnManager: " + action + " " + id + ": no such VPN provider here");
            return false;
        }
        const entry = read.entries.find(item => item.id === parts.entry);
        if (!entry) {
            console.warn("VpnManager: " + action + " " + id + ": the provider reports no such VPN");
            return false;
        }
        try {
            if (typeof read.object[action] !== "function")
                return false;
            if (request === undefined)
                read.object[action](parts.entry);
            else
                read.object[action](parts.entry, request);
            return true;
        } catch (error) {
            console.warn("VpnManager: VPN provider \"" + read.providerId + "\": " + action + " threw:", error);
            _notify(NetworkRules.vpnFailureNotice(what + " " + entry.name, String(error)));
            return false;
        }
    }

    // The provider's action for a VPN that needs the user (its attention's action): always
    // the user's doing (a button), so it takes no request
    function attend(id: string): void {
        _callProvider(id, "attend", "Attending to");
    }

    // ── A VPN with a network ── wanted while a network it is linked to is up (NetworkRules
    // .vpnWithNetworkPlan): brought up then, taken down when none is if the shell brought it
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
    readonly property string _providerKey: _providerReads.map(read => read.providerId + (read.ready ? "+" : "-")).join(" ") + "|"
        + providerVpns.map(vpn => vpn.uuid + ":" + vpn.state + (vpn.attention ? ":!" : "")).join(" ")
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
            || providerVpns.some(vpn => vpn.uuid === id));
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
        // provider's VPN is never pruned (NetworkRules.prunedVpnMapping)
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
        const plan = NetworkRules.vpnWithNetworkPlan(profiles, withNetworks, memory, Date.now(), providerVpns);
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
    // environment, never otherwise
    property var _fakeProvider: null
    // By a file URL, as a module's files are loaded (the shell's scanner does not reach
    // tests/; such a file gets the same singletons — docs/plans/modules.md §2)
    readonly property string fakeProviderUrl: "file://" + Quickshell.shellDir + "/tests/FakeVpnProvider.qml"

    function _startFakeProvider() {
        if (Quickshell.env("H2S_FAKE_VPN_PROVIDER") !== "1" || _fakeProvider !== null)
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

    // By id: a provider's ("<provider>:<entry>") through its provider; anything else is
    // NetworkManager's UUID, as before providers. An id with a colon that is no provider
    // VPN here does nothing. `request` { origin: "user" | "network" } says who asked
    // (default the user — a button); a provider gets it as connect's second argument.
    function connect(uuid: string, request): void {
        if (uuid.indexOf(":") >= 0) {
            _callProvider(uuid, "connect", "Connecting", _request(request));
            return;
        }
        NetworkProfiles.activate(uuid, "");
    }

    function disconnect(uuid: string, request): void {
        if (uuid.indexOf(":") >= 0) {
            _callProvider(uuid, "disconnect", "Disconnecting", _request(request));
            return;
        }
        NetworkProfiles.deactivate(uuid, "Disconnecting " + NetworkProfiles.nameOf(uuid));
    }
}
