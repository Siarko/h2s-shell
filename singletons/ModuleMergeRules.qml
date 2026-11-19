pragma Singleton

import Quickshell
import QtQuick

// The module system's decisions about several modules (ModuleRules.qml has the overview):
// which of two with one id wins, the state a module is in, its status, and the modules'
// contributions merged into the lists the core's registries read. Pure, checked by
// tests/ModuleRulesTest.qml.
Singleton {
    id: root

    // ---- Several modules ----

    // Search-path precedence: `candidates` in search order, each { directory, id } (id ""
    // when the manifest had none). → one entry per candidate: { winner, shadowedBy } — the
    // first with an id wins, a later one with the same id is shadowed by the winner's
    // directory. One without an id is never shadowed and shadows nothing.
    function precedence(candidates) {
        const owners = new Map();
        return (candidates ?? []).map(candidate => {
            const id = candidate?.id ?? "";
            if (id === "")
                return { winner: true, shadowedBy: "" };
            if (owners.has(id))
                return { winner: false, shadowedBy: owners.get(id) };
            owners.set(id, candidate.directory);
            return { winner: true, shadowedBy: "" };
        });
    }

    // The state of one module, from what is known of it (see `states`). `facts`:
    //   valid, compatible, duplicate, safeMode, enabled  booleans
    //   settingsKnown      the config (which modules are off) has been read; false: pending
    //   programsKnown      the check of requires.programs has answered (true when none)
    //   missingPrograms    the ones not found
    //   mainError          why its main could not be created ("" for none)
    //   filesChecked       the check of the module's files has answered (false: pending)
    //   guardKnown         the start guard has answered (false: pending; see startGuard)
    //   dataDirectoryKnown making its data directory has answered (false: pending)
    function stateOf(facts) {
        // module.json not answered yet (the file check reads it): pending
        if (facts?.manifestRead === false)
            return "pending";
        if (!facts?.valid)
            return "failed";
        if (facts.duplicate)
            return "duplicate";
        if (!facts.compatible)
            return "incompatible";
        if (facts.filesChecked === false)
            return "pending";
        if (facts.mainFileError)
            return "failed";
        if (facts.guardKnown === false)
            return "pending";
        if (facts.safeMode)
            return "safe-mode";
        if (facts.settingsKnown === false)
            return "pending";
        if (!facts.enabled)
            return "disabled";
        if (!facts.programsKnown)
            return "pending";
        if ((facts.missingPrograms ?? []).length > 0)
            return "missing-program";
        // Its data directory is being made (API 1.13)
        if (facts.dataDirectoryKnown === false)
            return "pending";
        if (facts.mainError)
            return "failed";
        return "loaded";
    }

    // ---- Modules that use other modules (API 1.18) ----

    // Whether a provider whose `exports` has version `has` serves a dependent asking for
    // `wanted`: the same major, the provider's minor at least the one asked for (what a minor
    // may change is the provider's rule) → { fits, reason }
    function usesFit(wanted, has) {
        const asked = ModuleRules.parseApi(wanted);
        const given = ModuleRules.parseApi(has);
        if (!asked || !given)
            return { fits: false, reason: "has " + (typeof has === "string" ? has : ModuleRules.show(has)) };
        return asked.major === given.major && given.minor >= asked.minor ? { fits: true, reason: "" } : { fits: false, reason: "has " + has };
    }

    // Why a provider in state `state` serves no dependent, in a few words
    function _notLoadedReason(state) {
        switch (state) {
        case "disabled": return "turned off";
        case "failed": return "failed";
        case "incompatible": return "incompatible with this shell";
        case "missing-program": return "missing a program";
        case "missing-module": return "missing a module";
        case "safe-mode": return "not loaded (safe mode)";
        default: return "not loaded (" + ModuleRules.show(state) + ")";
        }
    }

    // The order the modules load in and the state each ends in, from what `uses` asks for.
    // `manifests`: checked manifests ({ id, uses: [{ id, version }], exports: { version } |
    // null }); a second one with an id already given is ignored (the host gives the ones that
    // count). `states`: { <id>: { state, exports } } — `state` what the module's own checks
    // say (stateOf), `exports` "" when its exports object is there, a text when it is not
    // (exportsOf), undefined while not known (taken as there: the host asks again once the
    // main is made).
    // → { order: [ids], providers first, then by id; destroyed in the reverse order,
    //     modules: [{ id, state, reasons: [text] }] in that order,
    //     cycles: [[ids]] }
    // A module whose own state is not "loaded" keeps it. One that would load:
    //   in a cycle of uses                    → failed, "uses form a cycle: a → b → a", or
    //                                            "uses itself"
    //   a provider pending                    → pending (it waits for it)
    //   a provider missing or not loaded, exporting nothing or an older version, or without
    //   its exports object                    → missing-module, one reason per provider:
    //     "needs module tailscale 1.0: not installed" / "turned off" / "failed" /
    //     "exports no API" / "has 0.9" / "gives no exports object"
    // Pure, and never throws on any input.
    function dependencyPlan(manifests, states) {
        const known = new Map();
        for (const manifest of Array.isArray(manifests) ? manifests : []) {
            const id = manifest?.id;
            if (typeof id !== "string" || id === "" || known.has(id))
                continue;
            known.set(id, { id: id, exports: ModuleRules.isObject(manifest.exports) ? manifest.exports : null,
                            uses: (Array.isArray(manifest.uses) ? manifest.uses : [])
                                .filter(use => use && typeof use.id === "string" && typeof use.version === "string") });
        }
        const ids = Array.from(known.keys()).sort();
        const edges = id => Array.from(new Set(known.get(id).uses.map(use => use.id).filter(other => known.has(other)))).sort();

        // The cycles: strongly connected components (Tarjan) of more than one module, or of
        // one that uses itself
        let counter = 0;
        const index = new Map();
        const low = new Map();
        const stack = [];
        const onStack = new Set();
        const cycles = [];
        const visit = id => {
            index.set(id, counter);
            low.set(id, counter);
            counter++;
            stack.push(id);
            onStack.add(id);
            for (const other of edges(id)) {
                if (!index.has(other)) {
                    visit(other);
                    low.set(id, Math.min(low.get(id), low.get(other)));
                } else if (onStack.has(other)) {
                    low.set(id, Math.min(low.get(id), index.get(other)));
                }
            }
            if (low.get(id) === index.get(id)) {
                const component = [];
                let member;
                do {
                    member = stack.pop();
                    onStack.delete(member);
                    component.push(member);
                } while (member !== id);
                if (component.length > 1 || edges(id).includes(id))
                    cycles.push(component.sort());
            }
        };
        for (const id of ids) {
            if (!index.has(id))
                visit(id);
        }
        const cycleText = new Map();
        for (const component of cycles) {
            const members = new Set(component);
            for (const id of component) {
                const path = _cyclePath(id, members, edges);
                cycleText.set(id, path.length <= 2 ? "uses itself" : "uses form a cycle: " + path.join(" → "));
            }
        }

        // The order: each module after the ones it uses (depth first, by id), a cycle's
        // members where the walk meets them
        const order = [];
        const placed = new Set();
        const entered = new Set();
        const place = id => {
            if (placed.has(id) || entered.has(id))
                return;
            entered.add(id);
            for (const other of edges(id))
                place(other);
            placed.add(id);
            order.push(id);
        };
        for (const id of ids)
            place(id);

        // The states, in that order: a provider's is known before its dependents'
        const final = new Map();
        const result = [];
        const stateOf = id => {
            const given = states && ModuleRules.isObject(states) && ModuleRules.has(states, id) ? states[id] : null;
            return typeof given?.state === "string" ? given.state : "failed";
        };
        const exportsProblem = id => {
            const given = states && ModuleRules.isObject(states) && ModuleRules.has(states, id) ? states[id] : null;
            return typeof given?.exports === "string" ? given.exports : "";
        };
        for (const id of order) {
            const own = stateOf(id);
            let state = own;
            const reasons = [];
            if (own === "loaded" && cycleText.has(id)) {
                state = "failed";
                reasons.push(cycleText.get(id));
            } else if (own === "loaded") {
                let waiting = false;
                for (const use of known.get(id).uses) {
                    const needs = "needs module " + use.id + " " + use.version + ": ";
                    if (!known.has(use.id)) {
                        reasons.push(needs + "not installed");
                        continue;
                    }
                    const providerState = final.get(use.id) ?? stateOf(use.id);
                    if (providerState === "pending") {
                        waiting = true;
                        continue;
                    }
                    if (providerState !== "loaded") {
                        reasons.push(needs + _notLoadedReason(providerState));
                        continue;
                    }
                    const provider = known.get(use.id);
                    if (!provider.exports) {
                        reasons.push(needs + "exports no API");
                        continue;
                    }
                    const fit = usesFit(use.version, provider.exports.version);
                    if (!fit.fits) {
                        reasons.push(needs + fit.reason);
                        continue;
                    }
                    if (exportsProblem(use.id) !== "")
                        reasons.push(needs + "gives no exports object");
                }
                if (reasons.length > 0)
                    state = "missing-module";
                else if (waiting)
                    state = "pending";
            }
            final.set(id, state);
            result.push({ id: id, state: state, reasons: reasons });
        }
        return { order: order, modules: result, cycles: cycles };
    }

    // One cycle through `start` inside a component (`members`): the shortest way back to it,
    // as [start, …, start]
    function _cyclePath(start, members, edges) {
        const previous = new Map();
        const queue = [start];
        const seen = new Set([start]);
        while (queue.length > 0) {
            const id = queue.shift();
            for (const other of edges(id)) {
                if (!members.has(other))
                    continue;
                if (other === start) {
                    const path = [start];
                    for (let step = id; step !== start; step = previous.get(step))
                        path.splice(1, 0, step);
                    path.push(start);
                    return path;
                }
                if (!seen.has(other)) {
                    seen.add(other);
                    previous.set(other, id);
                    queue.push(other);
                }
            }
        }
        return [start];
    }

    // The plan's entry for one module, or null
    function planned(plan, id) {
        return (plan?.modules ?? []).find(entry => entry.id === id) ?? null;
    }

    // A module's contributions count only while it is loaded
    function contributes(state) {
        return state === "loaded";
    }

    // The contributions of the loaded modules merged into the lists the core's registries
    // read, every file an absolute file:// URL, every entry marked with its module. Stable:
    // modules by id, each one's entries in manifest order — not in search-path order, which
    // differs from one machine to the next. `modules`: [{ id, directory, manifest }].
    // → { widgetEntries, settingsPages, settingEntries, factTypes, slots: { name: [...] } }
    function merge(modules) {
        const result = { widgetEntries: [], settingsPages: [], settingEntries: [], factTypes: [], slots: ({}) };
        const sorted = (modules ?? []).filter(module => module && typeof module.id === "string" && module.manifest)
            .slice().sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
        const slotMap = new Map();
        for (const module of sorted) {
            const url = file => file ? ModuleFileRules.fileUrl(module.directory, file) : "";
            for (const widget of module.manifest.widgets ?? []) {
                const entry = { module: module.id, type: widget.type, name: widget.name, widget: url(widget.widget),
                                multiple: widget.multiple === true };
                if (widget.popup)
                    entry.popup = widget.popup;
                if (widget.popupPanel)
                    entry.popupPanel = url(widget.popupPanel);
                if (widget.settings)
                    entry.settings = url(widget.settings);
                if (widget.presetDefaults)
                    entry.presetDefaults = JSON.parse(JSON.stringify(widget.presetDefaults));
                result.widgetEntries.push(entry);
            }
            for (const page of module.manifest.settingsPages ?? [])
                result.settingsPages.push(Object.assign({}, page, { module: module.id, component: url(page.component) }));
            for (const setting of module.manifest.settings ?? [])
                result.settingEntries.push(Object.assign({}, setting, { module: module.id }));
            for (const fact of module.manifest.facts ?? [])
                result.factTypes.push(Object.assign({}, fact, { module: module.id }));
            for (const slot of module.manifest.slots ?? []) {
                if (!slotMap.has(slot.slot))
                    slotMap.set(slot.slot, []);
                slotMap.get(slot.slot).push({ module: module.id, slot: slot.slot, component: url(slot.component) });
            }
        }
        // A plain object for QML, built without the prototype's names ever mattering: slot
        // names are checked dotted words, and are looked up with slotContributions()
        const slots = Object.create(null);
        for (const [name, entries] of slotMap)
            slots[name] = entries;
        result.slots = slots;
        return result;
    }

    // The contributions to one slot, from merge()'s `slots`
    function slotContributions(slots, name) {
        if (!slots || typeof name !== "string" || !Object.prototype.hasOwnProperty.call(slots, name))
            return [];
        return slots[name];
    }

    // One module's status, as the host keeps it and `qs ipc call modules list` prints it.
    // Every field plain data; nothing the module itself computed (no secrets).
    // `deprecations`: the old ways of the API the module still uses, one line each
    // (ModuleRules.deprecation) — they work, and go with the shell's next tightening.
    function statusOf(record) {
        const manifest = record?.manifest ?? null;
        const state = typeof record?.state === "string" ? record.state : "failed";
        return {
            id: manifest?.id ?? "",
            name: manifest?.name ?? "",
            version: manifest?.version ?? "",
            api: manifest?.api ?? "",
            description: manifest?.description ?? "",
            directory: record?.directory ?? "",
            state: state,
            enabled: record?.enabled !== false,
            errors: (record?.errors ?? []).slice(),
            warnings: (record?.warnings ?? []).slice(),
            deprecations: (record?.deprecations ?? []).slice(),
            missingPrograms: (record?.missingPrograms ?? []).slice(),
            setupHints: state === "missing-program" ? (manifest?.setupHints ?? []).slice() : [],
            shadowedBy: record?.shadowedBy ?? ""
        };
    }

    // A manifest's slot contributions to slots this shell does not offer: one warning each
    function unknownSlotWarnings(manifest) {
        return (manifest?.slots ?? []).filter(entry => !ModuleRules.slotNames.includes(entry.slot)).map(entry =>
            "slots: " + ModuleRules.show(entry.slot) + " is not a slot this shell offers (module API " + ModuleRules.apiVersion
            + "; offered: " + ModuleRules.slotNames.join(", ") + ") — " + entry.component + " shows nowhere");
    }

    // ---- The core's registries, merged with the modules' lists (M2) ----
    //
    // Each takes the core's own list and the host's merged list and returns the list the
    // registry publishes. With no module entries the result has the core's entries, in the
    // core's order, unchanged (the suites check it). A module entry that collides with a core
    // one (it cannot, with the namespaces, but the core never depends on that) is dropped.

    // WidgetRegistry.entries: the core's, then the modules' (a type or popup key the core
    // has, or "tray-menu"/"notifications" Popup wires itself, is dropped)
    function mergeWidgetEntries(core, modules) {
        const coreList = Array.isArray(core) ? core : [];
        const types = coreList.map(entry => entry.type);
        const popups = coreList.filter(entry => entry.popup).map(entry => entry.popup).concat(["tray-menu", "notifications"]);
        const added = [];
        for (const entry of Array.isArray(modules) ? modules : []) {
            if (!entry || types.includes(entry.type) || (entry.popup && popups.includes(entry.popup)))
                continue;
            types.push(entry.type);
            if (entry.popup)
                popups.push(entry.popup);
            added.push(entry);
        }
        return added.length === 0 ? coreList : coreList.concat(added);
    }

    // WidgetPresets.defaults: the core's, plus { type: presetDefaults } of the modules' widgets
    function mergePresetDefaults(core, moduleWidgets) {
        const result = Object.assign({}, core ?? {});
        for (const entry of Array.isArray(moduleWidgets) ? moduleWidgets : []) {
            if (entry?.presetDefaults && !ModuleRules.has(result, entry.type))
                result[entry.type] = entry.presetDefaults;
        }
        return result;
    }

    // SettingsSchema.entries: the core's, then the modules' (a key the core has: dropped).
    // A module entry has the schema's fields and `module`.
    function mergeSettingEntries(core, modules) {
        const coreList = Array.isArray(core) ? core : [];
        const keys = new Set(coreList.map(entry => entry.key));
        const added = (Array.isArray(modules) ? modules : []).filter(entry => entry && !keys.has(entry.key));
        return added.length === 0 ? coreList : coreList.concat(added);
    }

    // ProfileRules.factTypes: the core's, then the modules' (a fact the core has: dropped)
    function mergeFactTypes(core, modules) {
        const coreList = Array.isArray(core) ? core : [];
        const facts = new Set(coreList.map(entry => entry.fact));
        const added = (Array.isArray(modules) ? modules : []).filter(entry => entry && !facts.has(entry.fact));
        return added.length === 0 ? coreList : coreList.concat(added);
    }

    // The group the module pages without a usable parent go under, on the System tab
    readonly property var modulesGroup: ({ id: "modules", label: "Modules", tab: "system", group: true })

    // SettingsWindow.pages: the core's pages with the modules' pages put in. A module page
    // becomes { id, label, tab, url, module, parent? }:
    //   parent a core group → under it, on the group's tab (after the group's own pages);
    //   parent "modules", or a parent the core does not have → under the Modules group
    //     (System tab; the group exists only while it has pages);
    //   no parent → on its tab, after the core's pages.
    // An id the core has is dropped. → { pages, problems: [text] }
    function mergeSettingsPages(corePages, modulePages) {
        const core = Array.isArray(corePages) ? corePages : [];
        const problems = [];
        const ids = new Set(core.map(page => page.id));
        const groups = new Map(core.filter(page => page.group).map(page => [page.id, page.tab]));
        const children = new Map();
        const topLevel = [];
        const underModules = [];
        for (const page of Array.isArray(modulePages) ? modulePages : []) {
            if (!page || typeof page.id !== "string")
                continue;
            if (ids.has(page.id) || page.id === modulesGroup.id) {
                problems.push(page.module + ": settings page " + ModuleRules.show(page.id) + " has the id of a core page (dropped)");
                continue;
            }
            ids.add(page.id);
            const made = { id: page.id, label: page.label, tab: ModuleRules.settingsTabs.includes(page.tab) ? page.tab : "behaviour",
                           url: page.component, module: page.module };
            const parent = page.parent ?? "";
            if (parent === "") {
                topLevel.push(made);
            } else if (groups.has(parent)) {
                made.parent = parent;
                made.tab = groups.get(parent);
                if (!children.has(parent))
                    children.set(parent, []);
                children.get(parent).push(made);
            } else {
                if (parent !== modulesGroup.id)
                    problems.push(page.module + ": settings page " + ModuleRules.show(page.id) + ": no group " + ModuleRules.show(parent)
                                  + " — shown under Modules");
                made.parent = modulesGroup.id;
                made.tab = modulesGroup.tab;
                underModules.push(made);
            }
        }
        if (topLevel.length === 0 && underModules.length === 0 && children.size === 0)
            return { pages: core, problems: problems };
        const pages = [];
        core.forEach((page, index) => {
            pages.push(page);
            // A group's module pages after its last own page
            const group = page.group ? page.id : (page.parent ?? "");
            const next = core[index + 1];
            if (group !== "" && children.has(group) && !(next && next.parent === group))
                pages.push(...children.get(group));
        });
        pages.push(...topLevel);
        if (underModules.length > 0)
            pages.push(Object.assign({}, modulesGroup), ...underModules);
        return { pages: pages, problems: problems };
    }

    // The identity of a slot contribution, for the slot's ScriptModel
    function contributionKey(contribution) {
        return (contribution?.module ?? "") + "|" + (contribution?.component ?? "");
    }
}
