pragma Singleton

import Quickshell
import qs.singletons

// VPN providers — pure, tested in tests/VpnProvidersTest.qml: a VPN supplied by an object
// rather than NetworkManager (the contract: components/VpnProvider.qml). Its entries are
// addressed as "<providerId>:<entryId>" — NetworkManager's UUIDs are hexadecimal digits and
// dashes, so the colon keeps the two apart for good.
Singleton {
    id: root

    // A provider's id: a lower-case letter, then up to 31 of lower-case letters, digits,
    // "-" and "_" — no colon, nothing an object's prototype knows
    function isVpnProviderId(text) {
        return typeof text === "string" && /^[a-z][a-z0-9_-]{0,31}$/.test(text) && !_prototypeKeys.includes(text);
    }

    // An entry's id within its provider: 1 to 64 of letters, digits, ".", "_", "~", "-"
    function isVpnEntryId(text) {
        return typeof text === "string" && /^[A-Za-z0-9._~-]{1,64}$/.test(text) && !_prototypeKeys.includes(text);
    }

    readonly property var _prototypeKeys: ["__proto__", "constructor", "prototype", "hasOwnProperty", "toString", "valueOf",
        "__defineGetter__", "__defineSetter__", "__lookupGetter__", "__lookupSetter__", "isPrototypeOf", "propertyIsEnumerable",
        "toLocaleString"]

    // Provider ids the core keeps for providers of its own (the tests' stand-in): no module
    // may register one, whatever its module id
    readonly property var reservedProviderIds: ["fake"]

    // Whose provider a registration is, and whether it may have `id` (a valid provider id).
    // `owners`: [{ directory, moduleId, via }], each module directory the provider was traced
    // to — `via` "file": the folder of the file that declared it, "stack": a module's code on
    // the registering call's stack —, `moduleId` "" for a directory whose module has no
    // handle (a shadowed copy). → { moduleId, directory, problem, reportTo }: none traced,
    // the core's — any id; else exactly one module, whose provider id is its module id and
    // not reserved — the views, the own-provider places and the page slot take a provider's
    // id as its module's, so another id would put its VPNs and pages in that module's places.
    // `problem` "" when it may register; `reportTo` the module ids whose status gets the
    // refusal: traced to two modules, the ones whose code made it (the stack's), not the
    // module whose file was used.
    function providerRegistration(id, owners) {
        const list = Array.isArray(owners) ? owners : [];
        if (list.length === 0)
            return { moduleId: "", directory: "", problem: "", reportTo: [] };
        const idOf = owner => typeof owner?.moduleId === "string" ? owner.moduleId : "";
        const owner = list[0];
        const moduleId = idOf(owner);
        const refused = (problem, reportTo) => ({ moduleId: moduleId, directory: typeof owner?.directory === "string" ? owner.directory : "",
                                                  problem: problem, reportTo: problem === "" ? [] : reportTo ?? (moduleId !== "" ? [moduleId] : []) });
        if (list.length > 1) {
            const makers = list.filter(entry => entry?.via === "stack").map(idOf).filter(each => each !== "");
            return refused("a VPN provider traced to more than one module is refused", makers.length > 0 ? makers : list.map(idOf).filter(each => each !== ""));
        }
        if (moduleId === "")
            return refused("a VPN provider of a module that is not loaded is refused");
        if (reservedProviderIds.includes(id))
            return refused("the VPN provider id \"" + id + "\" is reserved for the shell");
        if (id !== moduleId)
            return refused("a VPN provider \"" + id + "\" refused: a module's provider id must be its module id \"" + moduleId + "\"");
        return refused("");
    }

    // A provider's pageUrl as the core may load it: a module's provider (`ownDirectory`, a
    // canonical module directory) only a file:// URL of a file in its own folder — in
    // `directories` (the module directories) the deepest holding it is its own, not one
    // nested inside it — and, symlinks followed, still in it: `resolved` is what realpath
    // made of the page's path and of `ownDirectory` ({ file, directory }), null when it could
    // not, undefined while not asked. The core's (`ownDirectory` "") as given.
    // → { url, problem, resolve }: `url` "" with the reason in `problem` when refused, ""
    // with `resolve` (the path to give realpath) while the link check has not answered.
    function providerPageUrl(pageUrl, ownDirectory, directories, resolved) {
        const url = typeof pageUrl === "string" ? pageUrl : "";
        if (url === "" || typeof ownDirectory !== "string" || ownDirectory === "")
            return { url: url, problem: "", resolve: "" };
        const list = Array.isArray(directories) ? directories : [];
        let path = "";
        try {
            path = url.startsWith("file:///") ? ModuleFileRules.canonicalPath(decodeURIComponent(url.slice(7).replace(/[?#].*$/, ""))) : "";
        } catch (error) {
            path = "";
        }
        const refused = why => ({ url: "", problem: "pageUrl " + JSON.stringify(url.slice(0, 200)) + " refused: " + why, resolve: "" });
        // The deepest module directory holding it is its own (list[-1] is undefined)
        if (!path.startsWith(ownDirectory + "/") || list[ModuleFileRules.directoryIndexOf(list, "file://" + encodeURI(path))] !== ownDirectory)
            return refused("not a file in the module's own folder");
        if (resolved === undefined)
            return { url: "", problem: "", resolve: path };
        const file = typeof resolved?.file === "string" ? resolved.file : "";
        const directory = typeof resolved?.directory === "string" ? resolved.directory : "";
        if (directory.startsWith("/") && file.startsWith(directory + "/"))
            return { url: url, problem: "", resolve: "" };
        return refused("it leaves the module's own folder through a link, or does not exist");
    }

    function vpnId(providerId, entryId) {
        return providerId + ":" + entryId;
    }

    // A VPN's id taken apart: { provider: "", entry: uuid } for NetworkManager's (no colon),
    // { provider, entry } for a provider's; null when it can be neither
    function vpnIdParts(id) {
        if (typeof id !== "string" || id === "")
            return null;
        const colon = id.indexOf(":");
        if (colon < 0)
            return _prototypeKeys.includes(id) ? null : { provider: "", entry: id };
        const provider = id.slice(0, colon), entry = id.slice(colon + 1);
        return isVpnProviderId(provider) && isVpnEntryId(entry) ? { provider: provider, entry: entry } : null;
    }

    readonly property var vpnStates: ["", "activating", "activated", "deactivating"]

    function _string(value, most) {
        return typeof value === "string" ? value.slice(0, most ?? 500) : "";
    }

    function _strings(value) {
        return Array.isArray(value) ? value.filter(item => typeof item === "string").slice(0, 64).map(item => item.slice(0, 200)) : [];
    }

    // A provider's `detail` in the shape vpnDetails gives NetworkManager's VPNs, so the views
    // read both alike: { service "", server, servers [], iface, interfaceName, addresses [],
    // dns [] } — anything else dropped, missing fields empty
    function vpnProviderDetail(detail) {
        const source = detail !== null && typeof detail === "object" && !Array.isArray(detail) ? detail : {};
        const read = key => Object.prototype.hasOwnProperty.call(source, key) ? source[key] : undefined;
        const server = _string(read("server"), 200);
        const servers = _strings(read("servers"));
        return {
            service: "", server: server, servers: servers.length > 0 ? servers : (server !== "" ? [server] : []),
            iface: /^[A-Za-z0-9_.-]{1,15}$/.test(_string(read("iface"))) ? read("iface") : "",
            interfaceName: /^[A-Za-z0-9_.-]{1,15}$/.test(_string(read("interfaceName"))) ? read("interfaceName") : "",
            addresses: _strings(read("addresses")), dns: _strings(read("dns"))
        };
    }

    // What a provider reports as its entries, checked: { entries, problems } — `entries`
    // [{ id, name, state, attention, detail, active, status, busy, fullTunnel, setsDns, routes }]
    // in the provider's order, `problems` sentences for the log. An entry whose id, name or
    // state is wrong (not an object; id not isVpnEntryId, or repeated; name not a string;
    // state not one of vpnStates) is dropped. A wrong optional field is set to its default
    // and reported: attention (null, or { reason: a non-empty string, action: a string, ""
    // none }), detail (vpnProviderDetail), active (a bool; else whether state is not ""),
    // status (text, at most 80; else ""), busy (a bool; else false), fullTunnel, setsDns and
    // routes (ModuleRules.vpnRoutingFields: null where absent or wrong — unknown).
    function vpnProviderEntries(providerId, raw) {
        const entries = [];
        const problems = [];
        const name = String(providerId);
        let list = raw;
        if (!Array.isArray(list)) {
            if (list !== undefined && list !== null)
                problems.push(name + ": entries is not a list");
            list = [];
        }
        const seen = {};
        list.slice(0, 64).forEach((entry, index) => {
            const where = name + ": entry " + index;
            if (entry === null || typeof entry !== "object" || Array.isArray(entry)) {
                problems.push(where + " is not an object");
                return;
            }
            const read = key => {
                try {
                    return Object.prototype.hasOwnProperty.call(entry, key) ? entry[key] : undefined;
                } catch (error) {
                    return undefined;
                }
            };
            const id = read("id");
            if (!isVpnEntryId(id)) {
                problems.push(where + ": id " + JSON.stringify(String(id)).slice(0, 80) + " is not 1–64 letters, digits, . _ ~ -");
                return;
            }
            if (seen[id] === true) {
                problems.push(where + ": id " + id + " repeated");
                return;
            }
            const entryName = read("name");
            if (typeof entryName !== "string") {
                problems.push(where + " (" + id + "): name is not text");
                return;
            }
            const state = read("state") ?? "";
            if (!vpnStates.includes(state)) {
                problems.push(where + " (" + id + "): state " + JSON.stringify(String(state)).slice(0, 40) + " is not one of activating, activated, deactivating, \"\"");
                return;
            }
            seen[id] = true;
            let attention = read("attention") ?? null;
            if (attention !== null) {
                const reason = typeof attention === "object" ? attention.reason : undefined;
                const action = typeof attention === "object" ? (attention.action ?? "") : undefined;
                if (typeof reason !== "string" || reason.trim() === "" || typeof action !== "string") {
                    problems.push(where + " (" + id + "): attention is not { reason, action }");
                    attention = null;
                } else {
                    attention = { reason: reason.slice(0, 300), action: action.slice(0, 40) };
                }
            }
            const rawDetail = read("detail");
            if (rawDetail !== undefined && rawDetail !== null && (typeof rawDetail !== "object" || Array.isArray(rawDetail)))
                problems.push(where + " (" + id + "): detail is not an object");
            let active = read("active");
            if (active !== undefined && typeof active !== "boolean")
                problems.push(where + " (" + id + "): active is not true or false");
            if (typeof active !== "boolean")
                active = state !== "";
            const status = read("status");
            if (status !== undefined && status !== null && typeof status !== "string")
                problems.push(where + " (" + id + "): status is not text");
            const entryBusy = read("busy");
            if (entryBusy !== undefined && entryBusy !== null && typeof entryBusy !== "boolean")
                problems.push(where + " (" + id + "): busy is not true or false");
            const routing = ModuleRules.vpnRoutingFields({ fullTunnel: read("fullTunnel"), setsDns: read("setsDns"), routes: read("routes") });
            routing.problems.forEach(problem => problems.push(where + " (" + id + "): " + problem));
            entries.push({
                id: id, name: entryName.trim().slice(0, 200) || id, state: state, attention: attention,
                detail: vpnProviderDetail(rawDetail), active: active,
                status: typeof status === "string" ? status.trim().slice(0, 80) : "", busy: entryBusy === true,
                fullTunnel: routing.fields.fullTunnel, setsDns: routing.fields.setsDns, routes: routing.fields.routes
            });
        });
        if (list.length > 64)
            problems.push(name + ": more than 64 entries, the rest left out");
        return { entries: entries, problems: problems };
    }

    // One provider's entries as VPNs in the shape of NetworkManager's ({ uuid, name, type,
    // kind, state, active, … }), so the views and vpnWithNetworkPlan take both: `uuid` is the
    // id "<provider>:<entry>", `type` "provider", plus provider, entryId, typeName, glyph,
    // attention, status, busy, fullTunnel, setsDns, routes. `read` { providerId, typeName, glyph, entries (vpnProviderEntries') }
    function vpnProviderVpns(read) {
        return (read?.entries ?? []).map(entry => ({
            uuid: vpnId(read.providerId, entry.id), name: entry.name, type: "provider", kind: "vpn",
            state: entry.state, active: entry.active, device: "", autoconnect: false, priority: 0, lastUsed: 0,
            provider: read.providerId, entryId: entry.id, typeName: read.typeName || "VPN", glyph: read.glyph || "",
            attention: entry.attention, status: entry.status ?? "", busy: entry.busy === true,
            fullTunnel: entry.fullTunnel ?? null, setsDns: entry.setsDns ?? null, routes: entry.routes ?? null
        }));
    }

    // NetworkManager's VPNs and the providers' in one list: those up first, then the most
    // recently used; ties keep their order — NetworkManager's first, then each provider's
    // in the order the providers were registered, entries in the provider's order
    function mergedVpns(nmVpns, providerVpns) {
        return (nmVpns ?? []).concat(providerVpns ?? [])
            .map((vpn, index) => ({ vpn: vpn, index: index }))
            .sort((a, b) => (b.vpn.active - a.vpn.active) || ((b.vpn.lastUsed ?? 0) - (a.vpn.lastUsed ?? 0)) || (a.index - b.index))
            .map(item => item.vpn);
    }

    // The glyph for the VPNs up (the bar, the popup's header): WireGuard's when every one is
    // WireGuard (and with none), one provider's own when every one is that provider's and it
    // has one, else the padlock
    function activeVpnGlyph(activeVpns) {
        const list = activeVpns ?? [];
        if (list.every(vpn => vpn.type === "wireguard"))
            return "󰒃";
        const glyph = list[0]?.glyph ?? "";
        if (glyph !== "" && list.every(vpn => vpn.provider !== undefined && vpn.provider === list[0].provider))
            return glyph;
        return "󰌾";
    }

    // A VPN's own glyph: WireGuard's, a provider's own, else the padlock
    function vpnGlyph(vpn) {
        return vpn?.type === "wireguard" ? "󰒃" : (vpn?.glyph || "󰌾");
    }

    // A provider's failure as a notification, as NetworkManager's are (NetworkProfiles):
    // { title "<what> failed", body: the reason }
    function vpnFailureNotice(what, reason) {
        const doing = _string(what, 200).trim() || "A VPN action";
        return { title: doing + " failed", body: _string(reason, 500).trim() || "It did not say why." };
    }

    // The kill switch does not cover provider VPNs (the owner's decision):
    // the sentence saying so while blocking is on and the VPN is up or coming up ("" when
    // there is nothing to say). `note` the provider's own wording (its lockdownNote), else
    // the shell's. `whateverState` true: whenever blocking is on, up or not — the VPN page's
    // card states the limit always; the popup's row only while it matters.
    function lockdownProviderNote(blocking, vpn, note, whateverState) {
        if (!blocking || typeof vpn?.provider !== "string" || vpn.provider === "")
            return "";
        if (whateverState !== true && vpn.state !== "activating" && vpn.state !== "activated")
            return "";
        const own = _string(note, 300).trim();
        return own !== "" ? own : (vpn.typeName || "This VPN") + " is not let through while traffic outside a VPN is blocked: "
            + "it may not connect or carry traffic.";
    }

    // Whether two slot contexts (VpnExtras, the provider's page) say the same, so a
    // provider re-read that changed nothing for this entry does not poke its contribution:
    // the same keys; objects that are not plain data (the provider) the same object;
    // functions (close) alike as functions; the rest the same as JSON
    function sameVpnContext(a, b) {
        if (a === b)
            return true;
        if (a === null || b === null || typeof a !== "object" || typeof b !== "object")
            return false;
        const keys = Object.keys(a);
        if (keys.length !== Object.keys(b).length)
            return false;
        for (const key of keys) {
            if (!Object.prototype.hasOwnProperty.call(b, key))
                return false;
            const left = a[key], right = b[key];
            if (left === right)
                continue;
            if (typeof left === "function" || typeof right === "function") {
                if (typeof left !== typeof right)
                    return false;
                continue;
            }
            if (key === "provider")
                return false;
            try {
                if (JSON.stringify(left) !== JSON.stringify(right))
                    return false;
            } catch (error) {
                return false;
            }
        }
        return true;
    }
}
