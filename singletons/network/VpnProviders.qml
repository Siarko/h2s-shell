pragma Singleton

import Quickshell
import QtQuick
import qs.singletons
import qs.singletons.network
import qs.singletons.io

// The VPN providers: objects registered here (components/VpnProvider.qml registers itself,
// through VpnManager.registerProvider), each read through VpnProviderRules.vpnProviderEntries:
// what is wrong is dropped and logged, never shown. A provider destroyed while registered (a
// module disabled) reads as gone and is dropped; a second one with a taken id is refused.
// Here: the registry, the providers' reads and their VPNs, where their contributions go
// (slots, extras, pages, a VPN's context) and the calls into a provider. VpnManager merges
// their VPNs with NetworkManager's and dispatches connect, disconnect and attend by id.
Singleton {
    id: root

    // [{ id, object, handler }] in the order registered
    property var _providers: []
    // Any registered: with none, VpnManager's lists are NetworkManager's alone
    readonly property bool hasProviders: _providers.length > 0

    // Where a provider's contributions go. A module's provider (providerId = its module id)
    // puts its elements under its VPNs' rows in the network popup and in their cards'
    // opened part through the anchors popup.network.connections.vpn.row (after) and
    // settings.network_vpn.vpns.card.settings (prepend), scope own-provider: the views give
    // each VPN's block its provider's id (scopeId) and the VPN's context — { vpnId, entryId,
    // vpn, provider, otherVpnsUp, otherVpns } (VpnManager.othersUp makes the last two) —,
    // and the module host shows only that module's elements there. The module's old slots network.vpn.row
    // and network.vpn.card are read as those anchors (ModuleRules.slotAliases). A provider
    // that is no module's (the stand-in) hands its Components over itself: rowExtras and
    // cardExtras (ownExtrasOf, built by components/VpnExtras.qml beside the anchor hosts),
    // pageUrl. The page keeps its slot:
    //   network.vpn.page — a page of the provider's own, opened over the VPN page from the
    //                      card, in the settings pages' frame (title, Back, scrolling) — only
    //                      when the provider has no settingsPage the settings window knows
    //                      (settingsPageOf, pageOf); context { slot, vpnId, entryId, vpn, provider, otherVpnsUp, otherVpns, close }
    //   (contextFor makes it)
    readonly property var slots: ({ page: "network.vpn.page" })

    // Takes `provider` (a VpnProvider, or an object of its shape); false when refused: no
    // valid providerId, a module's provider whose id is not its module id or is reserved
    // (VpnProviderRules.providerRegistration; the reason in the module's status), or the id
    // taken by another provider still there
    function registerProvider(provider): bool {
        let id;
        try {
            id = provider?.providerId;
        } catch (error) {
            id = undefined;
        }
        if (!VpnProviderRules.isVpnProviderId(id)) {
            console.warn("VpnProviders: a VPN provider refused: its providerId " + JSON.stringify(String(id)).slice(0, 60)
                + " is not a lower-case letter and up to 31 of a-z 0-9 - _");
            return false;
        }
        const live = _providers.filter(entry => _alive(entry));
        if (live.some(entry => entry.object === provider))
            return true;
        const registration = VpnProviderRules.providerRegistration(id, _ownersOf(provider, new Error().stack));
        if (registration.problem !== "") {
            if (registration.reportTo.length > 0)
                registration.reportTo.forEach(moduleId => Modules.reportError(moduleId, registration.problem));
            else
                console.warn("VpnProviders: " + registration.problem);
            return false;
        }
        if (live.some(entry => entry.id === id)) {
            console.warn("VpnProviders: a second VPN provider \"" + id + "\" refused: the id is taken");
            return false;
        }
        for (const gone of _providers.filter(entry => !live.includes(entry)))
            _disconnectHandler(gone);
        const handler = (entryId, what, reason) => root._providerFailed(id, entryId, what, reason);
        try {
            if (typeof provider.failed?.connect === "function")
                provider.failed.connect(handler);
        } catch (error) {
            console.warn("VpnProviders: VPN provider \"" + id + "\": its failed signal cannot be connected:", error);
        }
        _providers = live.concat([{ id: id, object: provider, handler: handler, moduleId: registration.moduleId, directory: registration.directory }]);
        return true;
    }

    // The module directories a provider is traced to ([{ directory, moduleId }]): the folder
    // of the file that declared it (its QML context) and each module whose code is on the
    // registering call's `stack` — a provider a module's code makes from its own file is
    // traced to that module once. None: the core's
    function _ownersOf(provider, stack) {
        const directories = Modules.host.directories;
        const found = [];
        const via = {};
        let declared = "";
        try {
            declared = String(Qt.resolvedUrl(".", provider));
        } catch (error) {
            declared = "";
        }
        const index = ModuleFileRules.directoryIndexOf(directories, declared);
        if (index >= 0) {
            found.push(directories[index]);
            via[directories[index]] = "file";
        }
        for (const directory of ModuleRules.stackDirectories(stack, directories))
            if (!found.includes(directory)) {
                found.push(directory);
                via[directory] = "stack";
            }
        return found.map(directory => ({ directory: directory, via: via[directory],
                                         moduleId: Modules.handleAt("file://" + encodeURI(directory) + "/")?.moduleId ?? "" }));
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
    // ready, lockdownNote, rowExtras, cardExtras, settingsPage, pageUrl, pageProblem, moduleId,
    // entries, problems, object } — a module's provider's pageUrl only a file of its own
    // folder (VpnProviderRules.providerPageUrl; else "" and pageProblem, in its module's status)
    readonly property var reads: _providers.map(entry => _readProvider(entry))
    // A provider's `ready`: its entries were read successfully at least once. The core no
    // longer judges anything by it (nothing is pruned); kept in the read for the views.

    function _readProvider(entry) {
        const gone = problem => ({
            providerId: entry.id, alive: false, typeName: "", glyph: "", busy: false, canChange: true, ready: false,
            lockdownNote: "", rowExtras: null, cardExtras: null, settingsPage: "", pageUrl: "", pageProblem: "", moduleId: entry.moduleId ?? "",
            entries: [], problems: [problem], object: null
        });
        try {
            const provider = entry.object;
            if (!_alive(entry))
                return gone(entry.id + ": gone, or its providerId changed");
            const checked = VpnProviderRules.vpnProviderEntries(entry.id, provider.entries);
            const text = (value, most) => typeof value === "string" ? value.slice(0, most) : "";
            const component = value => value !== null && value !== undefined && typeof value.createObject === "function" ? value : null;
            const page = _pageOf(text(provider.pageUrl, 1000), entry.directory ?? "");
            return {
                providerId: entry.id, alive: true, typeName: text(provider.typeName, 60) || "VPN", glyph: text(provider.glyph, 8),
                busy: provider.busy === true, canChange: provider.canChange !== false, ready: provider.ready === true,
                lockdownNote: text(provider.lockdownNote, 300), rowExtras: component(provider.rowExtras),
                cardExtras: component(provider.cardExtras), settingsPage: text(provider.settingsPage, 200),
                pageUrl: page.url, pageProblem: page.problem, moduleId: entry.moduleId ?? "",
                entries: checked.entries, problems: checked.problems, object: provider
            };
        } catch (error) {
            return gone(entry.id + ": reading it threw: " + error);
        }
    }

    // A module's provider's pageUrl, checked (VpnProviderRules.providerPageUrl): the link
    // check's answers by "<path>\n<module directory>" — { file, directory } (realpath of
    // each) or null — asked once per pair, the page held back until it answers. At most
    // _maxResolved kept; past that the oldest go and are asked again when read
    property var _resolved: ({})
    property var _resolving: []
    readonly property int _maxResolved: 64

    function _pageOf(url, directory) {
        const key = page => page + "\n" + directory;
        const page = VpnProviderRules.providerPageUrl(url, directory, Modules.host.directories);
        if (page.resolve === "")
            return page;
        const known = _resolved[key(page.resolve)];
        if (known !== undefined)
            return VpnProviderRules.providerPageUrl(url, directory, Modules.host.directories, known);
        const path = page.resolve;
        if (!_resolving.includes(key(path)))
            Qt.callLater(() => root._resolve(path, directory));
        return page;
    }

    function _resolve(path, directory) {
        const key = path + "\n" + directory;
        if (_resolving.includes(key) || _resolved[key] !== undefined)
            return;
        _resolving = _resolving.concat([key]);
        _linkCheck.start(["realpath", "-e", "--", directory, path], {
            timeoutMs: 5000, killAfterMs: 1000,
            done: result => {
                const lines = result.ok ? result.stdout.split("\n") : [];
                const answer = lines.length === 2 && lines[0].startsWith("/") && lines[1].startsWith("/") ? { directory: lines[0], file: lines[1] } : null;
                const kept = Object.keys(root._resolved).slice(-(root._maxResolved - 1));
                const next = {};
                for (const each of kept)
                    next[each] = root._resolved[each];
                next[key] = answer;
                root._resolving = root._resolving.filter(each => each !== key);
                root._resolved = next;
            }
        });
    }

    property CommandRunner _linkCheck: CommandRunner {}

    // A module's provider's refused pageUrl goes into its module's status, once per text
    readonly property string _pageProblemsText: JSON.stringify(reads.filter(read => read.pageProblem !== "" && read.moduleId !== "")
        .map(read => [read.moduleId, read.pageProblem]))
    on_PageProblemsTextChanged: {
        for (const read of reads)
            if (read.pageProblem !== "" && read.moduleId !== "")
                Modules.reportError(read.moduleId, "VPN provider \"" + read.providerId + "\": " + read.pageProblem);
    }

    // The providers' entries as VPNs (VpnProviderRules.vpnProviderVpns), providers in the order
    // registered
    readonly property var providerVpns: reads.reduce((all, read) => all.concat(VpnProviderRules.vpnProviderVpns(read)), [])

    // { providerId: [problem…] }: what was dropped from each, logged when it changes
    readonly property var providerProblems: {
        const problems = {};
        for (const read of reads)
            if (read.problems.length > 0)
                problems[read.providerId] = read.problems;
        return problems;
    }
    readonly property string _problemsText: JSON.stringify(providerProblems)
    on_ProblemsTextChanged: {
        for (const id in providerProblems)
            console.warn("VpnProviders: VPN provider \"" + id + "\": " + providerProblems[id].join("; "));
    }

    // The provider's read for a VPN ({ provider } or its id), or null (NetworkManager's,
    // or its provider not there)
    function providerOf(vpnOrId) {
        const parts = VpnProviderRules.vpnIdParts(typeof vpnOrId === "string" ? vpnOrId : (vpnOrId?.uuid ?? ""));
        if (parts === null || parts.provider === "")
            return null;
        return reads.find(read => read.alive && read.providerId === parts.provider) ?? null;
    }

    // A provider's own Component for under a VPN's row (`place` "row") or on its card
    // ("card"): its rowExtras / cardExtras, null when it has none or the VPN is
    // NetworkManager's. A module's elements come through the anchor hosts instead.
    function ownExtrasOf(place: string, vpn) {
        const read = providerOf(vpn);
        if (read === null || (place !== "row" && place !== "card"))
            return null;
        return place === "row" ? read.rowExtras : read.cardExtras;
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

    // The context of a VPN's place for a provider's contributions: { slot, vpnId, entryId,
    // vpn, provider, otherVpnsUp, otherVpns } and `extra` ({ close } on the page). `provider`
    // is the provider object itself, so a contribution can call its functions and read its
    // state. The views give the anchor blocks of a VPN's row and card the same keys, without
    // `slot`.
    function contextFor(slot: string, vpn, extra) {
        const others = VpnManager.othersUp(vpn);
        return Object.assign({ slot: slot, vpnId: vpn?.uuid ?? "", entryId: vpn?.entryId ?? "", vpn: vpn,
            provider: providerOf(vpn)?.object ?? null, otherVpnsUp: others.names, otherVpns: others.rows }, extra ?? {});
    }

    // A provider's failure texts come from outside the shell (a module, its daemon's error):
    // sent as plain text, never read as markup, so a provider need not clean them
    function _notify(notice) {
        Notifier.send(notice.title, { body: notice.body, format: "plain" });
    }

    function _providerFailed(providerId, entryId, what, reason) {
        _notify(VpnProviderRules.vpnFailureNotice(String(what ?? ""), String(reason ?? "")));
    }

    // Calls `action` ("connect", "disconnect", "attend") of a provider VPN, inside a guard
    // (VpnManager's connect, disconnect and attend for a provider's id): only for an entry
    // the provider reports; a throw is logged and said as a failure. `request` (connect,
    // disconnect) goes along as the second argument.
    function call(id, action, what, request) {
        const parts = VpnProviderRules.vpnIdParts(id);
        const read = providerOf(id);
        if (parts === null || read === null) {
            console.warn("VpnProviders: " + action + " " + id + ": no such VPN provider here");
            return false;
        }
        const entry = read.entries.find(item => item.id === parts.entry);
        if (!entry) {
            console.warn("VpnProviders: " + action + " " + id + ": the provider reports no such VPN");
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
            console.warn("VpnProviders: VPN provider \"" + read.providerId + "\": " + action + " threw:", error);
            _notify(VpnProviderRules.vpnFailureNotice(what + " " + entry.name, String(error)));
            return false;
        }
    }
}
