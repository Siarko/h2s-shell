import QtQuick
import qs.singletons

// ModuleDependencyRules (pure): the chain a module brings when installed or updated — there,
// update, download, unresolved, incompatible, soft offers, the limits and cycles —, the
// install order, taking back a run that failed halfway, the dependents Remove and Disable
// name, and the dependencies left without a user. Malformed input never reads as fine.
TestCase {
    id: suite
    suiteName: "ModuleDependencyRules"

    readonly property var _context: ({ shellApi: "1.36" })

    // A manifest: `uses` as { id: "1.0" } (hard) or { id: { version, optional, source } }
    function _manifest(id, version, exportsVersion, uses, api) {
        const list = [];
        for (const usedId of Object.keys(uses ?? {})) {
            const given = uses[usedId];
            list.push(typeof given === "string" ? { id: usedId, version: given, optional: false }
                      : { id: usedId, version: given.version, optional: given.optional === true, source: given.source });
        }
        return { id: id, name: id.charAt(0).toUpperCase() + id.slice(1), version: version, api: api ?? "1.36",
                 exports: exportsVersion === null ? null : { version: exportsVersion }, uses: list };
    }

    function _installed(id, version, exportsVersion, origin, address, uses) {
        const manifest = _manifest(id, version, exportsVersion, uses);
        manifest.origin = origin;
        manifest.address = address ?? "";
        return manifest;
    }

    function _entry(plan, id) {
        return plan.entries.find(entry => entry.id === id) ?? null;
    }

    function _plan(rootManifest, installed, fetched, context) {
        return ModuleDependencyRules.plan(rootManifest, installed, fetched, context ?? _context);
    }

    function run() {
        _chainOfTwo();
        _there();
        _missing();
        _incompatible();
        _updates();
        _twoDependents();
        _soft();
        _cycles();
        _limits();
        _malformed();
        _order();
        _rollback();
        _dependents();
        _disable();
        _orphans();
    }

    // Notes → Clipboard → Base, both missing with sources: asked for one layer at a time,
    // then installed providers first
    function _chainOfTwo() {
        const notes = _manifest("notes", "1.0.0", null, { clipboard: { version: "0.2", source: "file:///r/clipboard" } });
        const clipboard = _manifest("clipboard", "0.2.1", "0.2", { base: { version: "1.1", source: "file:///r/base" } });
        const base = _manifest("base", "1.4.0", "1.4", {});

        const first = _plan(notes, {}, {});
        assertEqual(first.refused, "", "chain: not refused");
        assertEqual(JSON.stringify(first.fetch), JSON.stringify([{ id: "clipboard", source: "file:///r/clipboard" }]),
                    "chain: first asks for the direct dependency from its source");
        assert(!first.complete && !first.ready, "chain: not complete while something is to fetch");
        assertEqual(_entry(first, "clipboard").kind + " " + _entry(first, "clipboard").fetch, "download true", "chain: clipboard a download, still to fetch");

        const second = _plan(notes, {}, { clipboard: clipboard });
        assertEqual(JSON.stringify(second.fetch), JSON.stringify([{ id: "base", source: "file:///r/base" }]),
                    "chain: the fetched dependency's own uses are walked next");
        assertEqual(_entry(second, "base").depth, 2, "chain: base met at depth 2");
        assertEqual(_entry(second, "clipboard").to, "0.2.1", "chain: the version to install is the fetched one");

        const third = _plan(notes, {}, { clipboard: clipboard, base: base });
        assert(third.complete && third.ready, "chain: complete and ready once both are there");
        assertEqual(third.blocking.length, 0, "chain: nothing blocking");
        assertEqual(third.order.join(","), "base,clipboard,notes", "chain: install order providers first, the root last");
        assertEqual(third.entries.map(entry => entry.id + ":" + entry.kind).join(","), "clipboard:download,base:download",
                    "chain: the entries in the order met");
    }

    function _there() {
        const exitMap = _manifest("exitmap", "1.0.0", null, { tailscale: "1.0" });
        const installed = { tailscale: _installed("tailscale", "0.6.0", "1.2", "shell", "file:///r/ts") };
        const result = _plan(exitMap, installed, {});
        assertEqual(_entry(result, "tailscale").kind, "there", "there: an installed provider that fits");
        assertEqual(_entry(result, "tailscale").from, "0.6.0", "there: its installed version for \"Already there\"");
        assert(result.ready && result.fetch.length === 0, "there: ready, nothing to fetch");
        assertEqual(result.order.join(","), "exitmap", "there: only the root installs");
    }

    function _missing() {
        const notes = _manifest("notes", "1.0.0", null, { clipboard: "0.2" });
        const result = _plan(notes, {}, {});
        const entry = _entry(result, "clipboard");
        assertEqual(entry.kind, "unresolved", "missing: no source → unresolved");
        assertEqual(entry.reason, "Needs clipboard 0.2 — not installed, no address given", "missing: the preview's line (the id: no manifest gives a name)");
        assert(result.complete && !result.ready, "missing: complete but not ready");
        assertEqual(result.blocking.join("|"), entry.reason, "missing: blocking names it — only \"Install anyway\"");
        assertEqual(result.order.join(","), "notes", "missing: \"Install anyway\" installs what resolves (the root)");
    }

    function _incompatible() {
        const notes = _manifest("notes", "1.0.0", null, { weather: "2.0" });
        const system = _plan(notes, { weather: _installed("weather", "1.2.0", "1.2", "system") }, {});
        assertEqual(_entry(system, "weather").kind, "incompatible", "incompatible: a system copy that does not fit cannot be updated here");
        assertEqual(_entry(system, "weather").reason, "Needs Weather 2.0 — the system's copy is 1.2", "incompatible: the system's line");
        assert(!system.ready && system.blocking.length === 1, "incompatible: blocking");
        const builtin = _plan(notes, { weather: _installed("weather", "1.2.0", "1.2", "builtin") }, {});
        assertEqual(_entry(builtin, "weather").reason, "Needs Weather 2.0 — the built-in copy is 1.2", "incompatible: built-in");
        const byHand = _plan(notes, { weather: _installed("weather", "1.2.0", "1.2", "link") }, {});
        assertEqual(_entry(byHand, "weather").kind, "incompatible", "incompatible: a copy placed by hand is not updated");
        const noAddress = _plan(notes, { weather: _installed("weather", "1.2.0", "1.2", "shell", "") }, {});
        assertEqual(_entry(noAddress, "weather").kind, "incompatible", "incompatible: installed by the shell but no recorded address");

        const wants = _manifest("notes", "1.0.0", null, { clipboard: { version: "0.3", source: "file:///r/c" } });
        const tooOld = _plan(wants, {}, { clipboard: _manifest("clipboard", "0.2.1", "0.2", {}) });
        assertEqual(_entry(tooOld, "clipboard").kind, "incompatible", "incompatible: the downloaded version is too old");
        assertEqual(_entry(tooOld, "clipboard").reason, "Needs Clipboard 0.3 — the repository has 0.2", "incompatible: its line");
        assertEqual(tooOld.order.join(","), "notes", "incompatible: not installed with \"Install anyway\"");
        const newApi = _plan(wants, {}, { clipboard: _manifest("clipboard", "0.3.0", "0.3", {}, "1.40") });
        assertEqual(_entry(newApi, "clipboard").kind, "incompatible", "incompatible: the downloaded one asks a newer API than the shell's");
        assert(_entry(newApi, "clipboard").reason.indexOf("a newer shell is needed") > 0, "incompatible: the API's reason in the line");
        const noExports = _plan(wants, {}, { clipboard: _manifest("clipboard", "0.3.0", null, {}) });
        assertEqual(_entry(noExports, "clipboard").kind, "incompatible", "incompatible: a provider exporting nothing");
        const wrongId = _plan(wants, {}, { clipboard: _manifest("other", "0.3.0", "0.3", {}) });
        assertEqual(_entry(wrongId, "clipboard").reason, "Needs clipboard 0.3 — its manifest could not be read",
                    "incompatible: a repository holding another module is unreadable, not fine (nor its name taken)");
        const garbage = _plan(wants, {}, { clipboard: "{oops" });
        assertEqual(_entry(garbage, "clipboard").kind, "incompatible", "incompatible: a fetched manifest that is not an object");
    }

    function _updates() {
        const notes = _manifest("notes", "1.0.0", null, { weather: "1.3" });
        const installed = { weather: _installed("weather", "1.2.0", "1.2", "shell", "file:///r/weather"),
                            radar: _installed("radar", "1.0.0", null, "shell", "file:///r/radar", { weather: "1.0" }) };
        const before = _plan(notes, installed, {});
        assertEqual(_entry(before, "weather").kind + " " + _entry(before, "weather").fetch, "update true", "update: too old, an address → an update to fetch");
        assertEqual(JSON.stringify(before.fetch), JSON.stringify([{ id: "weather", source: "file:///r/weather" }]), "update: fetched from its recorded address");
        assertEqual(_entry(before, "weather").reason, "notes needs 1.3", "update: the line says who needs what");

        const after = _plan(notes, installed, { weather: _manifest("weather", "1.3.0", "1.3", { sky: { version: "1.0", source: "file:///r/sky" } }) });
        const weather = _entry(after, "weather");
        assertEqual(weather.from + " → " + weather.to, "1.2.0 → 1.3.0", "update: from and to");
        assertEqual(weather.breaks.length, 0, "update: a minor update breaks nobody");
        assertEqual(_entry(after, "sky").kind, "download", "update: a new hard dependency of the update joins the chain");

        const major = _plan(_manifest("notes", "1.0.0", null, { weather: "2.0" }), installed,
                            { weather: _manifest("weather", "2.0.0", "2.0", {}) });
        assertEqual(_entry(major, "weather").breaks.join(","), "radar", "update: a new major names the installed modules it would stop");

        const updateRoot = _plan(_manifest("weather", "2.0.0", "2.0", {}), installed, {});
        assertEqual(updateRoot.rootBreaks.join(","), "radar", "update: the root's own new major names them too");

        const badUpdate = _plan(notes, installed, { weather: _manifest("weather", "1.2.5", "1.2", {}) });
        assertEqual(_entry(badUpdate, "weather").kind, "incompatible", "update: a fetched update that still does not fit");
    }

    // Clipboard needed by Notes and by Todo: one entry naming both, fit against both
    function _twoDependents() {
        const notes = _manifest("notes", "1.0.0", null, { clipboard: { version: "0.2", source: "file:///r/c" },
                                                          todo: { version: "1.0", source: "file:///r/t" } });
        const todo = _manifest("todo", "1.0.0", "1.0", { clipboard: { version: "0.3", source: "file:///r/c-other" } });
        const result = _plan(notes, {}, { todo: todo, clipboard: _manifest("clipboard", "0.3.0", "0.3", {}) });
        const clipboard = _entry(result, "clipboard");
        assertEqual(result.entries.filter(entry => entry.id === "clipboard").length, 1, "two dependents: listed once");
        assertEqual(clipboard.neededBy.join(","), "notes,todo", "two dependents: both named");
        assertEqual(clipboard.wants.join(","), "0.2,0.3", "two dependents: both versions asked");
        assertEqual(clipboard.source, "file:///r/c", "two dependents: the first source named stays");
        assertEqual(clipboard.kind, "download", "two dependents: 0.3 serves both");
        assertEqual(result.order.join(","), "clipboard,todo,notes", "two dependents: order");

        const narrow = _plan(notes, {}, { todo: todo, clipboard: _manifest("clipboard", "0.2.0", "0.2", {}) });
        assertEqual(_entry(narrow, "clipboard").kind, "incompatible", "two dependents: one that serves only the first is incompatible");
        assertEqual(_entry(narrow, "clipboard").reason, "Needs Clipboard 0.2 and 0.3 — the repository has 0.2", "two dependents: the line names both");
    }

    function _soft() {
        const weather = _manifest("weather", "1.0.0", null, { calendar: { version: "1.0", optional: true, source: "file:///r/cal" },
                                                               maps: { version: "1.0", optional: true } ,
                                                               clock: { version: "1.0", optional: true } });
        const installed = { clock: _installed("clock", "1.0.0", "1.0", "builtin") };
        const result = _plan(weather, installed, {});
        assertEqual(result.entries.length, 0, "soft: absent soft uses are not in the chain");
        assertEqual(result.offers.map(offer => offer.id + ":" + offer.canInstall).join(","), "calendar:true,maps:false",
                    "soft: offered, \"Also install\" only with a source; an installed one not offered");
        assert(result.ready && result.fetch.length === 0, "soft: never downloaded unasked; the module is ready");

        const ticked = _plan(weather, installed, {}, { shellApi: "1.36", alsoInstall: ["calendar", "maps"] });
        assertEqual(JSON.stringify(ticked.fetch), JSON.stringify([{ id: "calendar", source: "file:///r/cal" }]), "soft: a ticked one with a source is downloaded");
        assertEqual(ticked.offers.map(offer => offer.id).join(","), "maps", "soft: a ticked one without a source stays an offer");
        const done = _plan(weather, installed, { calendar: _manifest("calendar", "1.1.0", "1.1", {}) }, { shellApi: "1.36", alsoInstall: ["calendar"] });
        assert(_entry(done, "calendar").soft && done.order.join(",") === "calendar,weather", "soft: ticked, it installs first");
        const misfit = _plan(weather, installed, { calendar: _manifest("calendar", "2.0.0", "2.0", {}) }, { shellApi: "1.36", alsoInstall: ["calendar"] });
        assert(misfit.ready && misfit.order.join(",") === "weather", "soft: a ticked one that does not fit blocks nothing and is left out");

        const both = _plan(_manifest("notes", "1.0.0", null, { calendar: { version: "1.0", optional: true },
                                                                 todo: { version: "1.0", source: "file:///r/t" } }),
                           {}, { todo: _manifest("todo", "1.0.0", "1.0", { calendar: { version: "1.0", source: "file:///r/cal" } }) });
        assertEqual(both.offers.length + " " + _entry(both, "calendar").soft, "0 false", "soft: one another module needs hard is in the chain, not offered");
    }

    function _cycles() {
        const notes = _manifest("notes", "1.0.0", "1.0", { clipboard: { version: "0.2", source: "file:///r/c" } });
        const back = _plan(notes, {}, { clipboard: _manifest("clipboard", "0.2.0", "0.2", { notes: "1.0" }) });
        assertEqual(back.refused, "uses form a cycle: notes → clipboard → notes", "cycle: back to the root is refused, naming it");
        assert(!back.ready && back.order.length === 0 && back.entries.length === 0, "cycle: nothing to install");
        const longer = _plan(notes, {}, { clipboard: _manifest("clipboard", "0.2.0", "0.2", { paste: { version: "1.0", source: "file:///r/p" } }),
                                          paste: _manifest("paste", "1.0.0", "1.0", { clipboard: "0.2" }) });
        assertEqual(longer.refused, "uses form a cycle: clipboard → paste → clipboard", "cycle: among dependencies");
        const self = _plan(notes, {}, { clipboard: _manifest("clipboard", "0.2.0", "0.2", { clipboard: "0.2" }) });
        assertEqual(self.refused, "clipboard uses itself", "cycle: a module that uses itself");
        const softBack = _plan(notes, {}, { clipboard: _manifest("clipboard", "0.2.0", "0.2", { notes: { version: "1.0", optional: true } }) });
        assertEqual(softBack.refused, "", "cycle: a soft use back never closes one");
        assert(softBack.ready, "cycle: … and the chain is ready");
    }

    // A chain of `length` modules m1 → m2 → … each with a source, all fetched
    function _line(length) {
        const fetched = {};
        for (let i = 1; i <= length; i++)
            fetched["m" + i] = _manifest("m" + i, "1.0.0", "1.0", i < length ? { ["m" + (i + 1)]: { version: "1.0", source: "file:///r/m" + (i + 1) } } : {});
        return { root: _manifest("root", "1.0.0", null, { m1: { version: "1.0", source: "file:///r/m1" } }), fetched: fetched };
    }

    function _limits() {
        const eight = _line(8);
        assertEqual(_plan(eight.root, {}, eight.fetched).refused, "", "limits: depth 8 is allowed");
        assert(_plan(eight.root, {}, eight.fetched).ready, "limits: … and ready");
        const nine = _line(9);
        assertEqual(_plan(nine.root, {}, nine.fetched).refused,
                    "the chain is deeper than 8: root → m1 → m2 → m3 → m4 → m5 → m6 → m7 → m8 → m9", "limits: depth 9 refused, naming the path");
        const uses = {};
        for (let i = 1; i <= 16; i++)
            uses["w" + i] = { version: "1.0" };
        assertEqual(_plan(_manifest("root", "1.0.0", null, uses), {}, {}).refused, "the chain has more than 16 modules",
                    "limits: more than 16 modules refused");
        delete uses.w16;
        assertEqual(_plan(_manifest("root", "1.0.0", null, uses), {}, {}).refused, "", "limits: 16 with the root is allowed");
    }

    function _malformed() {
        const notes = _manifest("notes", "1.0.0", null, { clipboard: "0.2" });
        assertEqual(_plan(null, {}, {}).refused, "the module's manifest could not be read", "malformed: no root manifest");
        assertEqual(_plan({ id: "notes", version: "1.0.0", uses: "x" }, {}, {}).refused, "the module's manifest could not be read", "malformed: uses not a list");
        assertEqual(_plan(notes, null, {}).refused, "the installed modules are not known", "malformed: the installed list unknown refuses, never \"download all\"");
        const noApi = ModuleDependencyRules.plan(notes, {}, {}, null).refused;
        assert(noApi.indexOf("is not \"major.minor\"") > 0, "malformed: no shell API refuses — " + noApi);
        assert(_plan(_manifest("notes", "1.0.0", null, {}, "2.0"), {}, {}).refused.indexOf("Notes: ") === 0, "malformed: a root for another API is refused, named");
        assertEqual(_plan(notes, {}, "nonsense").entries.length, 1, "malformed: fetched not an object reads as nothing fetched");
        const odd = _plan(_manifest("notes", "1.0.0", null, { constructor: "1.0", toString: "1.0" }), {}, {});
        assertEqual(odd.entries.map(entry => entry.kind).join(","), "unresolved,unresolved", "malformed: prototype names are just ids");
        const brokenRecord = _plan(notes, { clipboard: "garbage" }, {});
        assertEqual(_entry(brokenRecord, "clipboard").kind, "incompatible", "malformed: an unreadable installed record does not fit");
        let threw = false;
        try {
            for (const value of [undefined, 0, "x", [], { uses: [null, 3, { id: 5 }] }])
                ModuleDependencyRules.plan({ id: "a", version: "1", api: "1.36", uses: [null, 3, { id: 5 }, value] }, {}, value, value);
            ModuleDependencyRules.installOrder("x");
            ModuleDependencyRules.rollbackPlan("x");
            ModuleDependencyRules.dependents(null, "x");
            ModuleDependencyRules.disableList(undefined, [null, 1, { id: 2 }]);
            ModuleDependencyRules.orphans("a", { id: "a" });
        } catch (error) {
            threw = true;
        }
        assert(!threw, "malformed: nothing throws");
    }

    function _order() {
        const order = ModuleDependencyRules.installOrder([
            _manifest("notes", "1.0.0", null, { clipboard: "0.2", base: "1.0" }),
            _manifest("clipboard", "0.2.0", "0.2", { base: "1.0" }),
            _manifest("base", "1.0.0", "1.0", {}),
            _manifest("weather", "1.0.0", null, { calendar: { version: "1.0", optional: true } }),
            _manifest("calendar", "1.0.0", "1.0", {}),
            null, { id: "broken" }]);
        assertEqual(order.join(","), "base,calendar,clipboard,notes,weather", "order: providers first (soft ones too), then by id; unreadable left out");
        assertEqual(ModuleDependencyRules.installOrder(null).length, 0, "order: nothing for nothing");
    }

    // The chain Notes → Clipboard, with Weather updated: Clipboard and Weather moved in, Notes
    // failed to move → the two taken back, last first, then every staging directory deleted
    function _rollback() {
        const failedOnSecond = ModuleDependencyRules.rollbackPlan({
            staged: ["/s/clipboard", "/s/weather", "/s/notes"],
            done: [{ id: "clipboard", kind: "install", version: "0.2.0" },
                   { id: "weather", kind: "update", version: "1.3.0", previousVersion: "1.2.0", backup: "/b/weather-1.2.0" }] });
        assertEqual(JSON.stringify(failedOnSecond.actions), JSON.stringify([
            { action: "relink", id: "weather", version: "1.2.0" },
            { action: "restoreBackup", id: "weather", backup: "/b/weather-1.2.0" },
            { action: "deleteVersion", id: "weather", version: "1.3.0" },
            { action: "unlink", id: "clipboard" },
            { action: "deleteVersion", id: "clipboard", version: "0.2.0" },
            { action: "deleteStaging", directory: "/s/clipboard" },
            { action: "deleteStaging", directory: "/s/weather" },
            { action: "deleteStaging", directory: "/s/notes" }]), "rollback: the moved ones last first, then the staging");
        assertEqual(failedOnSecond.problems.length, 0, "rollback: no problems");

        const beforeMoving = ModuleDependencyRules.rollbackPlan({ staged: ["/s/a", "/s/b"], done: [] });
        assertEqual(beforeMoving.actions.map(action => action.action).join(","), "deleteStaging,deleteStaging",
                    "rollback: a failed download or check deletes the staging only");
        const noBackup = ModuleDependencyRules.rollbackPlan({ staged: [], done: [{ id: "w", kind: "update", version: "2.0.0", previousVersion: "1.0.0" }] });
        assertEqual(noBackup.actions.map(action => action.action).join(","), "relink,deleteVersion", "rollback: an update without a backup");

        const unsafe = ModuleDependencyRules.rollbackPlan({ staged: ["/s/x", "", 5],
            done: [{ id: "w", kind: "update", version: "2.0.0" }, { id: "c", kind: "install" }, { kind: "install" }, { id: "z", kind: "remove" }] });
        assertEqual(unsafe.actions.map(action => action.action + ":" + (action.id ?? action.directory)).join(","), "unlink:c,deleteStaging:/s/x",
                    "rollback: an update without its previous version keeps its new one linked; an unknown version's directory is left");
        assertEqual(unsafe.problems.length, 6, "rollback: every unreadable step and path is a problem");
        assertEqual(ModuleDependencyRules.rollbackPlan({ done: "x" }).problems.length, 1, "rollback: unreadable list of moved ones is a problem");
    }

    function _modules() {
        return [
            { id: "tailscale", name: "Tailscale", uses: [], state: "loaded" },
            { id: "exitmap", name: "Exit map", uses: [{ id: "tailscale", version: "1.0" }], state: "loaded" },
            { id: "routes", name: "Routes", uses: [{ id: "exitmap", version: "1.0" }], state: "disabled" },
            { id: "status", name: "Status", uses: [{ id: "routes", version: "1.0" }], state: "loaded" },
            { id: "weather", name: "Weather", uses: [{ id: "tailscale", version: "1.0", optional: true }], state: "loaded" },
            { id: "badge", name: "Badge", uses: [{ id: "routes", version: "1.0", optional: true }], state: "loaded" },
            { id: "clock", name: "Clock", uses: [], state: "loaded" },
            { id: "mystery", name: "Mystery", uses: "??", state: "loaded" }];
    }

    function _dependents() {
        const result = ModuleDependencyRules.dependents("tailscale", _modules());
        assertEqual(result.stopWorking.join(","), "exitmap,routes,status", "dependents: hard ones and theirs, by name");
        assertEqual(result.loseFeature.join(","), "badge,weather", "dependents: soft users of it or of those, by name");
        assertEqual(result.unknown.join(","), "mystery", "dependents: unreadable uses may need it");
        const none = ModuleDependencyRules.dependents("clock", _modules());
        assertEqual(none.stopWorking.length + none.loseFeature.length, 0, "dependents: none");
        const twoUsers = ModuleDependencyRules.dependents("p", [
            { id: "p", uses: [] }, { id: "a", name: "A", uses: [{ id: "p" }] }, { id: "b", name: "B", uses: [{ id: "p" }] }]);
        assertEqual(twoUsers.stopWorking.join(","), "a,b", "dependents: a provider with two dependents names both");
    }

    function _disable() {
        const result = ModuleDependencyRules.disableList("tailscale", _modules());
        assertEqual(result.disabled.join(","), "exitmap,status", "disable: the running hard dependents, through a disabled one too");
        assertEqual(result.unknown.join(","), "mystery", "disable: a running one with unreadable uses");
        assertEqual(ModuleDependencyRules.disableList("clock", _modules()).disabled.length, 0, "disable: none → the button's own question");
        const soft = ModuleDependencyRules.disableList("weather", [{ id: "weather", uses: [] },
            { id: "a", uses: [{ id: "weather", optional: true }], state: "loaded" }]);
        assertEqual(soft.disabled.length, 0, "disable: soft users stay on");
    }

    function _orphans() {
        const modules = [
            { id: "notes", name: "Notes", uses: [{ id: "clipboard" }, { id: "todo" }], origin: "shell" },
            { id: "clipboard", name: "Clipboard", uses: [], origin: "shell", installedFor: "notes" },
            { id: "todo", name: "Todo", uses: [{ id: "paste" }], origin: "shell", installedFor: "notes" },
            { id: "paste", name: "Paste", uses: [], origin: "shell", installedFor: "todo" },
            { id: "shared", name: "Shared", uses: [], origin: "shell", installedFor: "notes" },
            { id: "other", name: "Other", uses: [{ id: "shared", optional: true }], origin: "shell" },
            { id: "sys", name: "Sys", uses: [], origin: "system", installedFor: "notes" }];
        const result = ModuleDependencyRules.orphans("notes", modules);
        assertEqual(result.map(orphan => orphan.id + "[" + orphan.usedBy.join(",") + "]").join(" "), "clipboard[] paste[todo] todo[]",
                    "orphans: installed for it (or for one of those), used by nothing else; one used by another offered one says so; a soft user keeps one; system never");
        assertEqual(result[0].name, "Clipboard", "orphans: with the name for the checkbox");
        const unknownUser = ModuleDependencyRules.orphans("notes", modules.concat([{ id: "mystery", uses: null }]));
        assertEqual(unknownUser.length, 0, "orphans: a module with unreadable uses may need any of them");
        assertEqual(ModuleDependencyRules.orphans("clock", modules).length, 0, "orphans: none for a module nothing was installed for");
        const sharedProvider = ModuleDependencyRules.orphans("a", [
            { id: "a", uses: [{ id: "p" }] }, { id: "b", uses: [{ id: "p" }] }, { id: "p", uses: [], installedFor: "a" }]);
        assertEqual(sharedProvider.length, 0, "orphans: a provider with two dependents stays");
    }
}
