pragma Singleton

import Quickshell
import QtQuick

// The dependency chain of a module being installed or updated (plan §6.9): what each of its
// `uses` needs (nothing, an update, a download), what cannot be had and why, the soft ones
// offered, the order the chain installs in, how a run that failed halfway is taken back, and
// — for Remove and Disable — which modules need a module and which dependencies installed for
// it nothing else needs. Pure, never throws; checked by tests/ModuleDependencyRulesTest.qml.
// What cannot be read is never taken as fine: it refuses, blocks, or counts as "may need it".
Singleton {
    id: root

    // A chain longer or larger than this is refused, not walked further: a repository naming
    // a long or wide chain must not make the shell download without end.
    readonly property int maxDepth: 8
    readonly property int maxModules: 16
    // Names from manifests stand in lines the views show; never a whole huge string
    readonly property int maxNameLength: 64

    // ---- Resolving ----

    // What installing (or updating to) the manifest `rootManifest` brings with it.
    // `rootManifest`: the staged manifest { id, name, version, api, exports: { version } | null,
    //   uses: [{ id, version, optional, source }] } — `source` (API 1.36) the address the
    //   dependency is downloaded from when it is missing ("<url>#<ref>" allowed); one that
    //   ModuleInstallRules.repositoryProblem refuses counts as none ("address not usable").
    // `installed`: { <id>: { name, version, api, exports, uses, source, isLink, address, ref } }
    //   — every module on disk; `source` ModuleInstallRules.sourceOf's kind (builtin, system,
    //   repository, folder, user, developer), `address` and `ref` its recorded ones. Only one
    //   the shell installed — a repository with a usable address, or a folder with an
    //   absolute path — can be updated here, from that address at that ref.
    // `fetched`: { <id>: manifest } — the manifests downloaded and verified into staging so
    //   far (dependencies and updates); missing ones are asked for in `fetch`.
    // `context`: { shellApi, apiFloor (optional), alsoInstall: [ids] } — `alsoInstall` the
    //   soft dependencies whose "Also install" the user ticked.
    // → { refused: "" | why the whole chain is refused (a cycle, a limit, unreadable input),
    //     entries: [{ id, name, kind, soft, depth, neededBy: [ids], wants: [versions],
    //                 address, ref, from, to, fetch, reason, breaks: [ids] }] in the order met
    //       (breadth first, so a provider with several dependents is listed once) — `kind`:
    //         "there"        installed and fits every dependent: nothing to do
    //         "update"       installed, too old, can be updated from its recorded address
    //                        (`from` → `to`; `fetch` while the new manifest is not there yet)
    //         "download"     missing, with a source: downloaded too, its own uses walked
    //         "unresolved"   missing, no source
    //         "incompatible" present or downloaded, but its version or its API does not fit
    //                        (an installed copy whose API no longer fits the shell: an update
    //                        when it can have one, else this)
    //       `reason` one line for the preview ("Needs Clipboard 0.2 — not installed, no
    //       address given"; for an update "Notes needs 1.3"); `breaks` installed modules the
    //       update would no longer serve (a new major; the update rules ask for consent),
    //     offers: [{ id, name, wants, neededBy, address, ref, canInstall }] — soft uses that
    //       are missing ("Can use: Calendar — not installed"; "Also install" only with a usable
    //       address),
    //     fetch: [{ id, address, ref }] — what to download next; the installer calls plan again
    //       with the new manifests in `fetched`,
    //     complete: nothing more to fetch,
    //     blocking: [lines] — the unresolved and incompatible hard dependencies,
    //     ready: complete, not refused, nothing blocking — "Install" may go;
    //       complete and not refused with lines in `blocking`: only "Install anyway",
    //     order: [ids] the modules this run installs or updates (the root last among its
    //       providers), providers first — what "Install anyway" installs too,
    //     rootBreaks: [ids] — when the root replaces an installed copy, the installed modules
    //       its new version no longer serves }
    function plan(rootManifest, installed, fetched, context) {
        const empty = reason => ({ refused: reason, entries: [], offers: [], fetch: [], complete: false,
                                   blocking: [], ready: false, order: [], rootBreaks: [] });
        if (!_readable(rootManifest))
            return empty("the module's manifest could not be read");
        // Without the list of what is installed every dependency would look missing and be
        // downloaded over what is there
        if (!ModuleRules.isObject(installed))
            return empty("the installed modules are not known");
        const shellApi = context?.shellApi;
        const apiFloor = context?.apiFloor;
        const rootFit = ModuleRules.apiCompatibility(rootManifest.api, shellApi, apiFloor);
        if (!rootFit.compatible)
            return empty(_name(rootManifest.name, rootManifest.id) + ": " + rootFit.reason);
        const staged = ModuleRules.isObject(fetched) ? fetched : {};
        const chosen = Array.isArray(context?.alsoInstall) ? context.alsoInstall.filter(id => typeof id === "string") : [];

        // Which ids have their fetched manifest walked depends on the final kinds (only an
        // update or a download is walked), and the kinds on every dependent's wish: walk,
        // classify, and walk again with the new set until it stays the same. The set only
        // changes through what the chain names, so a few rounds settle it; one that never
        // settles is refused rather than guessed.
        let walked = new Set();
        for (let round = 0; round < 3 * maxModules; round++) {
            const result = _walk(rootManifest, installed, staged, chosen, walked, shellApi, apiFloor);
            if (result.refused !== "")
                return empty(result.refused);
            const next = new Set(result.entries.filter(entry => (entry.kind === "update" || entry.kind === "download") && !entry.fetch)
                                 .map(entry => entry.id));
            if (_sameSet(next, walked))
                return _finish(rootManifest, installed, staged, result);
            walked = next;
        }
        return empty("the chain does not settle");
    }

    // One walk from the root with the manifests of `walked` read; → { refused, entries, offers }
    function _walk(rootManifest, installed, staged, chosen, walked, shellApi, apiFloor) {
        const met = new Map();          // id → entry (the root is never one)
        const offers = new Map();
        const parent = new Map();       // id → the id it was first met from, for messages
        const queue = [{ manifest: rootManifest, depth: 0 }];
        while (queue.length > 0) {
            const { manifest, depth } = queue.shift();
            for (const use of manifest.uses) {
                const id = use?.id;
                if (typeof id !== "string" || id === "" || id === rootManifest.id)
                    continue;           // a use of the root closes a cycle: found below
                const given = _address(use.source);
                const source = given.address;
                const soft = use.optional === true;
                if (soft && !met.has(id)) {
                    if (ModuleRules.has(installed, id))
                        continue;       // there: the host gives it when it fits
                    if (!(chosen.includes(id) && source !== "")) {
                        const offer = offers.get(id) ?? { id: id, name: id, wants: [], neededBy: [], address: "", ref: "", canInstall: false };
                        _addOnce(offer.wants, use.version);
                        _addOnce(offer.neededBy, manifest.id);
                        if (offer.address === "" && source !== "") {
                            offer.address = source;
                            offer.ref = given.ref;
                        }
                        offer.canInstall = offer.address !== "";
                        offers.set(id, offer);
                        continue;
                    }
                }
                if (met.has(id)) {
                    const entry = met.get(id);
                    _addOnce(entry.neededBy, manifest.id);
                    if (!soft) {
                        _addOnce(entry.wants, use.version);
                        entry.soft = false;
                    } else {
                        _addOnce(entry.softWants, use.version);
                    }
                    // The first usable address named stays: dependents naming another are not
                    // asked which is right
                    if (entry.address === "" && source !== "") {
                        entry.address = source;
                        entry.ref = given.ref;
                    }
                    if (given.problem)
                        entry.badAddress = true;
                    continue;
                }
                parent.set(id, manifest.id);
                if (depth + 1 > maxDepth)
                    return { refused: "the chain is deeper than " + maxDepth + ": " + _path(parent, id, rootManifest.id).join(" → ") };
                if (met.size + 2 > maxModules)
                    return { refused: "the chain has more than " + maxModules + " modules" };
                offers.delete(id);
                const entry = { id: id, name: id, kind: "", soft: soft, depth: depth + 1, neededBy: [manifest.id],
                                wants: soft ? [] : [use.version], softWants: soft ? [use.version] : [],
                                address: source, ref: given.ref, badAddress: given.problem, from: "", to: "",
                                fetch: false, reason: "", breaks: [] };
                met.set(id, entry);
                if (walked.has(id) && _readable(ModuleRules.get(staged, id)))
                    queue.push({ manifest: ModuleRules.get(staged, id), depth: depth + 1 });
            }
        }
        const cycle = _cycle(rootManifest, installed, staged, walked);
        if (cycle.length > 0)
            return { refused: cycle.length <= 2 ? cycle[0] + " uses itself" : "uses form a cycle: " + cycle.join(" → ") };
        for (const entry of met.values())
            _classify(entry, rootManifest, installed, staged, shellApi, apiFloor);
        // An offer one module makes soft and another installs hard is not offered
        for (const id of Array.from(offers.keys()))
            if (met.has(id))
                offers.delete(id);
        return { refused: "", entries: Array.from(met.values()), offers: Array.from(offers.values()) };
    }

    // The kind, versions and line of one entry, from everything that wants it
    function _classify(entry, rootManifest, installed, staged, shellApi, apiFloor) {
        _classifyKind(entry, rootManifest, installed, staged, shellApi, apiFloor);
        delete entry.badAddress;
    }

    function _classifyKind(entry, rootManifest, installed, staged, shellApi, apiFloor) {
        // A dependency taken only as a ticked soft one is asked for at its soft version
        const wants = entry.wants.length > 0 ? entry.wants : entry.softWants;
        const wantsText = wants.map(version => ModuleRules.show(version).replace(/^"|"$/g, "")).join(" and ");
        const has = ModuleRules.has(staged, entry.id);
        const manifest = has ? staged[entry.id] : null;
        const record = ModuleRules.has(installed, entry.id) ? installed[entry.id] : null;
        entry.name = _name(_readable(manifest) && manifest.id === entry.id ? manifest.name : record?.name, entry.id);
        const needs = "Needs " + entry.name + " " + wantsText + " — ";
        const neededBy = entry.neededBy.join(", ");
        // The fetched manifest's verdict: "" when it fits, else why not
        const fetchedMisfit = () => {
            if (!_readable(manifest) || manifest.id !== entry.id)
                return "its manifest could not be read";
            const api = ModuleRules.apiCompatibility(manifest.api, shellApi, apiFloor);
            if (!api.compatible)
                return api.reason;
            const misfit = _misfit(wants, manifest.exports);
            return misfit === "" ? "" : "the repository has " + misfit;
        };
        delete entry.softWants;
        entry.wants = wants;
        if (record !== null) {
            entry.from = typeof record.version === "string" ? record.version : "";
            const versionMisfit = ModuleRules.isObject(record) ? _misfit(wants, record.exports) : "nothing readable";
            // A copy that serves the version but asks an API this shell no longer has does not
            // load: it needs an update as much as a too old one
            const api = ModuleRules.isObject(record) ? ModuleRules.apiCompatibility(record.api, shellApi, apiFloor)
                                                     : { compatible: false, reason: "" };
            if (versionMisfit === "" && api.compatible) {
                entry.kind = "there";
                return;
            }
            const misfitText = versionMisfit !== "" ? _copyWords(record?.source) + " " + versionMisfit
                                                    : _copyWords(record?.source) + " " + entry.from + ", " + api.reason;
            if (!_updatable(record)) {
                entry.kind = "incompatible";
                entry.reason = needs + misfitText;
                return;
            }
            entry.address = record.address;
            entry.ref = typeof record.ref === "string" ? record.ref : "";
            entry.badAddress = false;
            if (!has) {
                entry.kind = "update";
                entry.fetch = true;
                entry.reason = neededBy + " needs " + wantsText;
                return;
            }
            const problem = fetchedMisfit();
            entry.to = _readable(manifest) && typeof manifest.version === "string" ? manifest.version : "";
            entry.kind = problem === "" ? "update" : "incompatible";
            entry.reason = problem === "" ? neededBy + " needs " + wantsText : needs + problem;
            if (problem === "")
                entry.breaks = _breaks(entry.id, manifest, installed, staged, rootManifest);
            return;
        }
        if (entry.address === "") {
            entry.kind = "unresolved";
            entry.reason = needs + (entry.badAddress ? "not installed, address not usable" : "not installed, no address given");
            return;
        }
        if (!has) {
            entry.kind = "download";
            entry.fetch = true;
            return;
        }
        const problem = fetchedMisfit();
        entry.to = _readable(manifest) && typeof manifest.version === "string" ? manifest.version : "";
        entry.kind = problem === "" ? "download" : "incompatible";
        entry.reason = problem === "" ? "" : needs + problem;
    }

    // The whole result from a settled walk
    function _finish(rootManifest, installed, staged, walk) {
        const entries = walk.entries;
        const fetch = entries.filter(entry => entry.fetch).map(entry => ({ id: entry.id, address: entry.address, ref: entry.ref }));
        const blocking = entries.filter(entry => !entry.soft && (entry.kind === "unresolved" || entry.kind === "incompatible"))
            .map(entry => entry.reason);
        // The root, when it replaces an installed copy, may leave dependents behind too
        const rootBreaks = ModuleRules.has(installed, rootManifest.id) ? _breaks(rootManifest.id, rootManifest, installed, staged, rootManifest) : [];
        const installing = entries.filter(entry => (entry.kind === "update" || entry.kind === "download") && !entry.fetch);
        const order = installOrder([rootManifest].concat(installing.map(entry => staged[entry.id])));
        return { refused: "", entries: entries, offers: walk.offers, fetch: fetch, complete: fetch.length === 0,
                 blocking: blocking, ready: fetch.length === 0 && blocking.length === 0, order: order,
                 rootBreaks: rootBreaks };
    }

    // The installed modules whose hard use of `id` the new manifest no longer serves (one
    // being updated in the same chain — the root `rootManifest` among them — is judged by its
    // new manifest, not its old uses)
    function _breaks(id, manifest, installed, staged, rootManifest) {
        const result = [];
        for (const otherId of Object.keys(installed).sort()) {
            if (otherId === id)
                continue;
            const newer = rootManifest && otherId === rootManifest.id ? rootManifest
                : ModuleRules.has(staged, otherId) && _readable(staged[otherId]) ? staged[otherId] : null;
            const uses = (newer ?? installed[otherId])?.uses;
            if (!Array.isArray(uses))
                continue;
            for (const use of uses)
                if (use?.id === id && use.optional !== true && _misfit([use.version], manifest.exports) !== "") {
                    result.push(otherId);
                    break;
                }
        }
        return result;
    }

    // "" when `exports` serves every version in `wants`, else what it has, in a few words
    function _misfit(wants, exports) {
        if (!ModuleRules.isObject(exports))
            return "no API to give";
        for (const version of wants)
            if (!ModuleMergeRules.usesFit(version, exports.version).fits)
                return typeof exports.version === "string" ? exports.version : ModuleRules.show(exports.version);
        return "";
    }

    function _copyWords(source) {
        switch (source) {
        case "system": return "the system's copy is";
        case "builtin": return "the built-in copy is";
        case "user": return "the copy placed by hand is";
        case "developer": return "the development copy is";
        default: return "the installed copy is";
        }
    }

    // Whether an installed module can be updated here: the shell installed it and its
    // recorded address can be fetched again
    function _updatable(record) {
        if (!ModuleRules.isObject(record))
            return false;
        if (record.source === "repository")
            return ModuleInstallRules.repositoryProblem(record.address) === "";
        if (record.source === "folder")
            return typeof record.address === "string" && _cleanPath(record.address) !== "";
        return false;
    }

    // A dependency's `source` → { address, ref, problem }: "<url>#<ref>" split; one the
    // download would refuse is no address at all (`problem` true), so it is never fetched
    function _address(source) {
        if (source === undefined || source === null || source === "")
            return { address: "", ref: "", problem: false };
        if (ModuleInstallRules.repositoryProblem(source) !== "")
            return { address: "", ref: "", problem: true };
        const parts = ModuleInstallRules.splitAddress(source);
        return { address: parts.url, ref: parts.ref, problem: false };
    }

    // A hard cycle reachable from the root, through the walked manifests and the installed
    // modules (a dependency that is there may use the root or a new one back), as
    // [a, b, …, a], or []. Soft uses never close one (the host breaks them at load). A cycle
    // among installed modules alone is not this chain's.
    function _cycle(rootManifest, installed, staged, walked) {
        const manifests = new Map();
        for (const id of Object.keys(installed))
            if (ModuleRules.isObject(installed[id]) && Array.isArray(installed[id].uses))
                manifests.set(id, installed[id]);
        for (const id of walked)
            if (_readable(ModuleRules.get(staged, id)))
                manifests.set(id, staged[id]);
        manifests.set(rootManifest.id, rootManifest);
        const edges = id => manifests.get(id).uses.filter(use => use?.optional !== true && manifests.has(use?.id))
            .map(use => use.id);
        const state = new Map();        // id → "open" while on the path, "done" after
        const stack = [];
        const visit = id => {
            state.set(id, "open");
            stack.push(id);
            for (const other of edges(id)) {
                if (state.get(other) === "open")
                    return stack.slice(stack.indexOf(other)).concat([other]);
                if (!state.has(other)) {
                    const found = visit(other);
                    if (found.length > 0)
                        return found;
                }
            }
            stack.pop();
            state.set(id, "done");
            return [];
        };
        return visit(rootManifest.id);
    }

    // The way from the root to `id` the walk took
    function _path(parent, id, rootId) {
        const path = [id];
        for (let step = parent.get(id); step !== undefined && path.length <= maxModules + maxDepth; step = parent.get(step)) {
            path.unshift(step);
            if (step === rootId)
                break;
        }
        return path;
    }

    // ---- Order ----

    // The order a set of modules installs (or updates) in: each after the ones it uses,
    // providers first — the host's load order (ModuleMergeRules.dependencyPlan), so a queue
    // of updates follows it too. `manifests`: [{ id, uses, exports }] → [ids]; unreadable
    // ones are left out.
    function installOrder(manifests) {
        const readable = (Array.isArray(manifests) ? manifests : []).filter(manifest => _readable(manifest));
        return ModuleMergeRules.dependencyPlan(readable, {}).order;
    }

    // ---- A failure halfway ----

    // How to take back a run that failed while installing: the user root as it was before.
    // Versions are named by their directory (`<version>-<commit7>`, ModuleInstallRules), never
    // by the version text: the same version from a new commit is another directory.
    // `run`: { stagingRoot — the staging place (ModuleInstallRules.paths().staging),
    //          staged: [directories] — every staging directory of the chain, each inside it,
    //          done: [{ id, kind: "install" | "update", dir, previousDir, existed, backup,
    //                   previousRecord }] — the modules already moved in, in the order they
    //            were; `existed` when `dir` was a kept version before this run (a refused
    //            update kept on disk), `previousRecord` the record's entry before the run }
    // → { actions: [...] in the order to carry out — the done ones last first:
    //       install: { action: "unlink", id }, { action: "deleteVersion", id, dir },
    //                { action: "dropRecord", id }
    //       update:  { action: "relink", id, dir: previousDir },
    //                { action: "restoreBackup", id, backup } (when one was taken),
    //                { action: "deleteVersion", id, dir } (only a directory this run made:
    //                  not the previous one, not one kept before),
    //                { action: "restoreRecord", id, previous }
    //     then { action: "deleteStaging", directory } for each staged one under the staging
    //       root,
    //     problems: [lines] — steps that could not be read; what they would touch is left
    //       alone (a new version without a previous one to relink to stays linked) }
    function rollbackPlan(run) {
        const actions = [];
        const problems = [];
        const done = Array.isArray(run?.done) ? run.done : [];
        if (run?.done !== undefined && !Array.isArray(run?.done))
            problems.push("the modules moved in are not known");
        for (let i = done.length - 1; i >= 0; i--) {
            const step = done[i];
            const id = step?.id;
            if (!ModuleManifestRules.validId(id)) {
                problems.push("step " + (i + 1) + ": no module id");
                continue;
            }
            const dir = _versionDir(step.dir);
            if (step.kind === "install") {
                actions.push({ action: "unlink", id: id });
                if (dir !== "")
                    actions.push({ action: "deleteVersion", id: id, dir: dir });
                else
                    problems.push(id + ": the version directory is not known; it is left");
                actions.push({ action: "dropRecord", id: id });
            } else if (step.kind === "update") {
                const previousDir = _versionDir(step.previousDir);
                if (previousDir === "") {
                    problems.push(id + ": the previous version is not known; the new one stays linked");
                    continue;
                }
                actions.push({ action: "relink", id: id, dir: previousDir });
                if (ModuleRules.isString(step.backup, 4096))
                    actions.push({ action: "restoreBackup", id: id, backup: step.backup });
                if (dir !== "" && dir !== previousDir && step.existed !== true)
                    actions.push({ action: "deleteVersion", id: id, dir: dir });
                if (ModuleRules.isObject(step.previousRecord))
                    actions.push({ action: "restoreRecord", id: id, previous: step.previousRecord });
                else
                    problems.push(id + ": its record before the update is not known; the record is left");
            } else {
                problems.push(id + ": " + ModuleRules.show(step.kind) + " is not a step that can be taken back");
            }
        }
        const stagingRoot = _cleanPath(run?.stagingRoot);
        if (stagingRoot === "" && Array.isArray(run?.staged) && run.staged.length > 0)
            problems.push("the staging place is not known; nothing staged is deleted");
        for (const directory of Array.isArray(run?.staged) ? run.staged : []) {
            const clean = _cleanPath(directory);
            // Only what lies inside the staging place: a path from a broken step must never
            // turn a cleanup into deleting something else
            if (stagingRoot !== "" && clean !== "" && clean.startsWith(stagingRoot + "/"))
                actions.push({ action: "deleteStaging", directory: clean });
            else if (stagingRoot !== "")
                problems.push("not inside the staging place: " + ModuleRules.show(directory));
        }
        return { actions: actions, problems: problems };
    }

    // A version directory's name ("1.2.0-abc1234"), "" for anything that is not one plain name
    function _versionDir(dir) {
        return typeof dir === "string" && /^[A-Za-z0-9][A-Za-z0-9._+-]{0,99}$/.test(dir) && dir !== "." && dir !== ".." ? dir : "";
    }

    // An absolute path with no "." or ".." segment, trailing slashes dropped; "" otherwise
    function _cleanPath(path) {
        if (typeof path !== "string" || !path.startsWith("/") || path.includes("\u0000"))
            return "";
        const parts = path.split("/").filter(part => part !== "");
        if (parts.length === 0 || parts.some(part => part === "." || part === ".."))
            return "";
        return "/" + parts.join("/");
    }

    // ---- Remove and Disable ----

    // Who needs module `id`. `modules`: [{ id, name, uses: [{ id, version, optional }],
    // state }] (the others on disk; `id` among them or not).
    // → { hard: [ids] — hard dependents, and theirs in turn ("These stop working:"),
    //     soft: [ids] — soft users of it or of those, that keep working ("These lose a
    //       feature:") — the shape of ModuleInstallRules.removalPlan's `dependents`,
    //     unknown: [ids] — modules whose uses cannot be read: they may need it }
    // Each list by name.
    function dependents(id, modules) {
        const known = _modules(modules);
        const stopping = _hardClosure(id, known);
        const losing = new Set();
        for (const module of known.list)
            if (module.uses !== null && module.id !== id && !stopping.has(module.id)
                    && module.uses.some(use => use.optional && (use.id === id || stopping.has(use.id))))
                losing.add(module.id);
        return { hard: _byName(stopping, known), soft: _byName(losing, known),
                 unknown: _byName(new Set(known.list.filter(module => module.uses === null && module.id !== id).map(module => module.id)), known) };
    }

    // What disabling module `id` disables with it — the modal's list ("These modules need it
    // and are disabled too:"): the running ones among its hard dependents and theirs; running
    // is "loaded" or "pending". Empty: the button's own "Disable?" is enough.
    // → { disabled: [ids], unknown: [ids] — running modules whose uses cannot be read }
    function disableList(id, modules) {
        const known = _modules(modules);
        const running = module => module.state === "loaded" || module.state === "pending";
        const stopping = _hardClosure(id, known);
        return { disabled: _byName(new Set(Array.from(stopping).filter(other => running(known.byId.get(other)))), known),
                 unknown: _byName(new Set(known.list.filter(module => module.uses === null && module.id !== id && running(module))
                                          .map(module => module.id)), known) };
    }

    // The dependencies installed for module `id` that nothing else needs once it is removed
    // — each offered unchecked with its removal ("Also remove Clipboard (installed for Notes,
    // nothing else uses it)"). `modules`: [{ id, name, uses, source, installedFor }] —
    // `source` ModuleInstallRules.sourceOf's kind.
    // Installed for it: `installedFor` is `id`, or another such dependency (a chain of two
    // recorded either way). One stays out when a module outside them (not `id`, not one of
    // them) uses it, hard or soft, or has uses that cannot be read. Only what the shell
    // installed (`repository`, `folder`) is offered: a module placed by hand, a development
    // copy, a built-in or a system one is the user's or someone else's to remove.
    // → [{ id, name, usedBy: [ids] }] by name — `usedBy` the other offered ones that use it:
    //   it may go only together with them.
    function orphans(id, modules) {
        const known = _modules(modules);
        const candidates = new Set();
        for (let grew = true; grew;) {
            grew = false;
            for (const module of known.list)
                if (!candidates.has(module.id) && module.id !== id && (module.source === "repository" || module.source === "folder")
                        && (module.installedFor === id || candidates.has(module.installedFor))) {
                    candidates.add(module.id);
                    grew = true;
                }
        }
        const usesOf = (module, other) => module.uses === null || module.uses.some(use => use.id === other);
        for (let shrank = true; shrank;) {
            shrank = false;
            for (const candidate of Array.from(candidates))
                if (known.list.some(module => module.id !== id && module.id !== candidate && !candidates.has(module.id)
                                    && usesOf(module, candidate))) {
                    candidates.delete(candidate);
                    shrank = true;
                }
        }
        return _byName(candidates, known).map(other => ({
            id: other, name: known.byId.get(other).name,
            usedBy: _byName(new Set(Array.from(candidates).filter(user => user !== other && usesOf(known.byId.get(user), other))), known)
        }));
    }

    // The modules as { list, byId }, each { id, name, uses (null when unreadable), state,
    // source, installedFor }; the first of an id counts
    function _modules(modules) {
        const byId = new Map();
        for (const module of Array.isArray(modules) ? modules : []) {
            const id = module?.id;
            if (typeof id !== "string" || id === "" || byId.has(id))
                continue;
            const uses = Array.isArray(module.uses) && module.uses.every(use => typeof use?.id === "string")
                ? module.uses.map(use => ({ id: use.id, optional: use.optional === true })) : null;
            byId.set(id, { id: id, name: _name(module.name, id), uses: uses, state: module.state,
                           source: module.source, installedFor: typeof module.installedFor === "string" ? module.installedFor : "" });
        }
        return { list: Array.from(byId.values()), byId: byId };
    }

    // The modules that need `id` through hard uses, directly or through each other
    function _hardClosure(id, known) {
        const result = new Set();
        for (let grew = true; grew;) {
            grew = false;
            for (const module of known.list)
                if (module.id !== id && !result.has(module.id) && module.uses !== null
                        && module.uses.some(use => !use.optional && (use.id === id || result.has(use.id)))) {
                    result.add(module.id);
                    grew = true;
                }
        }
        return result;
    }

    function _byName(ids, known) {
        return Array.from(ids).sort((first, second) => {
            const byName = known.byId.get(first).name.localeCompare(known.byId.get(second).name);
            return byName !== 0 ? byName : (first < second ? -1 : first > second ? 1 : 0);
        });
    }

    // ---- Small helpers ----

    // A manifest the walk can read: an id, a version, a list of uses
    function _readable(manifest) {
        return ModuleRules.isObject(manifest) && ModuleRules.isString(manifest.id, 200) && typeof manifest.version === "string"
            && Array.isArray(manifest.uses);
    }

    function _name(name, id) {
        const text = ModuleRules.isString(name, 100000) ? name.replace(/\s+/g, " ") : String(id);
        return text.length > maxNameLength ? text.slice(0, maxNameLength - 1) + "…" : text;
    }

    function _addOnce(list, value) {
        if (!list.includes(value))
            list.push(value);
    }

    function _sameSet(first, second) {
        return first.size === second.size && Array.from(first).every(value => second.has(value));
    }
}
