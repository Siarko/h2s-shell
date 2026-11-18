pragma Singleton

import Quickshell
import QtQuick


// The module system's decisions (notes/plans/modules.md) — pure, so tests/ModuleRulesTest.qml
// checks them without a module on disk: reading and checking a manifest, whether its API
// version fits the shell's, the namespaces a module's contributions must stay in, the import
// check (a warning, by the owner's decision), which of two modules with one id wins, the
// state a module is in, and the contributions of several modules merged into the lists the
// core's registries will read. No file, no process, no other singleton; ModuleHost does the
// I/O. Nothing here throws on any input: a manifest is written by someone else.
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
    readonly property string apiVersion: "1.9"

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
        // The VPN provider seam's three (notes/plans/tailscale.md §3; VpnManager.extrasFor and
        // pageOf ask here first): one contribution per provider, the one of the module whose
        // id is the provider's providerId — a module's provider uses its module id
        // (`VpnProvider { providerId: module.moduleId }`). A provider that is no module's keeps
        // its own rowExtras, cardExtras and pageUrl.
        { name: "network.vpn.row", since: "1.1",
          where: "the network popup's VPN section (panels/network/VpnSection.qml), under the row of each VPN of the module's provider",
          context: "{ slot, vpnId, entryId, vpn, provider, otherVpnsUp: [names of the other VPNs up] }" },
        { name: "network.vpn.card", since: "1.1",
          where: "Settings → System → Network → VPN, on the card of each VPN of the module's provider, while the card is open",
          context: "{ slot, vpnId, entryId, vpn, provider, otherVpnsUp, open: bool }" },
        { name: "network.vpn.page", since: "1.1",
          where: "a page over Settings → System → Network → VPN, opened from the card's \"Settings…\", in the core's frame (Back, title, scrolling)",
          context: "{ slot, vpnId, entryId, vpn, provider, otherVpnsUp, close: function }" }
    ]
    readonly property var slotNames: slotTable.map(entry => entry.name)

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
    //   disabled         turned off in Settings → Modules (Config.disabledModules)
    //   failed           its manifest is unusable, or its main could not be created
    //   incompatible     written for another module API: another major, a newer minor than
    //                    the shell's, or one below the shell's floor (apiFloor)
    //   missing-program  a program in requires.programs is not on PATH
    //   duplicate        another module with the same id came first (search-path order)
    //   pending          waiting for the check of its required programs
    //   safe-mode        the shell started in safe mode: no module is loaded
    readonly property var states: ["loaded", "disabled", "failed", "incompatible", "missing-program",
                                   "duplicate", "pending", "safe-mode"]

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
    // TRUSTED means that nobody but root can change what runs: the program's real file is in
    // the Nix store, or it is owned by root and writable by no one else — and so is every
    // directory above the path found, above each link on the way to the real file, and above
    // the real file (each judged where its name leads: `stat -L`), up to "/". A path in the
    // Nix store is not looked above (the store is read-only; its own directory is not root's
    // alone on every install). NixOS: /run/current-system/sw/bin leads into the store, the
    // setuid wrappers are root's files under /run/wrappers; Arch: root's /usr/bin. Anything
    // not read — a stat missing, a link that does not resolve — is untrusted, never trusted.
    // A guard against mistakes (a program in a directory the user owns, handed on to run as
    // root), not against a process that can already write where it likes.

    // Links followed from the path found to the real file; a longer chain is untrusted
    readonly property int maxLinkHops: 16
    // How often a module may ask for its programs to be looked up again (recheckDelay)
    readonly property int recheckMinMs: 2000

    // `sh -c programProbeScript sh <"first" | "all"> <name>…`: each name on PATH (absolute
    // entries only; an executable regular file), the first match or all of them. Per match,
    // tab-separated lines:
    //   cand <name> <path>             a match ("" after the name: none at all)
    //   real <name> <readlink -f>      its real file (missing: it does not resolve)
    //   hop  <name> <path>             each link on the way, made absolute, at most maxLinkHops
    //   stat <name> <uid> <mode> <path>  every directory above the path, each hop and the
    //                                  real file, and the real file itself (stat -L; octal
    //                                  mode); nothing at or above a path under /nix/store/
    readonly property string programProbeScript: [
        "mode=$1; shift",
        "set -f",
        "say() { s=$(stat -L -c '%u %a' -- \"$2\") && printf 'stat\\t%s\\t%s\\t%s\\t%s\\n' \"$1\" \"${s% *}\" \"${s#* }\" \"$2\"; }",
        "look() {",
        "  n=$1; p=$2",
        "  printf 'cand\\t%s\\t%s\\n' \"$n\" \"$p\"",
        "  r=$(readlink -f -- \"$p\") && printf 'real\\t%s\\t%s\\n' \"$n\" \"$r\" || r=",
        "  set -- \"$p\"",
        "  h=$p; i=0",
        "  while [ -L \"$h\" ] && [ \"$i\" -lt " + maxLinkHops + " ]; do",
        "    t=$(readlink -- \"$h\") || break",
        "    case $t in /*) h=$t ;; *) h=${h%/*}/$t ;; esac",
        "    printf 'hop\\t%s\\t%s\\n' \"$n\" \"$h\"",
        "    set -- \"$@\" \"$h\"",
        "    i=$((i + 1))",
        "  done",
        "  [ -n \"$r\" ] && set -- \"$@\" \"$r\"",
        "  for e; do",
        "    case $e in /nix/store/*) continue ;; esac",
        "    a=$e",
        "    while [ \"$a\" != / ]; do",
        "      a=${a%/*}; [ -n \"$a\" ] || a=/",
        "      say \"$n\" \"$a\"",
        "    done",
        "  done",
        "  case $r in ''|/nix/store/*) ;; *) say \"$n\" \"$r\" ;; esac",
        "}",
        "for n; do",
        "  hit=",
        "  IFS=:",
        "  for d in $PATH; do",
        "    case $d in /*) ;; *) continue ;; esac",
        "    p=$d/$n",
        "    if [ -f \"$p\" ] && [ -x \"$p\" ]; then hit=1; look \"$n\" \"$p\"; [ \"$mode\" = all ] || break; fi",
        "  done",
        "  unset IFS",
        "  [ -n \"$hit\" ] || printf 'cand\\t%s\\t\\n' \"$n\"",
        "done"
    ].join("\n")

    // An absolute path as the probe prints it: no control character, not too long
    function _probePath(value) {
        return typeof value === "string" && value.startsWith("/") && value.length <= 4096 && !/[\u0000-\u001f\u007f]/.test(value);
    }

    // In the Nix store (and not leaving it by "..")
    function programInStore(path) {
        return typeof path === "string" && path.startsWith("/nix/store/") && !path.split("/").includes("..");
    }

    // The directories above an absolute path, nearest first, up to "/" — the steps the probe
    // takes (strip the last "/…"; "/" when nothing is left)
    function programAncestors(path) {
        const list = [];
        if (!_probePath(path))
            return list;
        let above = path;
        while (above !== "/") {
            above = above.slice(0, above.lastIndexOf("/"));
            if (above === "")
                above = "/";
            list.push(above);
        }
        return list;
    }

    // One stat's verdict: owned by root, no write bit for the group or others
    function statTrusted(stat) {
        const mode = stat?.mode;
        const bits = typeof mode === "string" && /^[0-7]{1,5}$/.test(mode) ? parseInt(mode, 8) : -1;
        return stat?.uid === "0" && bits >= 0 && (bits & 0o022) === 0;
    }

    // The probe's lines → { names: { <name>: [candidate…] }, answered: [names] }, a candidate
    // { path, hops, real, stats: { <path>: { uid, mode } } }, in PATH order. `answered`: the
    // names the probe got to (a "cand" line, found or not); it did not reach the others.
    // Lines of names not asked for, and malformed ones, are skipped.
    function programProbe(lines, names) {
        const found = Object.create(null);
        const last = Object.create(null);
        const answered = [];
        for (const name of Array.isArray(names) ? names : []) {
            if (typeof name === "string")
                found[name] = [];
        }
        for (const line of Array.isArray(lines) ? lines.slice(0, 20000) : []) {
            if (typeof line !== "string")
                continue;
            const parts = line.split("\t");
            const name = parts[1];
            if (typeof name !== "string" || !(name in found))
                continue;
            if (parts[0] === "cand" && parts.length === 3) {
                if (!answered.includes(name))
                    answered.push(name);
                last[name] = null;
                if (parts[2] === "")
                    continue;
                const candidate = { path: parts[2], hops: [], real: "", stats: Object.create(null) };
                found[name].push(candidate);
                last[name] = candidate;
                continue;
            }
            const candidate = last[name];
            if (!candidate)
                continue;
            if (parts[0] === "hop" && parts.length === 3)
                candidate.hops.push(parts[2]);
            else if (parts[0] === "real" && parts.length === 3)
                candidate.real = parts[2];
            else if (parts[0] === "stat" && parts.length === 5 && _probePath(parts[4]))
                candidate.stats[parts[4]] = { uid: parts[2], mode: parts[3] };
        }
        return { names: found, answered: answered };
    }

    // One candidate's verdict → frozen { path, real, trusted, reason, owner, mode } (owner
    // and mode: the real file's, "" in the store). Nothing found: path "".
    function programVerdict(candidate) {
        if (!candidate || !_probePath(candidate.path))
            return Object.freeze({ path: "", real: "", trusted: false, reason: "not found", owner: "", mode: "" });
        const real = _probePath(candidate.real) ? candidate.real : "";
        const verdict = (trusted, reason) => {
            const stat = real !== "" ? candidate.stats?.[real] : undefined;
            return Object.freeze({ path: candidate.path, real: real, trusted: trusted, reason: reason,
                                   owner: stat?.uid ?? "", mode: stat?.mode ?? "" });
        };
        const hops = Array.isArray(candidate.hops) ? candidate.hops : [];
        if (hops.length >= maxLinkHops)
            return verdict(false, "more than " + maxLinkHops + " links on the way to its real file");
        if (real === "")
            return verdict(false, "its real file could not be found");
        const needed = [];
        for (const entry of [candidate.path].concat(hops, [real])) {
            if (!_probePath(entry))
                return verdict(false, "a link on the way could not be read");
            if (programInStore(entry))
                continue;
            for (const directory of programAncestors(entry)) {
                if (!needed.includes(directory))
                    needed.push(directory);
            }
        }
        const inStore = programInStore(real);
        if (!inStore)
            needed.push(real);
        for (const path of needed) {
            const stat = candidate.stats?.[path];
            if (!stat)
                return verdict(false, "could not be checked: " + path);
            if (!statTrusted(stat))
                return verdict(false, "others than root can change " + path);
        }
        return verdict(true, inStore ? "in the Nix store" : "root's, and only root can change it");
    }

    // The probe's lines, run with "first" → { <name>: verdict } for each name it answered
    function programVerdicts(lines, names) {
        const probe = programProbe(lines, names);
        const verdicts = {};
        for (const name of probe.answered)
            verdicts[name] = programVerdict(probe.names[name][0] ?? null);
        return verdicts;
    }

    // The probe's lines, run with "all" → the paths of the trusted matches of `name`, in
    // PATH order
    function trustedPrograms(lines, name) {
        return (programProbe(lines, [name]).names[name] ?? []).map(candidate => programVerdict(candidate))
            .filter(verdict => verdict.trusted).map(verdict => verdict.path);
    }

    // How long a module's recheckPrograms() waits: 0 (now) when the last look was at least
    // `minMs` ago, or never, else the rest of that time
    function recheckDelay(lastMs, nowMs, minMs) {
        if (typeof lastMs !== "number" || !isFinite(lastMs) || lastMs <= 0 || typeof nowMs !== "number" || nowMs < lastMs)
            return 0;
        return Math.max(0, lastMs + minMs - nowMs);
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
    // not a port of a bridge or bond (the bridge is what joins). `active` only when fully up
    // ("activated"), so a module does not act on a network still connecting. Those active
    // first, then the rest, each in the given order. Garbage is skipped, never thrown on.
    function apiNetworks(profiles, wifiDetails) {
        const details = isObject(wifiDetails) ? wifiDetails : {};
        const active = [];
        const inactive = [];
        for (const profile of Array.isArray(profiles) ? profiles : []) {
            if (!isObject(profile) || !isString(profile.uuid, 200))
                continue;
            if (profile.kind !== "wifi" && profile.kind !== "ethernet")
                continue;
            if (typeof profile.port === "string" && profile.port !== "")
                continue;
            const wifi = has(details, profile.uuid) ? details[profile.uuid] : null;
            if (profile.kind === "wifi" && isObject(wifi) && wifi.mode === "ap")
                continue;
            const network = { id: profile.uuid, name: typeof profile.name === "string" ? profile.name : "",
                kind: profile.kind, active: profile.state === "activated" };
            (network.active ? active : inactive).push(network);
        }
        return active.concat(inactive);
    }

    // Api.vpnsUp: the VPNs up now (VpnManager.activeVpns) → [{ name, type, provider }] —
    // `type` "wireguard", "vpn" … or "provider", `provider` the providerId of a provider's VPN
    // ("" for NetworkManager's). In the given order; garbage skipped, never thrown on.
    function apiVpnsUp(activeVpns) {
        const list = [];
        for (const vpn of Array.isArray(activeVpns) ? activeVpns : []) {
            if (!isObject(vpn))
                continue;
            const type = typeof vpn.type === "string" ? vpn.type : "";
            list.push({ name: typeof vpn.name === "string" ? vpn.name : "", type: type,
                provider: type === "provider" && typeof vpn.provider === "string" ? vpn.provider : "" });
        }
        return list;
    }

    // A JSON text of a list of plain objects → that list, the list and each entry frozen —
    // what Api hands out (a module cannot change the core's copy)
    function frozenRows(text) {
        let rows = [];
        try {
            rows = JSON.parse(text);
        } catch (error) {
            rows = [];
        }
        if (!Array.isArray(rows))
            rows = [];
        return Object.freeze(rows.map(row => Object.freeze(row)));
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

    // An object of Qt's (a QtObject, an Item) rather than plain data
    function _isQtObject(value) {
        try {
            return typeof value.objectName === "string" && typeof value.destroy === "function";
        } catch (error) {
            return true;
        }
    }
}
