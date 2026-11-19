pragma Singleton

import Quickshell
import QtQuick


// The module system's decisions (notes/plans/modules.md) — pure, so tests/ModuleRulesTest.qml
// checks them without a module on disk: reading and checking a manifest, whether its API
// version fits the shell's, the namespaces a module's contributions must stay in, the import
// check (a warning, by the owner's decision), which of two modules with one id wins, the
// state a module is in, and the contributions of several modules merged into the lists the
// core's registries will read. No file, no process, no other singleton but the pure
// AddressRules; ModuleHost does the I/O. Nothing here throws on any input: a manifest is
// written by someone else.
//
// This file holds what the API is: its version, the slots, the reserved ids, the states,
// the limits, the API's views of the core's state, what a module hands the core at run
// time, and the small readers the other files share. The rest is in four files beside it:
// ModuleManifestRules (the manifest and the namespaces), ModuleFileRules (paths, the file
// check, the start guard), ModuleSourceRules (what is read from a module's QML: the root's
// properties, the import check) and ModuleMergeRules (several modules: precedence, states,
// the merged lists).
Singleton {
    id: root

    // The largest module.json read; anything bigger is refused before parsing
    readonly property int maxManifestBytes: 256 * 1024
    // At most this many entries in each list of a manifest; the rest is dropped (an error)
    readonly property int maxEntries: 200
    // How much of a QML file the import check looks at (imports sit at the top)
    readonly property int maxHeaderBytes: 64 * 1024

    readonly property var idPattern: /^[a-z][a-z0-9_-]{0,31}$/

    // The module API this shell offers, "major.minor" — published as Api.version (qs.api).
    // Kept here, not in api/, so that the host (qs.singletons) never imports qs.api: qs.api
    // imports qs.singletons, and the two importing each other would be a cycle.
    // notes/plans/modules.md, "Module API 1.0", is the surface.
    //
    // THE VERSION RULE. Every change to the API bumps the minor once and has one "- 1.x:"
    // line under "Module API" in CHANGELOG.md (tests/ModuleRulesTest.qml compares the newest
    // with this number); what a change refuses or removes is named there after "Tightened:".
    // Until the first release announced as open to module authors a minor may also remove
    // things: the old way keeps working while it is listed among a module's `deprecations`
    // (statusOf), and the change that removes it raises `apiFloor`. From that release on a
    // minor only adds: a removal needs a major version, after at least one release in which
    // the thing was listed as deprecated.
    readonly property string apiVersion: "1.32"

    // The oldest API version whose modules still run unchanged on this shell: a module
    // written for an older one is `incompatible`, with the reason (apiCompatibility), so a
    // tightening is never silent. Never the version that removes something — a module cannot
    // ask for a version no shell has yet — but the last one that only added.
    readonly property string apiFloor: "1.0"

    // ---- The slots the core offers (API 1.0; the VPN ones since 1.1) ----
    //
    // A slot is a place in a panel the core owns where modules may put content
    // (components/ModuleSlot.qml). Each contribution is built in a guard of its own, with
    // the context below as its `context` property (passed again only when its value
    // changes) and the module's handle as `module`. Adding a slot bumps the API's minor.
    //
    // NEVER a slot on the lock screen, the screensaver or anything under singletons/lock:
    // nothing foreign is drawn or run there (notes/plans/modules.md §4, item 1).
    // tests/ModuleRegistriesTest.qml checks that no file there names ModuleSlot.
    readonly property var slotTable: [
        { name: "network.popup.sections", since: "1.0",
          where: "the network popup (panels/NetworkPanel.qml), under the VPN, Ethernet and Wi-Fi sections, above the network list",
          context: "{ slot, wifiEnabled: bool, wifiConnected: bool, ethernetConnected: bool }" },
        { name: "notifications.popup.top", since: "1.0",
          where: "the notifications popup (panels/NotificationPanel.qml), above the list",
          context: "{ slot, count: the number of notifications in the list }" },
        { name: "settings.general.bottom", since: "1.0",
          where: "Settings → Behaviour → General, at the end of the page",
          context: "{ slot, editIndex: the profile being edited (for SettingEditor) }" },
        // The VPN provider seam's three (notes/plans/tailscale.md §3): one contribution per
        // provider, the one of the module whose id is the provider's providerId — a module's
        // provider uses its module id (`VpnProvider { providerId: module.moduleId }`). The row's
        // and the card's are read as their anchors since 1.23 (slotAliases: own-provider places);
        // the page's is still a slot (VpnManager.pageOf asks here first). A provider that is no
        // module's keeps its own rowExtras, cardExtras and pageUrl.
        { name: "network.vpn.row", since: "1.1",
          where: "the network popup's VPN section (panels/network/VpnSection.qml), under the row of each VPN of the module's provider",
          context: "{ slot, vpnId, entryId, vpn, provider, otherVpnsUp: [names of the other VPNs up], otherVpns: [the same as Api.vpnsUp rows] (1.16) }" },
        { name: "network.vpn.card", since: "1.1",
          where: "Settings → System → Network → VPN, on the card of each VPN of the module's provider, while the card is open",
          context: "{ slot, vpnId, entryId, vpn, provider, otherVpnsUp, otherVpns, open: bool }" },
        { name: "network.vpn.page", since: "1.1",
          where: "a page over Settings → System → Network → VPN, opened from the card's \"Settings…\", in the core's frame (Back, title, scrolling)",
          context: "{ slot, vpnId, entryId, vpn, provider, otherVpnsUp, otherVpns, close: function }" }
    ]
    readonly property var slotNames: slotTable.map(entry => entry.name)

    // ---- Anchors: the places in the shell's views where modules put elements ----
    //
    // A view is built from shared blocks (components/AnchorBlock.qml and the kinds on it);
    // a block with an `anchor` name has a path derived from where it stands:
    //
    //   <surface>.<view>[.<block>]…[.<region>]
    //
    //   surface   "settings" or "popup" — the bar has no anchors, nor has anything on the
    //             lock screen, the screensaver or under singletons/lock
    //   view      a settings page's id (SettingsWindow.pages: general, network_vpn, …) or a
    //             popup's key (WidgetRegistry: network, notifications, …), given by the
    //             window or the popup to the view's root
    //   block     a block's `anchor`, [a-z][a-zA-Z0-9]*: what it holds (saved, vpns), never
    //             where it stands or its title's words. A block repeated per item is named by
    //             its kind (card, row): all of them share one path, the item is in the
    //             element's context. A block with no anchor adds no level
    //   region    "actions", "settings" or "title": a card's regions, only right after
    //             "card", last; "title" also a row's (a popup row's name line), right after
    //             "row" (anchorRegionHolders); never a block's name
    //
    // A module names a path, a placement and its element (the manifest's `anchors`):
    // `before` and `after` put it next to the block, outside it; `prepend` and `append`
    // inside, first and last of its content (under its frame: a page's heading, a section's
    // title). Only the paths in anchorTable take content: naming a block does not publish it.
    // Adding a row bumps the API's minor; tests/AnchorsTest.qml holds the views to the table.
    readonly property var anchorPlacements: ["before", "after", "prepend", "append"]
    readonly property var anchorSurfaces: ["settings", "popup"]
    readonly property var anchorRegions: ["actions", "settings", "title"]
    // The blocks a region stands right under, by their name, and the regions each has
    readonly property var anchorRegionHolders: ({ card: ["actions", "settings", "title"], row: ["title"] })
    // The kinds of block: SettingsPage, SettingsSection, SettingsCard, SettingsRow (PopupRow in
    // a popup), PopupSection, and a card's region
    readonly property var anchorKinds: ["page", "section", "card", "row", "popupSection", "region"]
    readonly property var anchorScopes: ["", "own-provider"]
    // What a row may demand of its elements: anything, or the public button (by the mark it
    // carries, `apiElement`). A card's `actions` takes the button only: the stack sits in the
    // card's header, beside the name, where anything else breaks every card
    readonly property var anchorTakes: ["", "SmallButton"]
    readonly property int maxAnchorPathLength: 200

    // The anchors this shell offers: { path, kind, placements, takes, context, scope, since,
    // where, view } —
    //   kind        one of anchorKinds
    //   placements  the placements published for the path (a block can take more; one is
    //               published when a module needs it)
    //   takes       what an element there must be (anchorTakes: "" anything; "SmallButton" on
    //               a card's actions — another is refused when it is built, an error in its
    //               module's status: components/ModuleContribution.qml)
    //   context     what an element's `context` holds besides { anchor, placement }
    //   scope       "" — every module's elements; "own-provider" — on an item of a VPN
    //               provider, only the elements of the module that is that provider (the
    //               block's scopeId, components/AnchorBlock.qml; none without one)
    //   since       the API version that published it
    //   where       where it shows, for people
    //   view        the file that builds the block, from the shell's directory
    //               ("panels/NetworkPanel.qml"): what tests/AnchorsTest.qml reads to check that
    //               a slot read as this place is no longer built as a slot there
    // Api.anchors is its frozen copy.
    readonly property var anchorTable: [
        { path: "settings.general", kind: "page", placements: ["append"], takes: "",
          context: "{ editIndex: the profile being edited (for SettingEditor) }", scope: "", since: "1.21",
          where: "Settings → Behaviour → General, at the end of the page", view: "panels/settings/GeneralSettings.qml" },
        { path: "popup.network.connections", kind: "popupSection", placements: ["append"], takes: "",
          context: "{ wifiEnabled: bool, wifiConnected: bool, ethernetConnected: bool }", scope: "", since: "1.22",
          where: "the network popup, under the VPN, Ethernet and Wi-Fi parts, above the divider over the network list",
          view: "panels/NetworkPanel.qml" },
        { path: "popup.notifications", kind: "popupSection", placements: ["prepend"], takes: "",
          context: "{ count: the number of notifications in the list }", scope: "", since: "1.22",
          where: "the notifications popup, under its header, above the list", view: "panels/NotificationPanel.qml" },
        { path: "popup.network.connections.vpn.row", kind: "row", placements: ["after"], takes: "",
          context: "{ vpnId, entryId, vpn, provider: the provider object, otherVpnsUp: [names of the other VPNs up], otherVpns: [the same as Api.vpnsUp rows] }",
          scope: "own-provider", since: "1.23",
          where: "the network popup's VPN part, under the row of each VPN of the module's provider", view: "panels/network/VpnSection.qml" },
        { path: "settings.network_vpn.vpns.card.settings", kind: "region", placements: ["prepend"], takes: "",
          context: "{ vpnId, entryId, vpn, provider, otherVpnsUp, otherVpns }", scope: "own-provider", since: "1.23",
          where: "Settings → System → Network → VPN, the opened card of each VPN of the module's provider, above the card's own rows",
          view: "panels/settings/NetworkVpnSettings.qml" },
        { path: "settings.network_wifi.saved.card.settings", kind: "region", placements: ["append"], takes: "",
          context: "{ networkId: the profile's UUID (Api.networks' id), name, kind: \"wifi\", active: fully up }", scope: "", since: "1.24",
          where: "Settings → System → Network → Wi-Fi, the opened card of each saved network, under the page's rows (the password)",
          view: "panels/settings/NetworkWifiSettings.qml" },
        { path: "settings.network_ethernet.profiles.card.settings", kind: "region", placements: ["append"], takes: "",
          context: "{ networkId: the profile's UUID (Api.networks' id), name, kind: \"ethernet\", active: fully up }", scope: "", since: "1.24",
          where: "Settings → System → Network → Ethernet, the opened card of each wired profile, under the card's rows",
          view: "panels/settings/NetworkEthernetSettings.qml" },
        { path: "settings.network_wifi.saved.card.title", kind: "region", placements: ["append"], takes: "",
          context: "{ networkId, name, kind: \"wifi\", active }", scope: "", since: "1.28",
          where: "Settings → System → Network → Wi-Fi, each saved network's card, closed and open: on its name's line, after the name",
          view: "panels/settings/NetworkWifiSettings.qml" },
        { path: "settings.network_ethernet.profiles.card.title", kind: "region", placements: ["append"], takes: "",
          context: "{ networkId, name, kind: \"ethernet\", active }", scope: "", since: "1.28",
          where: "Settings → System → Network → Ethernet, each wired profile's card, closed and open: on its name's line, after the name",
          view: "panels/settings/NetworkEthernetSettings.qml" },
        { path: "settings.network_vpn.vpns.card.title", kind: "region", placements: ["append"], takes: "",
          context: "{ vpnId, entryId, vpn, provider, otherVpnsUp, otherVpns }", scope: "", since: "1.29",
          where: "Settings → System → Network → VPN, each VPN's card, whatever its provider, closed and open: on its name's line, after the name",
          view: "panels/settings/NetworkVpnSettings.qml" },
        { path: "settings.network_vpn.vpns.card.actions", kind: "region", placements: ["append"], takes: "SmallButton",
          context: "{ vpnId, entryId, vpn, provider, otherVpnsUp, otherVpns }", scope: "own-provider", since: "1.25",
          where: "Settings → System → Network → VPN, the card of each VPN of the module's provider, closed and open: in the row of buttons on its name's line, after the card's own (\"Settings…\", \"Edit\"), before \"Delete\"",
          view: "panels/settings/NetworkVpnSettings.qml" },
        { path: "settings.network_wifi.saved.card.actions", kind: "region", placements: ["append"], takes: "SmallButton",
          context: "{ networkId, name, kind: \"wifi\", active }", scope: "", since: "1.25",
          where: "Settings → System → Network → Wi-Fi, each saved network's card, closed and open: in the row of buttons on its name's line, after \"Edit\", before \"Forget\"",
          view: "panels/settings/NetworkWifiSettings.qml" },
        { path: "settings.network_ethernet.profiles.card.actions", kind: "region", placements: ["append"], takes: "SmallButton",
          context: "{ networkId, name, kind: \"ethernet\", active }", scope: "", since: "1.25",
          where: "Settings → System → Network → Ethernet, each wired profile's card, closed and open: in the row of buttons on its name's line, after \"Edit\", before \"Forget\"",
          view: "panels/settings/NetworkEthernetSettings.qml" },
        { path: "popup.network.wifi.row.title", kind: "region", placements: ["append"], takes: "",
          context: "{ networkId: its saved profile's UUID, \"\" for a network not saved, name: the profile's, else the SSID, kind: \"wifi\", active }",
          scope: "", since: "1.32",
          where: "the network popup's list of Wi-Fi networks in range, each network's row, closed and open: on its name's line, after the name",
          view: "panels/network/WifiNetworkRow.qml" },
        { path: "popup.network.connections.wired.row.title", kind: "region", placements: ["append"], takes: "",
          context: "{ networkId: the wired profile up's UUID, name, kind: \"ethernet\", active } (networkId and name \"\" with none up)",
          scope: "", since: "1.32",
          where: "the network popup's Ethernet part, the wired row: on its name's line, after the name",
          view: "panels/NetworkPanel.qml" }
    ]

    // The kinds a view's root is: the one block with no name that is addressable, at the
    // base its window or popup gives it (settings.general, popup.notifications). Any other
    // block with no name adds no level and is not addressable.
    readonly property var anchorRootKinds: ["page", "popupSection"]
    // The block each kind is, as a view's file names it (slotAliasProblems)
    // (a network page's cards are NetworkProfileCards, built on SettingsCard)
    readonly property var anchorKindTypes: ({ page: ["SettingsPage"], section: ["SettingsSection"], card: ["SettingsCard", "NetworkProfileCard"],
                                              row: ["SettingsRow", "PopupRow"], popupSection: ["PopupSection"],
                                              region: ["SettingsCard", "NetworkProfileCard", "PopupRowTitle"] })

    // Today's slots, read as anchors once their view is converted (the alias's `at` in
    // anchorTable): a manifest's `slots` entry for one becomes that anchor's element, listed in
    // the module's deprecations, its context also carrying `slot` (and what `context` adds
    // here, as the old name promised). network.vpn.page has none: a provider's page is its
    // settingsPage.
    //   context  fixed values the old slot's context held
    //   needs    the keys of the old slot's context that change with the view (wifiEnabled
    //            in the network popup): the converted block's `context` must provide each,
    //            so an element written for the slot still finds them. tests/AnchorsTest.qml
    //            checks that the row's view names each one (slotAliasProblems).
    readonly property var slotAliases: [
        { slot: "network.popup.sections", at: "popup.network.connections", place: "append", context: {},
          needs: ["wifiEnabled", "wifiConnected", "ethernetConnected"] },
        { slot: "notifications.popup.top", at: "popup.notifications", place: "prepend", context: {}, needs: ["count"] },
        { slot: "settings.general.bottom", at: "settings.general", place: "append", context: {}, needs: ["editIndex"] },
        { slot: "network.vpn.row", at: "popup.network.connections.vpn.row", place: "after", context: {},
          needs: ["vpnId", "entryId", "vpn", "provider", "otherVpnsUp", "otherVpns"] },
        { slot: "network.vpn.card", at: "settings.network_vpn.vpns.card.settings", place: "prepend", context: { open: true },
          needs: ["vpnId", "entryId", "vpn", "provider", "otherVpnsUp", "otherVpns"] }
    ]

    // A slot's alias ({ slot, at, place, context }), or null
    function slotAlias(slot) {
        return slotAliases.find(alias => alias.slot === slot) ?? null;
    }

    // Why `name` is not a block's anchor name ("" when it is one)
    function anchorNameProblem(name) {
        if (typeof name !== "string" || name === "")
            return "a block's name is a word";
        if (name.length > 64 || !/^[a-z][a-zA-Z0-9]*$/.test(name))
            return show(name) + " is not a block's name (a lowercase letter, then letters and digits; at most 64)";
        if (anchorRegions.includes(name))
            return show(name) + " names a card's region, not a block";
        return "";
    }

    // Why `path` is not an anchor's path ("" when it is one, whether offered or not)
    function anchorPathProblem(path) {
        if (typeof path !== "string" || path === "")
            return "a place is a dotted name, <surface>.<view>[.<block>]…";
        if (path.length > maxAnchorPathLength)
            return show(path) + " is longer than " + maxAnchorPathLength + " characters";
        const parts = path.split(".");
        if (parts.length < 2 || !anchorSurfaces.includes(parts[0]))
            return show(path) + " does not start with settings.<page> or popup.<key>";
        if (!/^[a-z][a-z0-9_-]{0,63}$/.test(parts[1]))
            return show(path) + ": " + show(parts[1]) + " is not a page's id or a popup's key";
        for (let i = 2; i < parts.length; i++) {
            const part = parts[i];
            if (anchorRegions.includes(part)) {
                const holder = parts[i - 1];
                if (i === 2 || i !== parts.length - 1 || !(anchorRegionHolders[holder] ?? []).includes(part))
                    return show(path) + ": " + show(part) + " is a region: only last, right after a block that has it ("
                        + Object.keys(anchorRegionHolders).filter(name => anchorRegionHolders[name].includes(part)).map(show).join(" or ") + ")";
                continue;
            }
            const problem = anchorNameProblem(part);
            if (problem !== "")
                return show(path) + ": " + problem;
        }
        return "";
    }

    // Where a block stands: { path, childPath } — `path` its own address ("" not
    // addressable), `childPath` what the blocks inside it build on. `parentPath` is the
    // nearest enclosing block's childPath, or the base a window or popup gives its view's
    // root (`parentIsBase`). A block with no anchor adds no level, and is addressable only as
    // the view's root: a block of a root kind (anchorRootKinds, `kind`) right at the base (the
    // page itself: settings.general) — anything else with no name at the base, a section
    // straight under a plain item, is not; a name that is not one makes it and everything
    // inside it unaddressable. A card's region (kind "region") is named by the region
    // (anchorRegions), right under a block that has it (a card named "card"; "title" under a
    // row named "row" too: anchorRegionHolders), and nothing is under it; no other kind takes
    // a region's name.
    function anchorBlockPaths(parentPath, parentIsBase, anchor, kind) {
        const none = { path: "", childPath: "" };
        if (typeof parentPath !== "string" || parentPath === "" || anchorPathProblem(parentPath) !== "")
            return none;
        if (kind === "region") {
            const regionPath = parentPath + "." + anchor;
            return anchorRegions.includes(anchor) && anchorPathProblem(regionPath) === "" ? { path: regionPath, childPath: "" } : none;
        }
        if (anchor === undefined || anchor === null || anchor === "")
            return { path: parentIsBase === true && anchorRootKinds.includes(kind) ? parentPath : "", childPath: parentPath };
        if (anchorNameProblem(anchor) !== "")
            return none;
        const path = parentPath + "." + anchor;
        return anchorPathProblem(path) === "" ? { path: path, childPath: path } : none;
    }

    // The table's row for `path`, or null
    function anchorRow(table, path) {
        return (Array.isArray(table) ? table : []).find(row => isObject(row) && row.path === path) ?? null;
    }

    // Whether a block's host at `placement` shows the elements of `row` (the table's row for
    // the block's path): only when the block is of the row's kind and has a host there — a
    // block that merely shares a path (another kind, a placement it does not have) shows none
    function anchorBlockFits(row, kind, placements, placement) {
        return isObject(row) && typeof kind === "string" && row.kind === kind && Array.isArray(placements)
            && placements.includes(placement) && (row.placements ?? []).includes(placement);
    }

    // What is wrong with the slots read as anchors (an alias whose `at` is in `table`): one
    // text per problem. `slotUses` { slot: [files outside the tests still naming it] };
    // `viewTexts` { file: its text, or undefined when it cannot be read } for each row's view.
    // A slot read as its anchor must no longer be built as a slot; its row's view must build
    // the block (the kind's type, and the block's name unless it is the view's root) and name
    // in it what the alias needs.
    function slotAliasProblems(table, aliases, slotUses, viewTexts) {
        const problems = [];
        for (const alias of Array.isArray(aliases) ? aliases : []) {
            const row = anchorRow(table, alias?.at);
            if (!row)
                continue;
            const where = alias.slot + " → " + alias.at;
            const uses = (slotUses ?? {})[alias.slot] ?? [];
            if (uses.length > 0)
                problems.push(where + ": the slot is still built in " + uses.join(", "));
            if (typeof row.view !== "string" || row.view === "") {
                problems.push(where + ": the row names no view");
                continue;
            }
            const text = (viewTexts ?? {})[row.view];
            if (typeof text !== "string") {
                problems.push(where + ": its view " + row.view + " cannot be read");
                continue;
            }
            const types = anchorKindTypes[row.kind] ?? [];
            if (!types.some(type => new RegExp("\\b" + type + "\\s*\\{").test(text)))
                problems.push(where + ": " + row.view + " builds no " + (types.join(" or ") || row.kind));
            const parts = alias.at.split(".");
            const named = parts.filter((part, index) => index >= 2 && !anchorRegions.includes(part));
            const name = named[named.length - 1];
            if (name !== undefined && !new RegExp("\\banchor:\\s*\"" + name + "\"").test(text))
                problems.push(where + ": " + row.view + " names no block \"" + name + "\"");
            for (const key of Array.isArray(alias.needs) ? alias.needs : []) {
                if (!new RegExp("\\b" + key + "\\s*:").test(text))
                    problems.push(where + ": " + row.view + " gives no " + key + " in the block's context (the slot gave it)");
            }
        }
        return problems;
    }

    // What is wrong with an anchor table (anchorTable, or a suite's): one text per problem
    function anchorTableProblems(table) {
        if (!Array.isArray(table))
            return ["the anchor table is not a list"];
        const problems = [];
        const seen = new Set();
        table.forEach((row, index) => {
            const where = "row " + index + (isObject(row) && typeof row.path === "string" ? " (" + row.path + ")" : "");
            if (!isObject(row)) {
                problems.push(where + ": not an object");
                return;
            }
            const pathProblem = anchorPathProblem(row.path);
            if (pathProblem !== "")
                problems.push(where + ": " + pathProblem);
            if (seen.has(row.path))
                problems.push(where + ": the path is in the table twice");
            seen.add(row.path);
            if (!anchorKinds.includes(row.kind))
                problems.push(where + ": kind " + show(row.kind) + " is not one of " + anchorKinds.join(", "));
            // A row must offer something
            if (!Array.isArray(row.placements) || row.placements.length === 0
                    || !row.placements.every(place => anchorPlacements.includes(place))
                    || new Set(row.placements).size !== row.placements.length)
                problems.push(where + ": placements are not some of " + anchorPlacements.join(", "));
            if (typeof row.takes !== "string" || typeof row.context !== "string" || typeof row.where !== "string" || row.where === "")
                problems.push(where + ": takes, context and where are texts (where not empty)");
            else if (!anchorTakes.includes(row.takes))
                problems.push(where + ": takes " + show(row.takes) + " is not \"\" or \"SmallButton\"");
            else if (typeof row.path === "string" && row.path.endsWith(".card.actions") && row.takes !== "SmallButton")
                problems.push(where + ": a card's actions take a SmallButton");
            if (typeof row.view !== "string" || !/^[a-z][a-zA-Z0-9_/]*\.qml$/.test(row.view) || row.view.includes("//"))
                problems.push(where + ": view " + show(row.view) + " is not a file of the shell (\"panels/NetworkPanel.qml\")");
            if (!anchorScopes.includes(row.scope))
                problems.push(where + ": scope " + show(row.scope) + " is not \"\" or \"own-provider\"");
            if (!parseApi(row.since))
                problems.push(where + ": since " + show(row.since) + " is not \"major.minor\"");
        });
        return problems;
    }

    // ---- A module's icon (API 1.26) ----

    // A text's characters, each a code point: a surrogate pair (an icon above U+FFFF) is one,
    // a lone surrogate one too. The engine's Array.from splits a text into UTF-16 units
    function codePoints(text) {
        const points = [];
        const units = typeof text === "string" ? text : "";
        for (let i = 0; i < units.length; i++) {
            const unit = units.charCodeAt(i);
            const next = i + 1 < units.length ? units.charCodeAt(i + 1) : 0;
            if (unit >= 0xd800 && unit <= 0xdbff && next >= 0xdc00 && next <= 0xdfff) {
                points.push(units.slice(i, i + 2));
                i++;
            } else {
                points.push(units[i]);
            }
        }
        return points;
    }

    // How the shell draws a module's checked icon (the manifest's, ModuleManifestRules
    // .readIcon; its file in `directory`) → { kind, glyph, url, colors }: a glyph as text, an
    // SVG or picture by its file:// URL
    function iconShown(icon, directory) {
        if (!isObject(icon))
            return null;
        const file = icon.kind === "svg" || icon.kind === "image";
        return {
            kind: String(icon.kind), glyph: icon.kind === "glyph" ? String(icon.glyph) : "",
            url: file ? ModuleFileRules.fileUrl(String(directory), String(icon.file)) : "",
            colors: icon.colors === "own" ? "own" : "theme"
        };
    }

    // What stands in a module's icon's place when it has none (none declared, a wrong one,
    // one that could not be drawn): the first letter of its name, upper case — of its id
    // when the name has none; "?" when neither has one
    function iconLetter(name, id) {
        for (const text of [name, id]) {
            const letter = codePoints(text).find(character => character.toLowerCase() !== character.toUpperCase());
            if (letter !== undefined)
                return letter.toUpperCase();
        }
        return "?";
    }

    // Ids a module cannot take: the core's own namespaces (settings groups and key prefixes,
    // fact prefixes, IPC targets, directories) — a module with id "battery" would own the
    // facts battery.* — and words that mean the shell itself. ModuleRulesTest checks that
    // every prefix of a core setting and fact is here.
    readonly property var reservedIds: [
        "animation", "animations", "api", "app", "appearance", "audio", "auth", "authentication", "bar", "battery",
        "bluetooth", "calendar", "clock", "colors", "components", "config", "constructor",
        "core", "curves", "debug", "dictation", "energy", "fonts", "gcal", "general", "graphs", "h2s",
        "h2s-shell", "hardware", "hud", "input", "ipc", "launcher", "lock", "lockscreen",
        "media", "mod", "module", "modules", "music", "network", "notifications", "panel",
        "panels", "performance", "polkit", "polling", "power", "profile", "profiles", "prototype", "qs",
        "quickshell", "safe-mode", "screen", "screensaver", "settings", "shell", "singletons",
        "sound", "stt", "system", "test", "tests", "theme", "themes", "tray", "vpn", "wallpaper",
        "wallpapers", "widget", "widgets", "window", "workspaces",
        // IPC targets of the core (a module's IpcHandler targets are <id> or <id>.<name>),
        // including the test seams' and the VPN branch's fake provider's
        "tablet", "locktest", "shelltest", "fakevpn",
        // Settings page ids and popup keys of the core that are module-id shaped
        "bar_appearance", "controls", "popups", "network_ethernet", "network_overview", "network_vpn",
        "network_wifi", "notifications_appearance", "other_appearance", "widgets_appearance", "tray-menu"
    ]

    readonly property var settingTypes: ["bool", "number", "slider", "interval", "enum", "string", "stringList"]
    readonly property var factTypeNames: ["bool", "number", "percent", "string", "enum"]
    readonly property var settingsTabs: ["behaviour", "appearance", "system"]

    // The states a module can be in (statusOf):
    //   loaded           running: its main (if any) was created, its contributions count
    //   disabled         turned off over IPC, `modules setEnabled <id> false` (Config.disabledModules)
    //   failed           its manifest is unusable, or its main could not be created
    //   incompatible     written for another module API: another major, a newer minor than
    //                    the shell's, or one below the shell's floor (apiFloor)
    //   missing-program  a program in requires.programs is not on PATH
    //   missing-module   (1.18) a module in its manifest's `uses` is not there, not loaded,
    //                    exports no API or an older one (ModuleMergeRules.dependencyPlan;
    //                    the reasons in its errors)
    //   duplicate        another module with the same id came first (search-path order)
    //   pending          waiting for the check of its required programs, or for a module
    //                    it uses
    //   safe-mode        the shell started in safe mode: no module is loaded
    // A module in a cycle of `uses` (itself included) is failed, the cycle named.
    readonly property var states: ["loaded", "disabled", "failed", "incompatible", "missing-program",
                                   "missing-module", "duplicate", "pending", "safe-mode"]

    // ---- Small helpers ----

    function isObject(value) {
        return value !== null && typeof value === "object" && !Array.isArray(value);
    }

    function isString(value, maxLength) {
        return typeof value === "string" && value.length > 0 && value.length <= (maxLength ?? 1000);
    }

    // An own, enumerable field — never one from the prototype ("constructor", "toString")
    function has(object, key) {
        return Object.prototype.hasOwnProperty.call(object, key);
    }

    function get(object, key) {
        return has(object, key) ? object[key] : undefined;
    }

    // A value as short text for a message: never the whole of a huge string
    function show(value) {
        let text;
        try {
            text = typeof value === "string" ? JSON.stringify(value) : String(JSON.stringify(value));
        } catch (error) {
            text = "?";
        }
        return text.length > 60 ? text.slice(0, 57) + "…" : text;
    }

    function isNumber(value) {
        return typeof value === "number" && isFinite(value);
    }

    // ---- API versions ----

    // "major.minor" → { major, minor }, or null
    function parseApi(value) {
        if (typeof value !== "string")
            return null;
        const match = /^(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})$/.exec(value);
        return match ? { major: Number(match[1]), minor: Number(match[2]) } : null;
    }

    // Whether a module asking for API `wanted` runs on a shell with API `shell` whose floor
    // is `floor` (not given: `apiFloor`): the same major, and floor ≤ wanted ≤ shell
    // → { compatible, reason }
    function apiCompatibility(wanted, shell, floor) {
        const oldest = floor === undefined ? apiFloor : floor;
        const module = parseApi(wanted);
        const have = parseApi(shell);
        const least = parseApi(oldest);
        if (!module)
            return { compatible: false, reason: "its API version " + show(wanted) + " is not \"major.minor\"" };
        if (!have)
            return { compatible: false, reason: "the shell's API version " + show(shell) + " is not \"major.minor\"" };
        // A floor that cannot be read lets nothing through: it is what keeps a module off
        // things this shell no longer has
        if (!least)
            return { compatible: false, reason: "the shell's API floor " + show(oldest) + " is not \"major.minor\"" };
        if (module.major !== have.major)
            return { compatible: false, reason: "written for module API " + wanted + "; the shell has " + shell
                     + (module.major > have.major ? " (a newer shell is needed)" : " (the module needs updating)") };
        if (module.minor > have.minor)
            return { compatible: false, reason: "needs module API " + wanted + "; the shell has " + shell + " (a newer shell is needed)" };
        if (least.major > module.major || (least.major === module.major && least.minor > module.minor))
            return { compatible: false, reason: "written for module API " + wanted + "; this shell needs " + oldest
                     + " or newer (the module needs updating)" };
        return { compatible: true, reason: "" };
    }

    // One line of a module's `deprecations` (statusOf): an old way the module still uses and
    // what replaces it — "slots: use `anchors` (goes with the shell's next tightening)".
    // Listed, never a warning: a module's warnings stay empty while it only uses old ways.
    function deprecation(what, use) {
        return String(what) + ": use " + String(use) + " (goes with the shell's next tightening)";
    }

    // ---- Program lookup with trust (API 1.9) ----
    //
    // Which program a name runs, and whether it can be trusted: what a module's handle shows
    // (`programs`) and where the command runner takes `timeout` and `setpriv` from
    // (CommandTools). The probe (programProbeScript) does the reading; everything here judges
    // what it printed.
    //
    // TRUSTED means that nobody but root can change what runs. The path found is walked
    // component by component, as the kernel resolves it (as `namei -l` shows it): every
    // directory passed through, the directory that holds each link met on the way, and the
    // real file at the end must be owned by root and writable by no one else. The Nix store
    // counts as root's as a whole only where /nix/store itself is root's and the user cannot
    // write to it (a multi-user install, run by the daemon); a store the user owns (a
    // single-user install) is judged like any other path. NixOS: /run/current-system/sw/bin
    // leads into the store, the setuid wrappers are root's files under /run/wrappers; Arch:
    // root's /usr/bin. Anything not read — a stat missing, a link that does not resolve, a
    // name holding a line break or a tab, two answers for one path — is untrusted.
    // A guard against mistakes (a program in a directory the user owns, handed on to run as
    // root), not against a process that can already write where it likes.

    // Links followed on the way to the real file; more is untrusted
    readonly property int maxLinkHops: 16
    // How often a module may ask for its programs to be looked up again (recheckDelay)
    readonly property int recheckMinMs: 2000
    // The probe's own PATH, for `stat`, `readlink` and `id` (and /bin/sh runs it): the
    // system's directories, never the PATH being judged — a `stat` the user put there could
    // say anything. NixOS: /run/current-system/sw/bin; Arch: /usr/bin
    readonly property string probeToolPath: "/run/current-system/sw/bin:/usr/bin:/bin"
    readonly property string probeShell: "/bin/sh"

    // `/bin/sh -c programProbeScript sh <"first" | "all"> <the PATH to search> <name>…`, run
    // with PATH=probeToolPath: each name on the PATH given (absolute entries only; an
    // executable regular file), the first match or all of them. Tab-separated lines:
    //   user <uid> <gid gid …>          once: who runs the probe
    //   cand <name> <path>              a match ("" after the name: none at all)
    //   stat <name> <uid> <mode> <gid> <path>   each directory passed through and the real
    //                                   file (stat -L of the physical path; octal mode)
    //   link <name> <path> <target>     each link met, at its physical path
    //   bad  <name>                     a path or a link's target holds a line break or a tab
    //   loop <name>                     more than maxLinkHops links
    readonly property string programProbeScript: [
        "mode=$1; searched=$2; shift 2",
        "set -f",
        "tab=$(printf '\\t'); nl=$(printf '\\nx'); nl=${nl%x}",
        "printf 'user\\t%s\\t%s\\n' \"$(id -u)\" \"$(id -G)\"",
        "say() { s=$(stat -L -c '%u %a %g' -- \"$2\") && printf 'stat\\t%s\\t%s\\t%s\\n' \"$1\" \"$(printf '%s' \"$s\" | tr ' ' '\\t')\" \"$2\"; }",
        "walk() {",
        "  n=$1; rest=${2#/}; cur=/; hops=0",
        "  say \"$n\" /",
        "  while [ -n \"$rest\" ]; do",
        "    c=${rest%%/*}",
        "    case $rest in */*) rest=${rest#*/} ;; *) rest= ;; esac",
        "    case $c in ''|.) continue ;; ..) cur=${cur%/*}; [ -n \"$cur\" ] || cur=/; continue ;; esac",
        "    if [ \"$cur\" = / ]; then next=/$c; else next=$cur/$c; fi",
        "    if [ -L \"$next\" ]; then",
        "      hops=$((hops + 1))",
        "      [ \"$hops\" -le " + maxLinkHops + " ] || { printf 'loop\\t%s\\n' \"$n\"; return; }",
        "      t=$(readlink -- \"$next\") || return",
        "      case $t in *\"$nl\"*|*\"$tab\"*|'') printf 'bad\\t%s\\n' \"$n\"; return ;; esac",
        "      printf 'link\\t%s\\t%s\\t%s\\n' \"$n\" \"$next\" \"$t\"",
        "      case $t in /*) cur=/; rest=${t#/}${rest:+/$rest} ;; *) rest=$t${rest:+/$rest} ;; esac",
        "    else",
        "      cur=$next",
        "      say \"$n\" \"$cur\"",
        "    fi",
        "  done",
        "}",
        "for n; do",
        "  hit=",
        "  IFS=:",
        "  for d in $searched; do",
        "    case $d in /*) ;; *) continue ;; esac",
        "    p=$d/$n",
        "    if [ -f \"$p\" ] && [ -x \"$p\" ]; then",
        "      hit=1",
        "      unset IFS",
        "      case $p in *\"$nl\"*|*\"$tab\"*) printf 'cand\\t%s\\t-\\n' \"$n\"; printf 'bad\\t%s\\n' \"$n\" ;; *) printf 'cand\\t%s\\t%s\\n' \"$n\" \"$p\"; walk \"$n\" \"$p\" ;; esac",
        "      IFS=:",
        "      [ \"$mode\" = all ] && continue || break",
        "    fi",
        "  done",
        "  unset IFS",
        "  [ -n \"$hit\" ] || printf 'cand\\t%s\\t\\n' \"$n\"",
        "done"
    ].join("\n")

    // An absolute path as the probe prints it: no control character, not too long
    function _probePath(value) {
        return typeof value === "string" && value.startsWith("/") && value.length <= 4096 && !/[\u0000-\u001f\u007f]/.test(value);
    }

    // Under the Nix store (and not leaving it by "..")
    function programInStore(path) {
        return typeof path === "string" && path.startsWith("/nix/store/") && !path.split("/").includes("..");
    }

    // One stat's verdict: owned by root, no write bit for the group or others
    function statTrusted(stat) {
        const bits = _modeBits(stat?.mode);
        return stat?.uid === "0" && bits >= 0 && (bits & 0o022) === 0;
    }

    function _modeBits(mode) {
        return typeof mode === "string" && /^[0-7]{1,5}$/.test(mode) ? parseInt(mode, 8) : -1;
    }

    // Whether the Nix store counts as root's as a whole: /nix/store root's, nobody else may
    // write to it, and its group (nixbld on a multi-user install, which may) is not one of
    // the user's (`user`: { uid, groups }; unknown groups: not)
    function storeTrusted(stat, user) {
        const bits = _modeBits(stat?.mode);
        if (stat?.uid !== "0" || bits < 0 || (bits & 0o002) !== 0)
            return false;
        if ((bits & 0o020) === 0)
            return true;
        return Array.isArray(user?.groups) && user.groups.length > 0 && !user.groups.includes(stat.gid);
    }

    // The path walked as the kernel resolves it, from `links` ({ <physical path>: target }):
    // → { ok, real, visited (every physical directory passed through, "/" first, then the
    // real file), reason }. The same steps the probe takes.
    function programWalk(path, links) {
        if (!_probePath(path))
            return { ok: false, real: "", visited: [], reason: "a path that could not be read" };
        let rest = path.split("/");
        let current = "/";
        let hops = 0;
        const visited = ["/"];
        while (rest.length > 0) {
            const part = rest.shift();
            if (part === "" || part === ".")
                continue;
            if (part === "..") {
                current = current.slice(0, current.lastIndexOf("/")) || "/";
                continue;
            }
            const next = current === "/" ? "/" + part : current + "/" + part;
            if (links && Object.prototype.hasOwnProperty.call(links, next)) {
                hops++;
                if (hops > maxLinkHops)
                    return { ok: false, real: "", visited: visited, reason: "more than " + maxLinkHops + " links on the way to its real file" };
                const target = links[next];
                if (target.startsWith("/"))
                    current = "/";
                rest = target.split("/").concat(rest);
                continue;
            }
            current = next;
            visited.push(current);
        }
        return { ok: true, real: current, visited: visited, reason: "" };
    }

    // The probe's lines → { names: { <name>: [candidate…] }, answered: [names], user }, a
    // candidate { path, links: { <path>: target }, stats: { <path>: { uid, mode, gid } },
    // problem }, in PATH order; `user` { uid, groups } or null. `answered`: the names the
    // probe got to (a "cand" line, found or not); it did not reach the others. Lines of
    // names not asked for, and malformed ones, are skipped; a second, different answer for
    // one path is a problem of the candidate.
    function programProbe(lines, names) {
        const found = Object.create(null);
        const last = Object.create(null);
        const answered = [];
        let user = null;
        for (const name of Array.isArray(names) ? names : []) {
            if (typeof name === "string")
                found[name] = [];
        }
        for (const line of Array.isArray(lines) ? lines.slice(0, 20000) : []) {
            if (typeof line !== "string")
                continue;
            const parts = line.split("\t");
            if (parts[0] === "user" && parts.length === 3 && user === null && /^\d+$/.test(parts[1])) {
                user = { uid: parts[1], groups: parts[2].split(" ").filter(group => /^\d+$/.test(group)) };
                continue;
            }
            const name = parts[1];
            if (typeof name !== "string" || !(name in found))
                continue;
            if (parts[0] === "cand" && parts.length === 3) {
                if (!answered.includes(name))
                    answered.push(name);
                last[name] = null;
                if (parts[2] === "")
                    continue;
                const candidate = { path: parts[2], links: Object.create(null), stats: Object.create(null), problem: "" };
                found[name].push(candidate);
                last[name] = candidate;
                continue;
            }
            const candidate = last[name];
            if (!candidate)
                continue;
            const conflict = (map, key, value) => {
                if (key in map && JSON.stringify(map[key]) !== JSON.stringify(value))
                    candidate.problem = "two answers for " + key;
                map[key] = value;
            };
            if (parts[0] === "link" && parts.length === 4 && _probePath(parts[2]) && parts[3] !== "" && !/[\u0000-\u001f\u007f]/.test(parts[3]))
                conflict(candidate.links, parts[2], parts[3]);
            else if (parts[0] === "stat" && parts.length === 6 && _probePath(parts[5]))
                conflict(candidate.stats, parts[5], { uid: parts[2], mode: parts[3], gid: parts[4] });
            else if (parts[0] === "bad" && parts.length === 2)
                candidate.problem = "a name on the way holds a line break or a tab";
            else if (parts[0] === "loop" && parts.length === 2)
                candidate.problem = "more than " + maxLinkHops + " links on the way to its real file";
        }
        return { names: found, answered: answered, user: user };
    }

    // One candidate's verdict → frozen { path, real, trusted, reason, owner, mode } (owner
    // and mode: the real file's). Nothing found: path "". `user`: the probe's.
    function programVerdict(candidate, user) {
        if (candidate && candidate.problem && !_probePath(candidate.path))
            return Object.freeze({ path: "", real: "", trusted: false, reason: candidate.problem, owner: "", mode: "" });
        if (!candidate || !_probePath(candidate.path))
            return Object.freeze({ path: "", real: "", trusted: false, reason: "not found", owner: "", mode: "" });
        const walked = programWalk(candidate.path, candidate.links);
        const real = walked.ok ? walked.real : "";
        const verdict = (trusted, reason) => {
            const stat = real !== "" ? candidate.stats?.[real] : undefined;
            return Object.freeze({ path: candidate.path, real: real, trusted: trusted, reason: reason,
                                   owner: stat?.uid ?? "", mode: stat?.mode ?? "" });
        };
        if (candidate.problem)
            return verdict(false, candidate.problem);
        if (!walked.ok)
            return verdict(false, walked.reason);
        const storeStat = candidate.stats?.["/nix/store"];
        const store = storeStat !== undefined && storeTrusted(storeStat, user);
        for (const path of walked.visited) {
            if (store && (path === "/nix/store" || programInStore(path)))
                continue;
            const stat = candidate.stats?.[path];
            if (!stat)
                return verdict(false, "could not be checked: " + path);
            if (!statTrusted(stat))
                return verdict(false, "others than root can change " + path);
        }
        return verdict(true, store && programInStore(real) ? "in the Nix store" : "root's, and only root can change it");
    }

    // The probe's lines, run with "first" → { <name>: verdict } for each name it answered
    function programVerdicts(lines, names) {
        const probe = programProbe(lines, names);
        const verdicts = {};
        for (const name of probe.answered)
            verdicts[name] = programVerdict(probe.names[name][0] ?? null, probe.user);
        return verdicts;
    }

    // The probe's lines, run with "all" → the paths of the trusted matches of `name`, in
    // PATH order
    function trustedPrograms(lines, name) {
        const probe = programProbe(lines, [name]);
        return (probe.names[name] ?? []).map(candidate => programVerdict(candidate, probe.user))
            .filter(verdict => verdict.trusted).map(verdict => verdict.path);
    }

    // How long a module's recheckPrograms() waits: 0 (now) when the last look was at least
    // `minMs` ago, or never, else the rest of that time
    function recheckDelay(lastMs, nowMs, minMs) {
        if (typeof lastMs !== "number" || !isFinite(lastMs) || lastMs <= 0 || typeof nowMs !== "number" || nowMs < lastMs)
            return 0;
        return Math.max(0, lastMs + minMs - nowMs);
    }

    // What a status says of a required program that was not found: on PATH, or (test mode)
    // in the module's stand-ins. `timedOutSeconds` > 0: the look-up did not answer in that time
    function missingProgramText(program, source, testPrograms, timedOutSeconds) {
        if (source === "test")
            return "needs the program " + program + ", which has no stand-in in " + testPrograms;
        return "needs the program " + program + ", which is not on PATH"
            + (timedOutSeconds > 0 ? " (the look-up did not answer within " + timedOutSeconds + " s)" : "");
    }

    // ---- Module test mode (API 1.10) ----
    //
    // On only where the shell's test entry points set it (ModuleHost.setTestMode, once,
    // before modules load): tests-modules.qml in process, a test tree through
    // TestSeams.moduleTestMode — never a variable alone, never a module. Then a module's
    // programs come from its manifest's testPrograms, Api.openUrl and Notifier.send record the
    // call instead of acting, and nothing a module starts reaches a pkexec that is not a
    // module's stand-in.

    readonly property string testStandInReason: "test stand-in"

    // Where a module's programs come from: "test" — its testPrograms directory — in test mode
    // when its manifest names one; else "path" (looked up on PATH and judged)
    function programSource(testMode, testPrograms) {
        return testMode === true && typeof testPrograms === "string" && testPrograms !== "" ? "test" : "path";
    }

    // The absolute directory of a module's stand-ins ("" without one); `directory` is the
    // module's canonical directory
    function testProgramsDirectory(directory, testPrograms) {
        if (typeof directory !== "string" || !directory.startsWith("/") || typeof testPrograms !== "string" || testPrograms === "")
            return "";
        return directory.replace(/\/+$/, "") + "/" + testPrograms.replace(/\/+$/, "");
    }

    // The stand-in pkexec of each module given ([{ directory, testPrograms }]) that names a
    // testPrograms directory: "<directory>/<testPrograms>/pkexec"
    function testStandIns(modules) {
        return (Array.isArray(modules) ? modules : [])
            .map(entry => testProgramsDirectory(entry?.directory, entry?.testPrograms))
            .filter(directory => directory !== "")
            .map(directory => directory + "/pkexec");
    }

    // `/bin/sh -c testProgramProbeScript sh <module directory> <stand-ins' directory> <name>…`,
    // run with PATH=probeToolPath: one line per name, "ok<TAB><name>" when the stand-in is
    // an executable regular file, not setuid or setgid, and both it and the stand-ins'
    // directory resolve, links followed, to a place inside the module's real directory (as
    // the file check demands of its .qml files) — else "no<TAB><name>". A link out of the
    // module (the directory, or a stand-in that leads to /usr/bin/pkexec) is no stand-in.
    readonly property string testProgramProbeScript: "mod=$(realpath -e -- \"$1\" 2>/dev/null) || mod=; dir=$2; shift 2; "
        + "real_dir=$(realpath -e -- \"$dir\" 2>/dev/null) || real_dir=; "
        + "case $real_dir in \"$mod\"/*) ;; *) real_dir= ;; esac; "
        + "for name; do ok=no; "
        + "if [ -n \"$mod\" ] && [ -n \"$real_dir\" ] && real=$(realpath -e -- \"$dir/$name\" 2>/dev/null); then "
        + "case $real in \"$mod\"/*) "
        + "if [ -f \"$real\" ] && [ -x \"$real\" ] && [ ! -u \"$real\" ] && [ ! -g \"$real\" ]; then ok=ok; fi ;; esac; fi; "
        + "printf '%s\\t%s\\n' \"$ok\" \"$name\"; done"

    // The probe's lines → { <name>: frozen verdict } for each of `names` it answered, in the
    // shape of programVerdict: there → { path: "<directory>/<name>", real: the same,
    // trusted: true, reason: testStandInReason }; not there → path "", untrusted, "no
    // stand-in". A stand-in is trusted because test mode only ever runs stand-ins: nothing it
    // starts is real, nothing runs as root
    function testProgramVerdicts(lines, names, directory) {
        const verdicts = {};
        const wanted = Array.isArray(names) ? names : [];
        for (const line of Array.isArray(lines) ? lines : []) {
            const parts = String(line).split("\t");
            if (parts.length !== 2 || (parts[0] !== "ok" && parts[0] !== "no") || !wanted.includes(parts[1])
                    || Object.prototype.hasOwnProperty.call(verdicts, parts[1]))
                continue;
            const path = parts[0] === "ok" && typeof directory === "string" && directory.startsWith("/") ? directory + "/" + parts[1] : "";
            verdicts[parts[1]] = Object.freeze(path !== ""
                ? { path: path, real: path, trusted: true, reason: testStandInReason, owner: "", mode: "" }
                : { path: "", real: "", trusted: false, reason: "no stand-in", owner: "", mode: "" });
        }
        return verdicts;
    }

    // Of a command a module starts (its CommandRunner, CommandAction, CommandQuery,
    // PrivilegedAction): "" when it may run, else why not. In test mode every word of the
    // command whose last path part is "pkexec" — the program, or one handed to `env`,
    // `timeout`, `setsid` and the like — must be one of `standIns` (testStandIns, and a
    // PrivilegedAction's own elevating program once checked), so a module's suites never meet
    // the real one. A guard against mistakes: a shell handed "pkexec" inside a script is not read.
    function testRunProblem(argv, testMode, standIns) {
        if (testMode !== true || !Array.isArray(argv))
            return "";
        const allowed = Array.isArray(standIns) ? standIns : [];
        const stray = argv.find(word => typeof word === "string" && word.replace(/^.*\//, "") === "pkexec" && !allowed.includes(word));
        if (stray === undefined)
            return "";
        return "test mode: pkexec is not run (" + show(stray.slice(0, 200)) + "); a module's suites use its stand-in, <testPrograms>/pkexec";
    }

    // ---- The test-mode gate for modules written for an API below 1.10 (removed by slice Z) ----
    //
    // REMOVED IN SLICE Z (notes/plans/api-next/migration.md): before 1.10 a module's suites
    // put their own stand-in into PrivilegedAction's `elevate`, wherever it lay. For such a
    // module the strict rule (only `<testPrograms>/pkexec`) is relaxed for `elevate` alone:
    // any program there runs unless it is the real pkexec — its real path that of the
    // system's pkexec, or a setuid or setgid file — and a check that fails or does not answer
    // counts as real. Everything else (its plain commands) follows the strict rule. The gate
    // is listed in the module's `deprecations` while test mode is on.

    readonly property string testStrictApi: "1.10"

    // Which pkexec rule a module's manifest API puts it under in test mode: "strict" from
    // testStrictApi on, "legacy" below it (the gate); an API that is not "major.minor": strict
    function testPkexecRule(api) {
        const module = parseApi(api);
        const strict = parseApi(testStrictApi);
        if (!module)
            return "strict";
        return module.major > strict.major || (module.major === strict.major && module.minor >= strict.minor) ? "strict" : "legacy";
    }

    // The module directories (of `directories`, canonical) whose files are on a JavaScript
    // stack (Error().stack: one "<function>@<url>:<line>" per line, innermost first), in that
    // order, each once. The shell's own files (qs:@/…) are no module's
    function stackDirectories(stack, directories) {
        const found = [];
        for (const line of typeof stack === "string" ? stack.slice(0, 65536).split("\n").slice(0, 200) : []) {
            const at = line.indexOf("@");
            if (at < 0)
                continue;
            const url = line.slice(at + 1).replace(/(:[0-9]+)+$/, "");
            if (!url.startsWith("file:///"))
                continue;
            const index = ModuleFileRules.directoryIndexOf(directories, url);
            if (index >= 0 && !found.includes(directories[index]))
                found.push(directories[index]);
        }
        return found;
    }

    // The rule for a call, from the rules of the modules whose code is on its stack
    // (testPkexecRule of each): "legacy" only when there is at least one and every one is;
    // else "strict" — a call no module is seen making, or one a 1.10 module takes part in
    function testCallRule(moduleRules) {
        const list = Array.isArray(moduleRules) ? moduleRules : [];
        return list.length > 0 && list.every(rule => rule === "legacy") ? "legacy" : "strict";
    }

    // PrivilegedAction's elevating program in test mode — "" or why not. Off test mode: ""
    // (as set). "strict": only a module's stand-in pkexec (one of `standIns`). "legacy" (the
    // gate): any absolute path, which the elevate probe then checks (testElevateProbeScript)
    function testElevateProblem(elevate, testMode, standIns, rule) {
        if (testMode !== true)
            return "";
        const program = Array.isArray(elevate) && typeof elevate[0] === "string" ? elevate[0] : "";
        if (rule === "legacy") {
            if (program.startsWith("/") && !program.includes("\n"))
                return "";
            return "test mode: a privileged run needs the module's stand-in pkexec, by its absolute path, as its elevating program";
        }
        if (program !== "" && Array.isArray(standIns) && standIns.includes(program))
            return "";
        return "test mode: a privileged run needs the module's stand-in pkexec (<testPrograms>/pkexec) as its elevating program";
    }

    // Where the system's pkexec is (NixOS: the setuid wrapper and the system profile's; Arch:
    // /usr/bin); the elevate probe also takes what `command -v pkexec` finds on
    // testPkexecLookupPath
    readonly property var systemPkexecPaths: ["/run/wrappers/bin/pkexec", "/run/current-system/sw/bin/pkexec", "/usr/bin/pkexec",
        "/usr/sbin/pkexec", "/usr/local/bin/pkexec", "/bin/pkexec", "/sbin/pkexec"]
    readonly property string testPkexecLookupPath: "/run/wrappers/bin:" + probeToolPath

    // `/bin/sh -c testElevateProbeScript sh <program> <lookup PATH> <system pkexec path>…`, run
    // with PATH=probeToolPath: one line — "stand-in" when the program's real path is an
    // executable regular file that is neither setuid nor setgid nor the same file as any
    // system pkexec (or the one found on the lookup PATH); "real" when it is one of those;
    // "unknown" when it cannot be resolved or is no executable file
    readonly property string testElevateProbeScript: "p=$1; lookup=$2; shift 2; "
        + "r=$(realpath -e -- \"$p\" 2>/dev/null) || { echo unknown; exit 0; }; "
        + "if [ -u \"$r\" ] || [ -g \"$r\" ]; then echo real; exit 0; fi; "
        + "found=$(PATH=$lookup command -v pkexec 2>/dev/null) && set -- \"$@\" \"$found\"; "
        + "for s; do if [ -e \"$s\" ] && { [ \"$r\" -ef \"$s\" ] || [ \"$r\" = \"$(realpath -e -- \"$s\" 2>/dev/null)\" ]; }; then echo real; exit 0; fi; done; "
        + "if [ -f \"$r\" ] && [ -x \"$r\" ]; then echo stand-in; else echo unknown; fi"

    // The elevate probe's answer → "" when the program may run as the module's stand-in, else
    // why not. Only an answer that is exactly "stand-in" lets it run: a failed or cut-short
    // probe, or anything else it printed, counts as the real pkexec
    function testElevateVerdict(ok, lines) {
        const answer = ok === true && Array.isArray(lines) && lines.length === 1 ? String(lines[0]) : "";
        if (answer === "stand-in")
            return "";
        return answer === "real"
            ? "test mode: the elevating program is the real pkexec (or a setuid file), not a stand-in; nothing runs"
            : "test mode: the elevating program could not be checked, so it counts as the real pkexec; nothing runs";
    }

    // What a module's `deprecations` say of the gate: one line for a module under it in test
    // mode, else nothing
    function testGateDeprecations(testMode, api) {
        if (testMode !== true || testPkexecRule(api) !== "legacy")
            return [];
        return ["module test mode: a pkexec stand-in outside testPrograms is still allowed for modules written for API below "
                + testStrictApi + "; this will be removed — declare api " + testStrictApi + " and put the stand-in in <testPrograms>/pkexec"];
    }

    // ---- Api.openUrl ----

    // The schemes Api.openUrl passes to xdg-open; file: only when asked for ({ allowFile: true })
    readonly property var openUrlSchemes: ["http", "https", "mailto"]

    // Why Api.openUrl refuses a link ("" when it may be opened): it must have a scheme
    // (`scheme:` at the start), the scheme must be http, https or mailto — or file with
    // options.allowFile === true — and the link no longer than 4096, without control
    // characters, not starting with "-"
    function openUrlProblem(url, options) {
        if (typeof url !== "string" || url === "")
            return "empty";
        if (url.length > 4096)
            return "longer than 4096 characters";
        if (/[\u0000-\u001f\u007f]/.test(url))
            return "holds control characters";
        if (url.startsWith("-"))
            return "starts with \"-\"";
        const match = /^([A-Za-z][A-Za-z0-9+.-]*):/.exec(url);
        if (!match)
            return "has no scheme (a bare path is not opened)";
        const scheme = match[1].toLowerCase();
        if (openUrlSchemes.includes(scheme))
            return "";
        if (scheme === "file")
            return options?.allowFile === true ? "" : "a file: link needs { allowFile: true }";
        return "the scheme " + scheme + ": is not opened (only " + openUrlSchemes.join(", ") + ", and file with allowFile)";
    }

    // ---- Facts the core publishes read-only (API 1.3) ----

    // Api.networks: the saved networks this computer joins, from NetworkProfiles' profiles
    // (Nmcli.profiles) and Wi-Fi details (Nmcli.wifiDetails) → [{ id, name, kind, active }].
    // `id` is the profile's UUID — the key system.vpnWithNetworks uses, as names may repeat.
    // Only Wi-Fi (not a hotspot: mode "ap" is this computer's own network) and Ethernet, and
    // not a port of a bridge or bond (the bridge is what joins). A Wi-Fi profile only once
    // its details are read: until then it could be a hotspot. `active` only when fully up
    // ("activated"), so a module does not act on a network still connecting. Those active
    // first, then the rest, each in the given order. Garbage is skipped, never thrown on.
    function apiNetworks(profiles, wifiDetails) {
        const details = isObject(wifiDetails) ? wifiDetails : {};
        const active = [];
        const inactive = [];
        for (const profile of Array.isArray(profiles) ? profiles : []) {
            if (!networkListed(profile, details))
                continue;
            const network = networkRow(profile.uuid, profile.name, profile.kind, profile.state === "activated");
            (network.active ? active : inactive).push(network);
        }
        return active.concat(inactive);
    }

    // Api.networksReady: the profiles have been read, and the Wi-Fi details of every Wi-Fi
    // profile apiNetworks looks at — so a list without a network means there is none. A
    // details read that failed leaves it false (unknown, never "none")
    function apiNetworksReady(listRead, profiles, wifiDetails) {
        if (listRead !== true)
            return false;
        const details = isObject(wifiDetails) ? wifiDetails : {};
        return (Array.isArray(profiles) ? profiles : []).every(profile =>
            !_joinable(profile) || profile.kind !== "wifi" || (has(details, profile.uuid) && isObject(details[profile.uuid])));
    }

    // Whether Api.networks lists `profile` (NetworkProfiles' profile, or a page's row built
    // on it) given the Wi-Fi details read so far: joinable, and a Wi-Fi profile only once its
    // details are read and say it is no hotspot. A saved network's card is a place only then,
    // so that no module's element is built for a network Api.networks does not name
    function networkListed(profile, wifiDetails) {
        if (!_joinable(profile))
            return false;
        if (profile.kind !== "wifi")
            return true;
        const details = isObject(wifiDetails) ? wifiDetails : {};
        const wifi = has(details, profile.uuid) ? details[profile.uuid] : null;
        return isObject(wifi) && wifi.mode !== "ap";
    }

    // A profile apiNetworks may list: Wi-Fi or Ethernet with a UUID, not a port
    function _joinable(profile) {
        return isObject(profile) && isString(profile.uuid, 200) && (profile.kind === "wifi" || profile.kind === "ethernet")
            && !(typeof profile.port === "string" && profile.port !== "");
    }

    // One row of Api.networks, each field of its kind (the name plain, on one line, capped)
    function networkRow(id, name, kind, active) {
        return { id: String(id), name: _plainLine(name, 200), kind: String(kind), active: active === true };
    }

    // What an element in a saved network's opened card gets as context (the Wi-Fi and
    // Ethernet pages' places): the network as Api.networks names it — { networkId: the
    // profile's UUID, name, kind ("wifi" | "ethernet"), active: fully up }
    function networkContext(profile) {
        const network = networkRow(profile?.uuid ?? "", profile?.name, profile?.kind ?? "", profile?.state === "activated");
        return { networkId: network.id, name: network.name, kind: network.kind, active: network.active };
    }

    // What an element on a Wi-Fi network's row in the network popup gets as context
    // (popup.network.wifi.row.title): the network as the saved networks' cards give it — the
    // profile saved for the SSID that Api.networks lists (`wifiDetails` read, no hotspot); of
    // several, the one up, else the one last used, else the first. A network not saved: no
    // profile, `networkId` "" and its SSID as the name (plain, on one line), not up
    function wifiRowContext(ssid, profiles, wifiDetails) {
        const details = isObject(wifiDetails) ? wifiDetails : {};
        let best = null;
        for (const profile of Array.isArray(profiles) ? profiles : []) {
            if (typeof ssid !== "string" || ssid === "" || !networkListed(profile, details) || profile.kind !== "wifi" || details[profile.uuid].ssid !== ssid)
                continue;
            const rank = [profile.state === "activated" ? 1 : 0, profile.active === true ? 1 : 0, typeof profile.lastUsed === "number" ? profile.lastUsed : 0];
            if (best === null || rank[0] > best.rank[0] || (rank[0] === best.rank[0] && (rank[1] > best.rank[1] || (rank[1] === best.rank[1] && rank[2] > best.rank[2]))))
                best = { profile: profile, rank: rank };
        }
        if (best !== null)
            return networkContext(best.profile);
        return { networkId: "", name: _plainLine(ssid, 200), kind: "wifi", active: false };
    }

    // What an element on the network popup's wired row gets as context
    // (popup.network.connections.wired.row.title): the wired profile up on `device` (the
    // Ethernet device the row is for), as its card gives it — fully up first. None up (or
    // no device): `networkId` and `name` "", not up
    function wiredRowContext(profiles, device) {
        let best = null;
        for (const profile of Array.isArray(profiles) ? profiles : []) {
            if (typeof device !== "string" || device === "" || !_joinable(profile) || profile.kind !== "ethernet"
                    || profile.active !== true || profile.device !== device)
                continue;
            if (best === null || (profile.state === "activated" && best.state !== "activated"))
                best = profile;
        }
        if (best !== null)
            return networkContext(best);
        return { networkId: "", name: "", kind: "ethernet", active: false };
    }

    // Text from outside (a network's or a VPN's name) on one line: control characters
    // become spaces, cut at `most`
    function _plainLine(value, most) {
        return typeof value === "string" ? value.replace(/[\u0000-\u001f\u007f\u2028\u2029]/g, " ").slice(0, most) : "";
    }

    // Api.vpnsUp: the VPNs up now (VpnManager.activeVpns) with their details (VpnManager
    // .details, by uuid) → [{ name, type, provider, fullTunnel, setsDns, routes }] — `type`
    // "wireguard", "vpn" … or "provider", `provider` the providerId of a provider's VPN ("" for
    // NetworkManager's); the last three vpnRouting's. In the given order; garbage skipped,
    // never thrown on.
    function apiVpnsUp(activeVpns, details) {
        const known = isObject(details) ? details : {};
        const list = [];
        for (const vpn of Array.isArray(activeVpns) ? activeVpns : []) {
            if (!isObject(vpn))
                continue;
            const type = typeof vpn.type === "string" ? vpn.type : "";
            const uuid = typeof vpn.uuid === "string" ? vpn.uuid : "";
            list.push(vpnUpRow(vpn.name, type, type === "provider" ? vpn.provider : "",
                               vpnRouting(vpn, uuid !== "" && has(known, uuid) ? known[uuid] : null)));
        }
        return list;
    }

    // One row of Api.vpnsUp; `routing` { fullTunnel, setsDns, routes }, each checked again
    // (vpnRoutingFields): what is wrong is unknown
    function vpnUpRow(name, type, provider, routing) {
        const fields = vpnRoutingFields(routing).fields;
        return { name: _plainLine(name, 200), type: typeof type === "string" ? type.slice(0, 40) : "",
            provider: typeof provider === "string" ? provider.slice(0, 32) : "",
            fullTunnel: fields.fullTunnel, setsDns: fields.setsDns, routes: fields.routes };
    }

    // What a VPN does with the traffic → { fullTunnel, setsDns, routes }, each null where
    // it is not known — never false for "not read":
    //   fullTunnel  true when it takes all traffic of IPv4 or of IPv6 (or both) that no more
    //               specific route sends elsewhere — the default route of that family, or
    //               "all" written as its two halves (0.0.0.0/1 and 128.0.0.0/1, ::/1 and
    //               8000::/1); false when it takes that of neither; null when not known
    //   setsDns     it brings DNS servers of its own while up
    //   routes      the networks it carries, canonical ("10.0.0.0/8", "0.0.0.0/0" for all);
    //               null when not known, or when there are more than maxRoutes
    // A provider's VPN: the three its entry reported (NetworkRules.vpnProviderEntries).
    // NetworkManager's, from its details (NetworkRules.vpnDetails):
    //   WireGuard by its profile: its peers' allowed-ips become its routes unless peer-routes
    //   is off (then the routes are not known from the profile, and it is a full tunnel only
    //   by what never-default rules out); the IPv6 ones do not count while IPv6 is disabled;
    //   a /0 counts as all of its family unless never-default is on for that family (not
    //   read: unknown), the two halves count whatever never-default says (they are no
    //   default route). peer-routes not read (an nmcli older than the field): on, as
    //   NetworkManager did before it had the setting.
    //   A plugin VPN by what NetworkManager made of it while up — a gateway, a /0 route or
    //   the two halves is a full tunnel, never-default on in both families is not.
    // DNS servers, and a plugin VPN's routes, are known only from a reading made while it
    // was "activated" (not while it was still activating).
    function vpnRouting(vpn, detail) {
        const unknown = { fullTunnel: null, setsDns: null, routes: null };
        if (!isObject(vpn))
            return unknown;
        if (vpn.type === "provider")
            return vpnRoutingFields({ fullTunnel: vpn.fullTunnel, setsDns: vpn.setsDns, routes: vpn.routes }).fields;
        if (!isObject(detail))
            return unknown;
        const up = detail.up === true;
        const strings = value => Array.isArray(value) ? value.filter(item => typeof item === "string") : [];
        const setsDns = up ? strings(detail.dns).length > 0 : null;
        const neverDefault = family => family === 4 ? detail.neverDefault4 : detail.neverDefault6;
        if (vpn.type === "wireguard") {
            if (!Array.isArray(detail.allowedIps))
                return { fullTunnel: null, setsDns: setsDns, routes: null };
            if (detail.peerRoutes === false) {
                const neither = neverDefault(4) === true && (neverDefault(6) === true || detail.ipv6Disabled === true);
                return { fullTunnel: neither ? false : null, setsDns: setsDns, routes: null };
            }
            const allowed = detail.ipv6Disabled === true
                ? detail.allowedIps.filter(item => typeof item === "string" && AddressRules.parseCidr(item.trim())?.family !== 6)
                : detail.allowedIps;
            const routes = _networks(allowed);
            if (routes === null)
                return { fullTunnel: null, setsDns: setsDns, routes: null };
            let fullTunnel = false;
            for (const family of [4, 6]) {
                const takes = _takesAll(routes, family);
                if (takes === "halves" || takes === "default" && neverDefault(family) === false) {
                    fullTunnel = true;
                    break;
                }
                if (takes === "default" && neverDefault(family) !== true)
                    fullTunnel = null;
            }
            return { fullTunnel: fullTunnel, setsDns: setsDns, routes: routes };
        }
        if (!up)
            return unknown;
        const all = _networks(strings(detail.routes));
        const routes = all === null ? null : all.filter(route => !AddressRules.contains("fe80::/10", route));
        const fullTunnel = neverDefault(4) === true && neverDefault(6) === true ? false
            : strings(detail.gateways).length > 0 ? true
            : routes === null ? null
            : _takesAll(routes, 4) !== "" || _takesAll(routes, 6) !== "";
        return { fullTunnel: fullTunnel, setsDns: setsDns, routes: routes };
    }

    // Whether canonical `routes` cover all of `family`: "default" (its /0), "halves" (its
    // two /1), or ""
    function _takesAll(routes, family) {
        const all = family === 4 ? ["0.0.0.0/0", ["0.0.0.0/1", "128.0.0.0/1"]] : ["::/0", ["::/1", "8000::/1"]];
        if (routes.includes(all[0]))
            return "default";
        return all[1].every(half => routes.includes(half)) ? "halves" : "";
    }

    // The most routes a VPN's row lists; with more, its routes are unknown (null), and the
    // shell says so in its log (vpnRoutesProblems, a provider's in its problems)
    readonly property int maxRoutes: 256

    // The three of vpnRouting as a provider (or a test) hands them, checked → { fields,
    // problems }: fullTunnel and setsDns true, false or null (absent: null); routes null or a
    // list of networks, each written canonically, the wrong ones left out — null when there
    // are more than maxRoutes
    function vpnRoutingFields(given) {
        const source = isObject(given) ? given : {};
        const problems = [];
        const flag = key => {
            const value = has(source, key) ? source[key] : undefined;
            if (value === undefined || value === null)
                return null;
            if (typeof value === "boolean")
                return value;
            problems.push(key + " is not true, false or null");
            return null;
        };
        const fullTunnel = flag("fullTunnel");
        const setsDns = flag("setsDns");
        const rawRoutes = has(source, "routes") ? source.routes : undefined;
        let routes = null;
        if (Array.isArray(rawRoutes)) {
            routes = _networks(rawRoutes);
            if (routes === null) {
                problems.push(routesProblem(rawRoutes));
            } else {
                const wrong = rawRoutes.filter(route => typeof route !== "string" || AddressRules.parseCidr(route.trim()) === null);
                if (wrong.length > 0)
                    problems.push("routes: not networks, left out: " + wrong.slice(0, 3).map(route => show(route)).join(", "));
            }
        } else if (rawRoutes !== undefined && rawRoutes !== null) {
            problems.push("routes is not a list of networks or null");
        }
        return { fields: { fullTunnel: fullTunnel, setsDns: setsDns, routes: routes }, problems: problems };
    }

    // Why a list of routes is not taken: more than maxRoutes networks in it
    function routesProblem(list) {
        return "routes: more than " + maxRoutes + " (" + (Array.isArray(list) ? list.length : 0) + " given) — not known";
    }

    // NetworkManager's VPNs whose routes are unknown for being too many (vpnRouting) →
    // sentences for the log, one per VPN
    function vpnRoutesProblems(vpns, details) {
        const known = isObject(details) ? details : {};
        const problems = [];
        for (const vpn of Array.isArray(vpns) ? vpns : []) {
            if (!isObject(vpn) || typeof vpn.uuid !== "string" || !has(known, vpn.uuid) || !isObject(known[vpn.uuid]))
                continue;
            const detail = known[vpn.uuid];
            const list = vpn.type === "wireguard" ? detail.allowedIps : detail.up === true ? detail.routes : null;
            if (Array.isArray(list) && _networks(list) === null)
                problems.push(_plainLine(vpn.name, 80) + ": " + routesProblem(list));
        }
        return problems;
    }

    // Networks as texts → the readable ones written canonically ("192.168.1.0/24"), each once
    // — or null when there are more than maxRoutes (the list is then not known whole)
    function _networks(list) {
        const source = Array.isArray(list) ? list : [];
        if (source.length > maxRoutes * 16)
            return null;
        const networks = [];
        for (const item of source) {
            const cidr = typeof item === "string" ? AddressRules.parseCidr(item.trim()) : null;
            if (cidr !== null && !networks.includes(cidr.network)) {
                if (networks.length === maxRoutes)
                    return null;
                networks.push(cidr.network);
            }
        }
        return networks;
    }

    // Api.localNetworks: the networks this computer is on, from NetworkManager's devices
    // (Nmcli.devices: { device, ipIface, type, ipv4 [], ipv6 [] }, addresses with their
    // prefix) → [{ device, kind, family, address, network }] — `device` the interface the
    // addresses are on (ipIface where known: a modem's wwan0, not its cdc-wdm0), `kind`
    // "wifi", "ethernet", "bridge", "modem" or "other", `family` 4 or 6, `address` this
    // computer's (canonical, no prefix), `network` the one it lies in ("192.168.1.0/24"; null
    // for a host prefix, /32 or /128 — DHCPv6 hands out a /128, whose network the router
    // announces apart). Only global addresses (not loopback, link-local, multicast or
    // unspecified), and of IPv6 not a deprecated one (`ipv6Flags`,
    // NetworkRules.ipv6AddressFlags: a privacy address already replaced — the current
    // temporary one is kept; where the flags are not known, null, every address is kept).
    // Not on a VPN's device: a loopback, tun, WireGuard, IP tunnel or VPN device, or one
    // named in `vpnInterfaces` (the VPNs' and the providers' interfaces) — except a Wi-Fi or
    // Ethernet device named there (an IPsec VPN reports the physical interface it runs on):
    // that one stays, less the VPNs' own addresses (`vpnAddresses`, with or without prefix),
    // which are left out wherever they show; a VPN that reports no addresses cannot be told
    // apart there. Each device and address once, in the given order, at most 64.
    function apiLocalNetworks(devices, vpnInterfaces, vpnAddresses, ipv6Flags) {
        const skipped = new Set((Array.isArray(vpnInterfaces) ? vpnInterfaces : []).filter(name => typeof name === "string" && name !== ""));
        const vpnOwn = new Set((Array.isArray(vpnAddresses) ? vpnAddresses : [])
            .map(address => typeof address === "string" ? AddressRules.parseCidr(address.trim().split("/")[0]) : null)
            .filter(address => address !== null).map(address => address.address));
        const flags = isObject(ipv6Flags) ? ipv6Flags : {};
        const rows = [];
        const seen = new Set();
        for (const device of Array.isArray(devices) ? devices : []) {
            if (!isObject(device) || typeof device.device !== "string")
                continue;
            if (localNetworkSkippedTypes.includes(device.type))
                continue;
            const name = typeof device.ipIface === "string" && device.ipIface !== "" ? device.ipIface : device.device;
            const physical = device.type === "wifi" || device.type === "ethernet";
            if (!physical && (skipped.has(device.device) || skipped.has(name)))
                continue;
            const kind = localNetworkKind(device.type);
            const addresses = (Array.isArray(device.ipv4) ? device.ipv4 : []).concat(Array.isArray(device.ipv6) ? device.ipv6 : []);
            for (const address of addresses) {
                const row = localNetworkRow(name, kind, address);
                if (row === null || seen.has(row.device + " " + row.address) || vpnOwn.has(row.address))
                    continue;
                const flag = row.family === 6 && has(flags, row.device + " " + row.address) ? flags[row.device + " " + row.address] : null;
                if (isObject(flag) && flag.deprecated === true)
                    continue;
                seen.add(row.device + " " + row.address);
                rows.push(row);
            }
        }
        return rows.slice(0, 64);
    }

    // NetworkManager's device types that are a VPN's or nobody's network
    readonly property var localNetworkSkippedTypes: ["loopback", "tun", "wireguard", "vpn", "ip-tunnel", "wifi-p2p"]

    // A device type (NetworkManager's GENERAL.TYPE) as Api.localNetworks names it
    function localNetworkKind(type) {
        const kinds = { "wifi": "wifi", "ethernet": "ethernet", "bridge": "bridge", "gsm": "modem", "cdma": "modem", "modem": "modem" };
        return typeof type === "string" && has(kinds, type) ? kinds[type] : "other";
    }

    // One row of Api.localNetworks — a device's name (1 to 15 printable characters, no "/" or
    // space), a kind of localNetworkKind's, and an address with its prefix ("192.168.1.23/24")
    // that is global — or null. A host prefix (/32, /128) gives the address, `network` null
    function localNetworkRow(device, kind, address) {
        if (typeof device !== "string" || !/^[^\u0000- \u007f/]{1,15}$/.test(device) || typeof address !== "string")
            return null;
        const parts = address.trim().split("/");
        if (parts.length !== 2)
            return null;
        const host = AddressRules.parseCidr(parts[0]);
        const network = AddressRules.parseCidr(address.trim());
        if (host === null || network === null || !_globalAddress(host))
            return null;
        return { device: device, kind: ["wifi", "ethernet", "bridge", "modem"].includes(kind) ? kind : "other",
            family: network.family, address: host.address, network: network.bits === (network.family === 4 ? 32 : 128) ? null : network.network };
    }

    // Not loopback, link-local, multicast, unspecified or broadcast: what `ip` calls scope
    // global (a unique local IPv6 address and a private IPv4 one are)
    function _globalAddress(host) {
        const local = host.family === 4 ? ["0.0.0.0/8", "127.0.0.0/8", "169.254.0.0/16", "224.0.0.0/3"]
            : ["::/127", "fe80::/10", "ff00::/8", "::ffff:0:0/96"];
        return !local.some(network => AddressRules.contains(network, host));
    }

    // Module test mode: what a suite says the network facts are (ModuleTestKit.setNetworks)
    // over the defaults (both read, no network, no VPN) → { facts: { networksReady, networks,
    // localNetworksReady, localNetworks, vpnsUp }, problems }. Rows go through the rows' own
    // checks: networks { id, name, kind ("wifi" | "ethernet"), active }, localNetworks
    // { device, kind, address: "<address>/<prefix>" } (family and network derived; one that
    // is not global left out), vpnsUp { name, type, provider, fullTunnel, setsDns, routes }.
    // A wrong field or row is left out and named in `problems`; so are localNetworks given
    // with localNetworksReady false, a state the shell never shows.
    function testNetworkFacts(given) {
        const source = isObject(given) ? given : {};
        const problems = [];
        if (given !== undefined && given !== null && !isObject(given))
            problems.push("the network facts are not an object");
        const known = ["networksReady", "networks", "localNetworksReady", "localNetworks", "vpnsUp"];
        for (const key of Object.keys(source))
            if (!known.includes(key))
                problems.push(key + ": not a network fact");
        const flag = key => {
            if (!has(source, key) || source[key] === undefined)
                return true;
            if (typeof source[key] === "boolean")
                return source[key];
            problems.push(key + ": not true or false");
            return true;
        };
        const rows = (key, make) => {
            if (!has(source, key) || source[key] === undefined)
                return [];
            if (!Array.isArray(source[key])) {
                problems.push(key + ": not a list");
                return [];
            }
            const list = [];
            source[key].slice(0, 64).forEach((row, index) => {
                const made = isObject(row) ? make(row) : null;
                if (made === null)
                    problems.push(key + "[" + index + "]: left out");
                else
                    list.push(made);
            });
            return list;
        };
        const networks = rows("networks", row => isString(row.id, 200) && (row.kind === "wifi" || row.kind === "ethernet")
            ? networkRow(row.id, row.name, row.kind, row.active) : null);
        const localNetworks = rows("localNetworks", row => localNetworkRow(row.device, row.kind, row.address));
        const vpnsUp = rows("vpnsUp", row => {
            const checked = vpnRoutingFields(row);
            checked.problems.forEach(problem => problems.push("vpnsUp: " + problem));
            return vpnUpRow(row.name, row.type, row.type === "provider" ? row.provider : "", checked.fields);
        });
        // As the shell has it: no local network listed while they are not read. Networks may
        // be listed while networksReady is false — the shell lists the Ethernet ones while
        // a Wi-Fi profile's details are still unread
        const networksReady = flag("networksReady");
        const localNetworksReady = flag("localNetworksReady");
        if (!localNetworksReady && localNetworks.length > 0)
            problems.push("localNetworks: left out, localNetworksReady is false (the shell lists none then)");
        return {
            facts: { networksReady: networksReady, networks: networks, localNetworksReady: localNetworksReady,
                localNetworks: localNetworksReady ? localNetworks : [], vpnsUp: vpnsUp },
            problems: problems
        };
    }

    // A JSON text of a list of plain objects → that list, the list, each entry and the
    // lists inside an entry frozen — what Api hands out (a module cannot change the core's copy)
    function frozenRows(text) {
        let rows = [];
        try {
            rows = JSON.parse(text);
        } catch (error) {
            rows = [];
        }
        if (!Array.isArray(rows))
            rows = [];
        const freeze = value => {
            if (value !== null && typeof value === "object") {
                for (const key of Object.keys(value))
                    freeze(value[key]);
                Object.freeze(value);
            }
            return value;
        };
        return Object.freeze(rows.map(row => freeze(row)));
    }

    // ---- What a module hands the core at run time ----

    // A fact's value checked against its declared type → { ok, value, error }. null and
    // undefined are "not known" (value null: no condition on it holds). Never throws.
    function factValue(type, value, options) {
        if (value === undefined || value === null)
            return { ok: true, value: null, error: "" };
        const bad = what => ({ ok: false, value: null, error: "not " + what + ": " + show(value) });
        switch (type) {
        case "bool":
            return typeof value === "boolean" ? { ok: true, value: value, error: "" } : bad("true or false");
        case "number":
            return isNumber(value) ? { ok: true, value: value, error: "" } : bad("a number");
        case "percent":
            return isNumber(value) && value >= 0 && value <= 100 ? { ok: true, value: value, error: "" } : bad("a number from 0 to 100");
        case "string":
            return typeof value === "string" && value.length <= 200 ? { ok: true, value: value, error: "" } : bad("a text of at most 200 characters");
        case "enum":
            return typeof value === "string" && (options ?? []).includes(value) ? { ok: true, value: value, error: "" }
                : bad("one of " + (options ?? []).join(", "));
        }
        return { ok: false, value: null, error: "the fact's type " + show(type) + " is unknown" };
    }

    // A module's setting key: its full key ("mod.<id>.<name>") for "<name>" or the full key
    // itself; "" when it is not the module's
    function ownSettingKey(id, key) {
        if (typeof key !== "string")
            return "";
        const full = key.startsWith("mod.") ? key : "mod." + id + "." + key;
        return ModuleManifestRules.isOwnSettingKey(id, full) ? full : "";
    }

    // A module's fact name: "<id>.<name>" for "<name>" or the full name; "" when not its
    function ownFactName(id, name) {
        if (typeof name !== "string")
            return "";
        const full = name.startsWith(id + ".") ? name : id + "." + name;
        return ModuleManifestRules.isOwnFact(id, full) ? full : "";
    }

    // Whether `value` may be written to a setting declared by `entry` (a schema entry): ""
    // when it may, else why not
    function settingValueProblem(entry, value) {
        if (!entry)
            return "not a declared setting";
        switch (entry.type) {
        case "bool":
            return typeof value === "boolean" ? "" : "not true or false";
        case "number":
        case "slider":
        case "interval":
            if (!isNumber(value))
                return "not a number";
            if ((entry.min !== undefined && value < entry.min) || (entry.max !== undefined && value > entry.max))
                return "outside " + entry.min + ".." + entry.max;
            return "";
        case "string":
            return typeof value === "string" && value.length <= 10000 ? "" : "not a text (at most 10000 characters)";
        case "stringList":
            return Array.isArray(value) && value.length <= 1000 && value.every(item => typeof item === "string") ? "" : "not a list of texts";
        case "enum":
            return (entry.options ?? []).some(option => option.value === value) ? "" : "not one of the options";
        }
        return "a setting of type " + show(entry.type) + " cannot be written by a module";
    }

    // The largest store a module may keep (its JSON, ModuleStore)
    readonly property int maxStoreBytes: 1024 * 1024

    // A store's content as JSON text, or null when it is not plain JSON or too large
    function storeText(data) {
        let text;
        try {
            text = JSON.stringify(data ?? {});
        } catch (error) {
            return null;
        }
        return typeof text === "string" && text.length <= maxStoreBytes ? text : null;
    }

    // A store file's text → its object ({} when missing, empty or not a JSON object)
    function parseStore(text) {
        if (typeof text !== "string" || text.trim() === "")
            return {};
        try {
            const parsed = JSON.parse(text);
            return isObject(parsed) ? parsed : {};
        } catch (error) {
            return {};
        }
    }

    // Whether a slot contribution's context has changed by value: plain data compared as
    // JSON, objects of Qt (a provider, an item) and functions by identity — one level deep,
    // as contexts are written ({ slot, editIndex, provider, close }). Never throws.
    function sameContext(a, b) {
        if (a === b)
            return true;
        if (!isObject(a) || !isObject(b))
            return false;
        const keys = Object.keys(a);
        if (keys.length !== Object.keys(b).length)
            return false;
        for (const key of keys) {
            if (!has(b, key))
                return false;
            const left = a[key];
            const right = b[key];
            if (left === right)
                continue;
            if (typeof left !== "object" || typeof right !== "object" || left === null || right === null
                    || _isQtObject(left) || _isQtObject(right))
                return false;
            let same = false;
            try {
                same = JSON.stringify(left) === JSON.stringify(right);
            } catch (error) {
                same = false;
            }
            if (!same)
                return false;
        }
        return true;
    }

    // ---- What a popup panel is given (API 1.15) ----

    // A popup panel's `opener`: the bar widget that opened it, from what PopupWidget passes
    // to Popup.open ({ widgetType, preset }), the bar's edge and whether a tap opened it.
    // Frozen { widgetType, preset, edge, byTouch }; null when no bar widget opened it (a
    // tray menu's request, nothing). Texts are kept to 64 characters.
    function popupOpener(contentData, edge, byTouch) {
        if (!isObject(contentData) || !isString(contentData.widgetType) || contentData.widgetType === "")
            return null;
        const text = value => typeof value === "string" ? value.slice(0, 64) : "";
        return Object.freeze({
            widgetType: text(contentData.widgetType),
            preset: text(contentData.preset),
            edge: text(edge),
            byTouch: byTouch === true
        });
    }

    // Whether two openers are the same (null for none)
    function sameOpener(a, b) {
        if (a === b)
            return true;
        if (!isObject(a) || !isObject(b))
            return false;
        return a.widgetType === b.widgetType && a.preset === b.preset && a.edge === b.edge && a.byTouch === b.byTouch;
    }

    // ---- Helpers (API 1.12) ----

    // Api.minuteNow: the start of the minute `ms` lies in; not a number: 0
    function minuteStart(ms) {
        return typeof ms === "number" && Number.isFinite(ms) ? Math.floor(ms / 60000) * 60000 : 0;
    }

    // A module's notification options as the core sends them (pure): a category in the
    // shell's own namespace ("x-qs-…", the shell's toast is "x-qs-shell"), given as the
    // category or as a hint, is dropped — a module's notification never looks like the
    // shell's. Everything else as given; not an object: {}
    function moduleNotifyOptions(options) {
        if (options === null || typeof options !== "object")
            return {};
        const isShells = value => typeof value === "string" && /^\s*x-qs-/i.test(value);
        const result = Object.assign({}, options);
        if (isShells(result.category))
            delete result.category;
        if (result.hints !== null && typeof result.hints === "object" && isShells(result.hints.category)) {
            const hints = Object.assign({}, result.hints);
            delete hints.category;
            result.hints = hints;
        }
        return result;
    }

    // module.log's levels; another word is "info"
    readonly property var logLevels: ["debug", "info", "warn", "error"]
    // A line's text is cut here (with "…"), a key here
    readonly property int logTextCap: 1000
    readonly property int logKeyCap: 200
    // How many keys a module's log remembers; past it the one written longest ago is dropped
    readonly property int maxLogKeys: 256

    // One line of module.log(level, text, key) → { level (one of logLevels), text (on one
    // line: line breaks, tabs and U+2028/2029 as spaces, other control and format
    // characters dropped (PrivilegedRules.unprintableCode), counted by code point, cut at
    // logTextCap), key (cut at logKeyCap; "" none), line ("[<id>] <text>"), memo (what the
    // key remembers once it is written: the level and the text), write }.
    // `written`: a Map of each key to the memo it wrote last (anything else: none). With a
    // key a line is written only when its level or text is not the one the key wrote last;
    // without one, always. A debug line with `debugOn` false is never written (and so not
    // remembered).
    function logEntry(moduleId, level, text, key, written, debugOn) {
        const cleanLevel = logLevels.includes(level) ? level : "info";
        const cleanText = _logText(text, logTextCap);
        const cleanKey = _logText(key, logKeyCap);
        const memo = cleanLevel + ":" + cleanText;
        const lastMemo = cleanKey !== "" && written instanceof Map ? written.get(cleanKey) : undefined;
        return {
            level: cleanLevel, text: cleanText, key: cleanKey, line: "[" + String(moduleId) + "] " + cleanText, memo: memo,
            write: (cleanLevel !== "debug" || debugOn === true) && (cleanKey === "" || lastMemo !== memo)
        };
    }

    function _logText(value, cap) {
        if (typeof value !== "string" && typeof value !== "number")
            return "";
        // As Notifier.plainText: a log line cannot be reordered or hidden by a format character
        const folded = String(value).replace(/[\r\n\t\v\f\u0085\u2028\u2029]+/g, " ");
        const characters = PrivilegedRules.characters(folded).filter(character => !PrivilegedRules.unprintableCode(character.codePointAt(0)));
        return characters.length > cap ? characters.slice(0, cap - 1).join("") + "…" : characters.join("");
    }

    // ---- A module's API for other modules (API 1.18) ----

    // What a provider's main offers as its `exports` (the manifest declares `exports`): the
    // object, or why there is none — and then its dependents count it as missing. A plain
    // QtObject of its own: not the main, nor anything with a `parent` (an Item), which would
    // lead a dependent up to the main; nor one of the shell's objects in `refused` (the
    // module handles, the host), which would hand a dependent the provider's own powers.
    // → { object, problem ("" when fine) }
    function exportsOf(main, refused) {
        if (!main)
            return { object: null, problem: "it declares exports but has no main to give them" };
        let value;
        try {
            value = main.exports;
        } catch (error) {
            return { object: null, problem: "its main's `exports` could not be read: " + error };
        }
        if (value === undefined)
            return { object: null, problem: "it declares exports but its main has no `exports` property" };
        if (value === null)
            return { object: null, problem: "its main's `exports` is null" };
        if (value === main)
            return { object: null, problem: "its main's `exports` is the main itself: it must be a QtObject of its own" };
        if (Array.isArray(refused) && refused.includes(value))
            return { object: null, problem: "its main's `exports` is the shell's (a module's handle?): it must be a QtObject of its own" };
        if (typeof value !== "object" || !_isQtObject(value))
            return { object: null, problem: "its main's `exports` is not a QtObject" };
        let hasParent = true;
        try {
            hasParent = "parent" in value;
        } catch (error) {
            hasParent = true;
        }
        if (hasParent)
            return { object: null, problem: "its main's `exports` has a `parent` (an Item?): it must be a plain QtObject" };
        return { object: value, problem: "" };
    }

    // An object of Qt's (a QtObject, an Item) rather than plain data
    function _isQtObject(value) {
        try {
            return typeof value.objectName === "string" && typeof value.destroy === "function";
        } catch (error) {
            return true;
        }
    }
}
