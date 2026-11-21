pragma Singleton

import Quickshell
import QtQuick

// The module system's decisions about updating an installed module (plan
// notes/plans/modules-management.md §6.3–§6.10): when an update needs the user's approval
// and what is only shown after it, the update queue (several modules, in dependency order,
// one restart offer at its end), which version directories stay on disk, the "Switch
// version" list, the part of a changelog shown, whether a found version is offered, when the
// daily automatic run is due, and what a configuration backup holds and which backups stay.
// Uses ModuleInstallRules' vocabulary (sources, addresses, the record keyed by version
// directory) and ModuleDependencyRules' chain and order. Pure: no file, no process, no clock
// of its own. Nothing here throws; input that cannot be read is unknown and unsafe — it asks,
// waits or keeps, never passes as fine. Checked by tests/ModuleUpdateRulesTest.qml.
Singleton {
    id: root

    // ---- Limits ----

    // Version directories kept per module: the active one, the one before it, and one
    // waiting or refused (§6.1)
    readonly property int maxKeptVersions: 3
    // Configuration backups kept per module (§6.10)
    readonly property int maxBackups: 5
    // The changelog: how much of the file is read, and how much of it is shown (§6.7)
    readonly property int maxChangelogBytes: 64 * 1024
    readonly property int maxChangelogLines: 200
    readonly property int maxChangelogCharacters: 20000
    // An install has no "from" version: the newest few sections are shown
    readonly property int installChangelogSections: 3
    // "Switch version": tags listed before "More…" (§6.8)
    readonly property int maxListedTags: 10
    // Notes under "New in this version" before "And N more" (§6.6)
    readonly property int maxAfterNotes: 12
    // Files of its data directory a manifest may name for a backup, and their path length
    readonly property int maxBackupPaths: 32
    readonly property int maxBackupPathLength: 200
    // The automatic run: once a day; after failures sooner, doubling from the first retry,
    // never later than the daily run
    readonly property int dayMs: 24 * 60 * 60 * 1000
    readonly property int firstRetryMs: 15 * 60 * 1000
    // Why a backup is taken (meta.json's `reason`)
    readonly property var backupReasons: ["update", "switch", "rollback", "restore"]

    // ---- Small helpers ----

    function _plain(value, most) {
        return ModuleInstallRules._plain(typeof value === "string" ? value : "", most);
    }

    function _version(value) {
        return _plain(value, ModuleInstallRules.maxVersionLength);
    }

    function _list(value) {
        return Array.isArray(value) ? value : [];
    }

    function _nameOf(manifest) {
        return _plain(manifest?.name) || _plain(manifest?.id) || "?";
    }

    // "Weather", "Weather and Notes", "Weather, Notes and Printers"
    function _joinNames(names) {
        const list = _list(names);
        if (list.length <= 1)
            return list.join("");
        return list.slice(0, -1).join(", ") + " and " + list[list.length - 1];
    }

    // A commit id as recorded: lower-case hex, 7 to 64 characters; "" otherwise
    function _commit(value) {
        return typeof value === "string" && /^[0-9a-f]{7,64}$/.test(value) ? value : "";
    }

    // Whether two commit ids name the same commit: one a prefix of the other, at least 7
    // characters each (a record may hold the short id, git the full one)
    function _sameCommit(first, second) {
        const a = _commit(first);
        const b = _commit(second);
        return a !== "" && b !== "" && (a.startsWith(b) || b.startsWith(a));
    }

    // A moment from a record (ms, or an ISO text) → ms, NaN when it cannot be read
    function _moment(value) {
        if (typeof value === "number")
            return Number.isFinite(value) ? value : NaN;
        if (typeof value === "string" && value !== "")
            return Date.parse(value);
        return NaN;
    }

    // A record entry fit to decide on: versions with plain directory names, the active one
    // among them; null otherwise (ModuleInstallRules.parseRecord's entries pass)
    function _record(record) {
        if (!ModuleRules.isObject(record) || !Array.isArray(record.versions) || record.versions.length === 0)
            return null;
        const dirs = new Set();
        for (const each of record.versions) {
            if (!ModuleRules.isObject(each) || !ModuleInstallRules._versionDirectory(each.dir) || typeof each.version !== "string"
                    || dirs.has(each.dir))
                return null;
            dirs.add(each.dir);
        }
        if (typeof record.active !== "string" || !dirs.has(record.active))
            return null;
        return record;
    }

    function _activeVersion(record) {
        return record.versions.find(each => each.dir === record.active);
    }

    // Whether a version ({ version, commit }) is the one the user refused (record.refused).
    // A refusal with its commit holds for that commit whatever the version text says (a tag
    // "v0.5.0" for a refused "0.5.0", a branch head with no version); only one recorded
    // without a commit holds by version, for every copy of it.
    function _isRefused(version, refused) {
        if (!ModuleRules.isObject(refused))
            return false;
        if (_commit(refused.commit) !== "")
            return _sameCommit(version?.commit, refused.commit);
        return typeof refused.version === "string" && refused.version !== "" && version?.version === refused.version;
    }

    // ---- Versions ----

    // "1.2.3", "v1.2", "2.0.0-rc.1" → { major, minor, patch, pre: [identifiers] }, or null
    function parseVersion(text) {
        if (typeof text !== "string" || text.length > 64)
            return null;
        const match = /^v?(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})(?:\.(0|[1-9][0-9]{0,8}))?(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$/.exec(text);
        if (!match)
            return null;
        return { major: Number(match[1]), minor: Number(match[2]), patch: Number(match[3] ?? 0),
                 pre: match[4] === undefined ? [] : match[4].split(".") };
    }

    // Semver order of two version texts: -1, 0 or 1; null when either does not parse (an
    // order that cannot be read is not guessed)
    function compareVersions(first, second) {
        const a = parseVersion(first);
        const b = parseVersion(second);
        if (!a || !b)
            return null;
        for (const field of ["major", "minor", "patch"])
            if (a[field] !== b[field])
                return a[field] < b[field] ? -1 : 1;
        // A pre-release comes before its release
        if (a.pre.length === 0 || b.pre.length === 0)
            return a.pre.length === b.pre.length ? 0 : (a.pre.length === 0 ? 1 : -1);
        for (let i = 0; i < Math.max(a.pre.length, b.pre.length); i++) {
            if (i >= a.pre.length)
                return -1;
            if (i >= b.pre.length)
                return 1;
            const x = a.pre[i];
            const y = b.pre[i];
            const xNumber = /^[0-9]+$/.test(x);
            const yNumber = /^[0-9]+$/.test(y);
            if (xNumber && yNumber && Number(x) !== Number(y))
                return Number(x) < Number(y) ? -1 : 1;
            if (xNumber !== yNumber)
                return xNumber ? -1 : 1;
            if (x !== y)
                return x < y ? -1 : 1;
        }
        return 0;
    }

    // ---- Consent for an update (§6.4) ----

    // Whether updating a module needs the user's approval, by hand and automatically alike.
    // `acknowledgement`: Config.acknowledgedModules[id] (ModuleInstallRules.acknowledgementOf's
    //   shape: { source, address, author, privileged });
    // `record`: the record's entry (ModuleInstallRules.parseRecord's modules[id]);
    // `newManifest`: the staged manifest ({ id, name, version, author, privileged: { why,
    //   programs } | absent, programs, optionalPrograms, uses });
    // `newAddress`: where the new version comes from (a repository's "#ref" does not count:
    //   a new tag of the same repository is the same source);
    // `context`: { dependencyPlan — ModuleDependencyRules.plan's result for the new manifest,
    //   currentManifest — the running version's manifest (for `after`), found: { program:
    //   bool }, names: { id: name } — the installed modules' names }.
    // → { needed, reasons: [{ kind, line, detail }], after: afterNotes(…) }
    //   kinds that need approval: "source" (another address or source kind), "author",
    //   "privileged" (first declares administrator actions), "newModule" (brings a module not
    //   installed), "breaks" (a new major would stop a dependent), "unresolved" (a dependency
    //   cannot be had), "chain" (the chain is refused), "unknown" (something needed to decide
    //   cannot be read). Going to a version that declares less never asks.
    function consentFor(acknowledgement, record, newManifest, newAddress, context) {
        const reasons = [];
        const name = _nameOf(newManifest);
        const version = _version(newManifest?.version);
        const title = name + (version !== "" ? " " + version : "");
        const add = (kind, line, detail) => reasons.push({ kind: kind, line: line, detail: detail ?? "" });
        const readableManifest = ModuleRules.isObject(newManifest) && ModuleManifestRules.validId(newManifest.id)
                                 && typeof newManifest.version === "string";
        if (!readableManifest)
            add("unknown", title + ": its manifest could not be read.");
        const ack = ModuleRules.isObject(acknowledgement) && typeof acknowledgement.address === "string"
                    && typeof acknowledgement.source === "string" ? acknowledgement : null;
        const kind = ModuleRules.isObject(record) && ["repository", "folder"].includes(record.kind) ? record.kind : "";
        if (!ack)
            add("unknown", title + ": its earlier approval could not be read.");
        if (kind === "")
            add("unknown", title + ": the record of where it came from could not be read.");
        if (ack && kind !== "") {
            const address = typeof newAddress !== "string" ? ""
                          : kind === "repository" ? ModuleInstallRules.splitAddress(newAddress).url : newAddress;
            const usable = address !== "" && (kind === "repository" ? ModuleInstallRules.repositoryProblem(address) === ""
                                                                     : ModuleInstallRules._cleanPath(address) !== "");
            if (!usable || ack.source !== kind || ack.address !== address)
                add("source", title + " comes from a different source.",
                    "From " + (usable ? ModuleInstallRules.addressShown(address) : "an unusable address")
                    + ", was " + ModuleInstallRules.addressShown(ack.address));
        }
        if (ack && readableManifest) {
            // An author added where none was named counts as changed, as for the first
            // confirmation (ModuleInstallRules.needsConfirmation)
            const author = typeof newManifest.author === "string" ? newManifest.author : "";
            const before = typeof ack.author === "string" ? ack.author : "";
            if (author !== before)
                add("author", title + " names a different author.",
                    (author !== "" ? "By " + _plain(author, 100) : "No author named")
                    + (before !== "" ? ", was " + _plain(before, 100) : ", none before"));
            // A declaration that is there but cannot be read may say anything: it asks
            if (newManifest.privileged !== undefined && !ModuleRules.isObject(newManifest.privileged))
                add("unknown", title + ": its administrator declaration could not be read.");
            if (ModuleRules.isObject(newManifest.privileged) && ack.privileged !== true) {
                const why = _plain(newManifest.privileged.why, 200);
                const programs = _list(newManifest.privileged.programs).map(program => _plain(program, 64)).filter(text => text !== "");
                const active = _record(record) ? _activeVersion(record).version : context?.currentManifest?.version;
                const parts = [];
                if (why !== "")
                    parts.push("For: " + why + ".");
                if (programs.length > 0)
                    parts.push("Programs: " + programs.join(", ") + ".");
                if (_version(active) !== "")
                    parts.push(_version(active) + " did not ask.");
                add("privileged", title + " asks for administrator rights.", parts.join(" "));
            }
        }
        _chainReasons(context?.dependencyPlan, title, context?.names, add);
        return { needed: reasons.length > 0, reasons: reasons,
                 after: afterNotes(context?.currentManifest, newManifest, { found: context?.found, names: context?.names }) };
    }

    // The chain's reasons (§6.4, 3 and 4; §6.9 "Unresolved"): a module not installed, a
    // dependent stopped, a dependency that cannot be had, a chain refused or not complete
    function _chainReasons(plan, title, names, add) {
        if (!ModuleRules.isObject(plan) || typeof plan.refused !== "string" || !Array.isArray(plan.entries)) {
            add("unknown", title + ": what it needs could not be read.");
            return;
        }
        if (plan.refused !== "") {
            add("chain", title + ": " + _plain(plan.refused) + ".");
            return;
        }
        if (plan.complete !== true) {
            add("unknown", title + ": what it needs is not downloaded yet.");
            return;
        }
        const nameOf = id => _plain(ModuleRules.isObject(names) && typeof ModuleRules.get(names, id) === "string" ? names[id] : id);
        for (const entry of plan.entries) {
            if (entry?.kind === "download")
                add("newModule", title + " needs " + _plain(entry.name) + ", which is not installed.");
            else if (entry?.kind === "update" && _list(entry.breaks).length > 0)
                add("breaks", _plain(entry.name) + (_version(entry.to) !== "" ? " " + _version(entry.to) : "")
                    + " would stop " + _joinNames(entry.breaks.map(nameOf)) + ".");
        }
        if (_list(plan.rootBreaks).length > 0)
            add("breaks", title + " would stop " + _joinNames(plan.rootBreaks.map(nameOf)) + ".");
        for (const line of _list(plan.blocking))
            add("unresolved", _plain(line) + ".");
    }

    // ---- After an update (§6.6) ----

    // What the card shows under "New in this version": not asked before, only told.
    // `oldManifest`, `newManifest`: the manifests before and after ({ version, programs,
    //   optionalPrograms, uses, privileged }); `context`: { found: { program: bool }, names:
    //   { id: name } }.
    // → [{ kind, line }] — "program" ("Needs the program curl — found"), "uses" ("Now uses
    //   Clipboard"), "major" ("Now 2.0: a major version"), "privilegedProgram" ("Now also
    //   runs nft as administrator"); capped, the rest one "And N more" line ("more").
    // An old manifest that cannot be read is compared as empty: everything is told.
    function afterNotes(oldManifest, newManifest, context) {
        if (!ModuleRules.isObject(newManifest))
            return [];
        const old = ModuleRules.isObject(oldManifest) ? oldManifest : {};
        const notes = [];
        const found = ModuleRules.isObject(context?.found) ? context.found : {};
        const names = ModuleRules.isObject(context?.names) ? context.names : {};
        const strings = list => _list(list).filter(each => typeof each === "string" && each !== "");
        const oldPrograms = strings(old.programs).concat(strings(old.optionalPrograms));
        const verdict = program => ModuleRules.get(found, program) === true ? " — found"
                                 : ModuleRules.get(found, program) === false ? " — missing" : "";
        for (const program of strings(newManifest.programs))
            if (!oldPrograms.includes(program))
                notes.push({ kind: "program", line: "Needs the program " + _plain(program, 64) + verdict(program) });
        for (const program of strings(newManifest.optionalPrograms))
            if (!oldPrograms.includes(program))
                notes.push({ kind: "program", line: "Can use the program " + _plain(program, 64) + verdict(program) });
        const oldUses = _list(old.uses).map(use => use?.id);
        for (const use of _list(newManifest.uses))
            if (typeof use?.id === "string" && !oldUses.includes(use.id)) {
                const usedName = _plain(typeof ModuleRules.get(names, use.id) === "string" ? names[use.id] : use.id);
                notes.push({ kind: "uses", line: (use.optional === true ? "Now can use " : "Now uses ") + usedName });
            }
        const before = parseVersion(old.version);
        const after = parseVersion(newManifest.version);
        if (before && after && after.major > before.major)
            notes.push({ kind: "major", line: "Now " + after.major + "." + after.minor + ": a major version" });
        // Programs added to a declaration the user already approved need no consent (§10, 4)
        if (ModuleRules.isObject(old.privileged) && ModuleRules.isObject(newManifest.privileged)) {
            const approved = strings(old.privileged.programs);
            for (const program of strings(newManifest.privileged.programs))
                if (!approved.includes(program))
                    notes.push({ kind: "privilegedProgram", line: "Now also runs " + _plain(program, 64) + " as administrator" });
        }
        if (notes.length > maxAfterNotes) {
            const rest = notes.length - (maxAfterNotes - 1);
            return notes.slice(0, maxAfterNotes - 1).concat([{ kind: "more", line: "And " + rest + " more" }]);
        }
        return notes;
    }

    // ---- The update queue (§6.5) ----

    // Row phases; the queue has ended when every row is in one of `_restingPhases`
    readonly property var _activePhases: ["downloading", "verifying", "backingUp", "installing"]
    readonly property var _restingPhases: ["done", "failed", "notFinished", "approval", "held"]
    readonly property var _finalPhases: ["done", "failed", "notFinished"]

    function emptyQueue() {
        return { rows: [], ended: true, offered: [], lastRun: 0 };
    }

    // One step of the update queue — a pure state machine. `queue`: the last result's queue
    // (null or emptyQueue() to start); `event`: one of
    //   { type: "add", items: [{ id, name, from, to, commit, uses, staged, consent }] }
    //       "Update", "Update all" or the automatic run; `staged` with `consent` (consentFor's
    //       result) and `uses` when the new version is already downloaded and verified
    //   { type: "progress", id, run, progress }  ModuleInstallRules.progressOf's result
    //   { type: "downloaded", id, run }
    //   { type: "verified", id, run, to, commit, uses, consent }
    //   { type: "approved" | "refused", id, to, commit }   the consent box's answer, keyed to
    //       the version it was asked about: an answer about another version is ignored
    //   { type: "backedUp", id, run }
    //   { type: "installed", id, run, restart }  `restart`: its new files need a restart
    //   { type: "failed", id, run, reason }
    //   `run`: the row's run token, from the subject of the action that started the work —
    //   each row queued anew gets a new one, so the answer of an earlier run of the same
    //   module (a download still finishing after it failed and was queued again) is ignored
    // → { queue, actions, offer, notification, summary, ignored }
    //   actions: [{ action: "download" | "verify" | "switch", id, subject: { id, to, commit, run } }
    //            | { action: "rememberRefusal", id, version, commit }]
    //   Downloads run side by side; one switch at a time (back up, unload, relink, load), each
    //   module after the modules of the queue it uses (ModuleDependencyRules.installOrder). A
    //   module whose provider in the queue failed or was refused fails; one whose provider
    //   waits for approval waits too ("held").
    //   offer: { text, ids } | null — once the whole queue has ended, the one "Restart shell"
    //     offer for the modules whose new files need it (never one per module; a consent
    //     accepted later makes its own);
    //   notification: { title, body, opens: "restart" | "changelog", ids } | null — the
    //     queue's one notification at its end, the restart merged into it;
    //   summary: queueSummary(queue).
    // An event for a row not in the queue, or in a phase that does not take it (a late
    // answer), changes nothing (`ignored`).
    function queueStep(queue, event) {
        const state = _copyQueue(queue);
        const actions = [];
        const result = ignored => {
            const ending = ignored ? { offer: null, notification: null } : _schedule(state, actions);
            return { queue: state, actions: actions, offer: ending.offer, notification: ending.notification,
                     summary: queueSummary(state), ignored: ignored };
        };
        const type = event?.type;
        if (type === "add") {
            const items = _list(event.items);
            let added = 0;
            if (state.ended) {
                // A new run: finished rows go, rows waiting for an answer stay
                state.rows = state.rows.filter(row => row.phase === "approval" || row.phase === "held");
                state.offered = [];
            }
            for (const item of items) {
                if (!ModuleRules.isObject(item) || !ModuleManifestRules.validId(item.id))
                    continue;
                const existing = state.rows.findIndex(row => row.id === item.id);
                if (existing >= 0 && !_finalPhases.includes(state.rows[existing].phase))
                    continue;           // already queued or waiting for its answer
                state.lastRun++;
                const row = _newRow(item, state.lastRun);
                if (existing >= 0)
                    state.rows[existing] = row;
                else
                    state.rows.push(row);
                added++;
                if (item.staged === true)
                    _verified(row, item);
                else
                    actions.push({ action: "download", id: row.id, subject: _subject(row) });
            }
            if (added === 0)
                return result(true);
            state.ended = false;
            return result(false);
        }
        const row = state.rows.find(each => each.id === event?.id);
        if (!row)
            return result(true);
        // The installer's reports name the run they belong to; the consent box's answers are
        // keyed to the version and commit they asked about instead
        if (type !== "approved" && type !== "refused" && event.run !== row.run)
            return result(true);
        switch (type) {
        case "progress":
            if (row.phase !== "downloading")
                return result(true);
            row.progress = ModuleRules.isObject(event.progress) ? {
                percent: ModuleRules.isNumber(event.progress.percent) ? event.progress.percent : null,
                bytes: ModuleRules.isNumber(event.progress.bytes) ? event.progress.bytes : null,
                rate: ModuleRules.isNumber(event.progress.rate) ? event.progress.rate : null
            } : null;
            return result(false);
        case "downloaded":
            if (row.phase !== "downloading")
                return result(true);
            row.phase = "verifying";
            row.progress = null;
            actions.push({ action: "verify", id: row.id, subject: _subject(row) });
            return result(false);
        case "verified":
            if (row.phase !== "verifying")
                return result(true);
            _verified(row, event);
            return result(false);
        case "approved":
        case "refused":
            if (row.phase !== "approval" || event.to !== row.to || !_sameCommit(event.commit, row.commit))
                return result(true);
            // The answer reopens an ended queue, so that its end is told again for this row
            state.ended = false;
            if (type === "approved") {
                row.approved = true;
                row.phase = "ready";
            } else {
                row.phase = "notFinished";
                actions.push({ action: "rememberRefusal", id: row.id, version: row.to, commit: row.commit });
            }
            return result(false);
        case "backedUp":
            if (row.phase !== "backingUp")
                return result(true);
            row.phase = "installing";
            return result(false);
        case "installed":
            if (row.phase !== "installing")
                return result(true);
            row.phase = "done";
            row.restart = event.restart === true;
            return result(false);
        case "failed":
            if (!_activePhases.includes(row.phase))
                return result(true);
            row.phase = "failed";
            row.reason = _plain(event.reason) || "no reason given";
            row.progress = null;
            return result(false);
        default:
            return result(true);
        }
    }

    // A queue to work on: a copy (the caller's stays as it was), or a new one when it cannot
    // be read
    function _copyQueue(queue) {
        if (!ModuleRules.isObject(queue) || !Array.isArray(queue.rows))
            return emptyQueue();
        let copy;
        try {
            copy = JSON.parse(JSON.stringify(queue));
        } catch (error) {
            return emptyQueue();
        }
        copy.rows = copy.rows.filter(row => ModuleRules.isObject(row) && ModuleManifestRules.validId(row.id));
        copy.offered = _list(copy.offered);
        copy.ended = copy.ended === true;
        copy.lastRun = Number.isInteger(copy.lastRun) && copy.lastRun >= 0 ? copy.lastRun : 0;
        // A token must never repeat one a row already holds
        for (const row of copy.rows)
            if (Number.isInteger(row.run) && row.run > copy.lastRun)
                copy.lastRun = row.run;
        return copy;
    }

    function _newRow(item, run) {
        return { id: item.id, run: run, name: _plain(item.name) || item.id, from: _version(item.from), to: _version(item.to),
                 commit: _commit(item.commit), uses: _uses(item.uses), phase: "downloading", reason: "",
                 progress: null, consentNeeded: false, consent: [], approved: false, restart: false, reported: "" };
    }

    // A manifest's uses as the queue keeps them; null when they cannot be read
    function _uses(uses) {
        if (!Array.isArray(uses) || !uses.every(use => ModuleRules.isObject(use) && typeof use.id === "string"))
            return null;
        return uses.map(use => ({ id: use.id, version: typeof use.version === "string" ? use.version : "", optional: use.optional === true }));
    }

    function _subject(row) {
        return { id: row.id, to: row.to, commit: row.commit, run: row.run };
    }

    // The new version is verified: its version, uses and whether it needs approval. A
    // manifest whose uses cannot be read cannot be ordered: it fails. A consent result that
    // cannot be read asks.
    function _verified(row, given) {
        if (typeof given.to === "string" && given.to !== "")
            row.to = _version(given.to);
        if (_commit(given.commit) !== "")
            row.commit = _commit(given.commit);
        row.uses = _uses(given.uses);
        if (row.uses === null) {
            row.phase = "failed";
            row.reason = "its manifest could not be read";
            return;
        }
        const consent = given.consent;
        const readable = ModuleRules.isObject(consent) && typeof consent.needed === "boolean";
        row.consentNeeded = !readable || consent.needed;
        row.consent = readable ? _list(consent.reasons).map(reason => ({ kind: String(reason?.kind ?? ""), line: _plain(reason?.line) }))
                               : [{ kind: "unknown", line: "Whether it needs approval could not be read." }];
        row.phase = row.consentNeeded ? "approval" : "ready";
    }

    // After every event: rows held behind or failed with their providers, the next switch,
    // and the end of the queue with its one offer and notification
    function _schedule(state, actions) {
        const order = ModuleDependencyRules.installOrder(state.rows.map(row => ({ id: row.id, version: row.to || "0", uses: row.uses ?? [] })));
        state.rows.sort((first, second) => order.indexOf(first.id) - order.indexOf(second.id));
        const byId = new Map(state.rows.map(row => [row.id, row]));
        const providersOf = row => _list(row.uses).filter(use => !use.optional && use.id !== row.id && byId.has(use.id))
            .map(use => byId.get(use.id));
        // A provider's end reaches its dependents, and theirs: settle until nothing changes
        for (let changed = true; changed;) {
            changed = false;
            for (const row of state.rows) {
                if (!["ready", "held", "approval"].includes(row.phase))
                    continue;
                const providers = providersOf(row);
                const lost = providers.find(provider => provider.phase === "failed" || provider.phase === "notFinished");
                const waiting = providers.find(provider => provider.phase === "approval" || provider.phase === "held");
                let phase = row.consentNeeded && !row.approved ? "approval" : "ready";
                let reason = "";
                if (lost) {
                    phase = "failed";
                    reason = "needs " + lost.name + ", which was not updated";
                } else if (waiting && phase === "ready") {
                    phase = "held";
                    reason = "waits for " + waiting.name;
                }
                if (phase !== row.phase || reason !== row.reason) {
                    row.phase = phase;
                    row.reason = reason;
                    changed = true;
                }
            }
        }
        const switching = state.rows.some(row => row.phase === "backingUp" || row.phase === "installing");
        if (!switching) {
            const next = state.rows.find(row => row.phase === "ready" && providersOf(row).every(provider => provider.phase === "done"));
            if (next) {
                next.phase = "backingUp";
                actions.push({ action: "switch", id: next.id, subject: _subject(next) });
            } else if (!state.rows.some(row => _activePhases.includes(row.phase))) {
                // Nothing running, nothing can start: the ready rows wait on each other (hard
                // uses in a cycle) and would wait for ever
                for (const row of state.rows.filter(each => each.phase === "ready")) {
                    row.phase = "failed";
                    row.reason = "its uses form a cycle in the queue";
                }
            }
        }
        const resting = state.rows.length > 0 && state.rows.every(row => _restingPhases.includes(row.phase));
        if (!resting || state.ended) {
            state.ended = state.ended && resting;
            return { offer: null, notification: null };
        }
        state.ended = true;
        return _ending(state);
    }

    // The queue has ended: what it says, once — rows already told about in their current
    // phase are not told again
    function _ending(state) {
        const fresh = state.rows.filter(row => row.reported !== row.phase);
        for (const row of fresh)
            row.reported = row.phase;
        const restart = state.rows.filter(row => row.phase === "done" && row.restart && !state.offered.includes(row.id));
        for (const row of restart)
            state.offered.push(row.id);
        const restartNames = _joinNames(restart.map(row => row.name));
        const offer = restart.length > 0
            ? { text: "Restart the shell to load the new files of " + restartNames + ".", ids: restart.map(row => row.id) }
            : null;
        const done = fresh.filter(row => row.phase === "done");
        const sentences = [];
        if (done.length > 0)
            sentences.push("Modules updated: " + done.map(row => row.name + (row.to !== "" ? " " + row.to : "")).join(", ") + ".");
        for (const row of fresh) {
            if (row.phase === "approval")
                sentences.push(row.name + ": approval required.");
            else if (row.phase === "notFinished")
                sentences.push(row.name + ": not finished.");
            else if (row.phase === "failed")
                sentences.push(row.name + ": failed.");
        }
        if (restart.length > 0)
            sentences.push("Restart the shell to finish updating " + restartNames + ".");
        const notification = sentences.length === 0 ? null : {
            title: restart.length > 0 ? "Restart needed" : done.length > 0 ? "Modules updated" : "Module updates",
            body: sentences.join(" "),
            opens: restart.length > 0 ? "restart" : "changelog",
            ids: done.map(row => row.id)
        };
        return { offer: offer, notification: notification };
    }

    // The queue's title line: { title: "Updating" | "Updates finished", count: "2 of 3",
    // finished, total } — finished: rows done, failed, refused or waiting for an answer
    function queueSummary(queue) {
        const rows = ModuleRules.isObject(queue) ? _list(queue.rows) : [];
        const finished = rows.filter(row => _restingPhases.includes(row?.phase)).length;
        return { title: rows.length > 0 && queue.ended === true ? "Updates finished" : "Updating",
                 count: finished + " of " + rows.length, finished: finished, total: rows.length };
    }

    // A queue row as the page shows it: "Weather 1.2.0 → 1.3.0 — Downloading 45% · 2.4 MiB/s"
    function rowText(row) {
        const versions = (row?.from ? " " + row.from : "") + (row?.to ? (row?.from ? " → " : " ") + row.to : "");
        const head = _plain(row?.name) + versions + " — ";
        switch (row?.phase) {
        case "downloading": {
            const parts = [];
            if (ModuleRules.isNumber(row.progress?.percent))
                parts.push(Math.round(row.progress.percent) + "%");
            if (ModuleRules.isNumber(row.progress?.rate))
                parts.push(sizeText(row.progress.rate) + "/s");
            return head + "Downloading" + (parts.length > 0 ? " " + parts.join(" · ") : "");
        }
        case "verifying": return head + "Verifying";
        case "ready": return head + "Waiting";
        case "held": return head + "Waits for " + _plain(row.reason).replace(/^waits for /, "");
        case "approval": return head + "Approval required";
        case "backingUp": return head + "Backing up settings";
        case "installing": return head + "Installing";
        case "done": return head + "Done";
        case "notFinished": return head + "Not finished";
        case "failed": return head + "Failed: " + (_plain(row.reason) || "no reason given");
        default: return head + "Unknown";
        }
    }

    // A size as "1.2 MiB"
    function sizeText(bytes) {
        const value = Number(bytes);
        if (!Number.isFinite(value) || value < 0)
            return "";
        const units = ["B", "KiB", "MiB", "GiB"];
        let size = value;
        let unit = 0;
        while (size >= 1024 && unit < units.length - 1) {
            size /= 1024;
            unit++;
        }
        return (unit === 0 ? String(Math.round(size)) : size.toFixed(1)) + " " + units[unit];
    }

    // ---- Versions kept on disk (§6.1) ----

    // Which version directories of a module stay after a switch. `record`: the record's
    // entry; `options`: { previousDir — the version switched from, pendingDir — one
    // downloaded and waiting }.
    // → { ok, keep: [dirs], delete: [dirs] } — the active one, the refused one and the one
    //   waiting in the queue are always kept; then the previous, then the newest fetched, up
    //   to maxKeptVersions.
    //   A record that cannot be read deletes nothing (ok false).
    function keepPlan(record, options) {
        const entry = _record(record);
        if (!entry)
            return { ok: false, keep: [], delete: [] };
        const keep = [entry.active];
        for (const version of entry.versions)
            if ((_isRefused(version, entry.refused) || version.dir === options?.pendingDir) && !keep.includes(version.dir))
                keep.push(version.dir);
        const others = entry.versions.filter(version => !keep.includes(version.dir)).slice().sort((first, second) => {
            const rank = version => version.dir === options?.previousDir ? 0 : 1;
            if (rank(first) !== rank(second))
                return rank(first) - rank(second);
            const a = _moment(first.fetchedAt);
            const b = _moment(second.fetchedAt);
            // Unreadable times last: the oldest is what goes first
            return (Number.isNaN(b) ? -Infinity : b) - (Number.isNaN(a) ? -Infinity : a);
        });
        const remove = [];
        for (const version of others) {
            if (keep.length < maxKeptVersions)
                keep.push(version.dir);
            else
                remove.push(version.dir);
        }
        return { ok: true, keep: keep, delete: remove };
    }

    // ---- Switch version (§6.8) ----

    // The "Switch version…" list. `record`: the record's entry; `tags`: [{ name, version,
    // commit, date }] from the check (`version` the tag's version text, default the name);
    // `head`: { branch, commit } of the recorded branch, or null.
    // → { ok, kept: [entry], tags: [entry], more, head: entry | null }
    //   an entry: { kind: "kept" | "tag" | "head", label, version, commit, dir, ref, state,
    //   older } — `state` for a kept one "active", "kept", "downloaded" or "notFinished";
    //   `older` before the active version (it may not read what a newer one wrote).
    //   Tags newest first — by semver where it parses, then the others by date —, the
    //   maxListedTags newest, `more` how many beyond; a tag or head already kept is not
    //   repeated. A record that cannot be read lists nothing.
    function versionList(record, tags, head) {
        const entry = _record(record);
        if (!entry)
            return { ok: false, kept: [], tags: [], more: 0, head: null };
        const active = _activeVersion(entry);
        const activeTime = _moment(active.fetchedAt);
        const keptCommits = entry.versions.map(version => version.commit);
        const isKept = commit => keptCommits.some(other => _sameCommit(other, commit));
        const kept = entry.versions.map(version => {
            const order = compareVersions(version.version, active.version);
            const time = _moment(version.fetchedAt);
            const newer = order !== null ? order > 0 : !Number.isNaN(time) && !Number.isNaN(activeTime) && time > activeTime;
            const older = order !== null ? order < 0 : !Number.isNaN(time) && !Number.isNaN(activeTime) && time < activeTime;
            const state = version.dir === entry.active ? "active" : _isRefused(version, entry.refused) ? "notFinished"
                        : newer ? "downloaded" : "kept";
            const words = { active: "active", kept: "kept", downloaded: "downloaded", notFinished: "not finished" };
            return { kind: "kept", label: _version(version.version) + " — " + words[state] + (older && state !== "active" ? " · older" : ""),
                     version: version.version, commit: version.commit, dir: version.dir, ref: "", state: state,
                     older: older && state !== "active", time: time };
        }).sort((first, second) => {
            const order = compareVersions(second.version, first.version);
            if (order !== null && order !== 0)
                return order;
            return (Number.isNaN(second.time) ? -Infinity : second.time) - (Number.isNaN(first.time) ? -Infinity : first.time);
        }).map(each => {
            delete each.time;
            return each;
        });
        const remote = _list(tags).filter(tag => ModuleRules.isObject(tag) && typeof tag.name === "string"
                                                  && ModuleInstallRules._refProblem(tag.name) === "" && _commit(tag.commit) !== ""
                                                  && !isKept(tag.commit))
            .map(tag => {
                const version = typeof tag.version === "string" && tag.version !== "" ? tag.version : tag.name;
                const order = compareVersions(version, active.version);
                return { kind: "tag", label: _plain(tag.name, ModuleInstallRules.maxVersionLength), version: version,
                         commit: tag.commit, dir: "", ref: tag.name, state: "", older: order !== null && order < 0,
                         parsed: parseVersion(version) !== null, time: _moment(tag.date) };
            })
            .sort((first, second) => {
                if (first.parsed !== second.parsed)
                    return first.parsed ? -1 : 1;
                if (first.parsed) {
                    const order = compareVersions(second.version, first.version);
                    if (order !== 0)
                        return order;
                }
                return (Number.isNaN(second.time) ? -Infinity : second.time) - (Number.isNaN(first.time) ? -Infinity : first.time);
            });
        const listed = remote.slice(0, maxListedTags).map(each => {
            delete each.parsed;
            delete each.time;
            return each;
        });
        let headEntry = null;
        if (ModuleRules.isObject(head) && typeof head.branch === "string" && ModuleInstallRules._refProblem(head.branch) === ""
                && _commit(head.commit) !== "" && !isKept(head.commit))
            headEntry = { kind: "head", label: _plain(head.branch, ModuleInstallRules.maxVersionLength) + " — latest commit " + head.commit.slice(0, 7),
                          version: "", commit: head.commit, dir: "", ref: head.branch, state: "", older: false };
        return { ok: true, kept: kept, tags: listed, more: Math.max(0, remote.length - maxListedTags), head: headEntry };
    }

    // ---- What's new (§6.7) ----

    // The part of a changelog shown for an update from `fromVersion` to `toVersion` (an
    // install: `fromVersion` empty). `text`: the file's text (only its first
    // maxChangelogBytes count).
    // → { text, cut, none } — the sections whose "## <version>" heading lies after the
    //   installed version up to the new one; for an install the newest few up to the new one;
    //   when none does (no headings, versions that do not parse, the same version from a new
    //   commit), the text's start. Plain text: control and bidi characters go, line breaks
    //   stay; at most maxChangelogLines lines and maxChangelogCharacters characters, then
    //   "(cut)". No text: none, "No changelog".
    function changelogSince(text, fromVersion, toVersion) {
        const none = { text: "No changelog", cut: false, none: true };
        if (typeof text !== "string")
            return none;
        const lines = _changelogLines(_utf8Prefix(text, maxChangelogBytes));
        if (lines.join("").trim() === "")
            return none;
        const sections = [];
        for (let i = 0; i < lines.length; i++) {
            const heading = /^##\s+\[?v?([0-9][0-9A-Za-z.+-]*)\]?(?:\s|$)/.exec(lines[i]);
            if (heading)
                sections.push({ version: heading[1], start: i, end: lines.length });
            else if (/^##?\s/.test(lines[i]) && sections.length > 0 && sections[sections.length - 1].end === lines.length)
                sections[sections.length - 1].end = i;
        }
        for (let i = 0; i < sections.length - 1; i++)
            sections[i].end = Math.min(sections[i].end, sections[i + 1].start);
        const install = typeof fromVersion !== "string" || fromVersion === "";
        let chosen = sections.filter(section => {
            const upTo = compareVersions(section.version, toVersion);
            if (upTo === null || upTo > 0)
                return false;
            if (install)
                return true;
            const after = compareVersions(section.version, fromVersion);
            return after !== null && after > 0;
        });
        if (install)
            chosen = chosen.slice(0, installChangelogSections);
        let shown = chosen.length > 0 ? [].concat(...chosen.map(section => lines.slice(section.start, section.end))) : lines;
        while (shown.length > 0 && shown[shown.length - 1].trim() === "")
            shown = shown.slice(0, -1);
        let cut = false;
        if (shown.length > maxChangelogLines) {
            shown = shown.slice(0, maxChangelogLines);
            cut = true;
        }
        let joined = shown.join("\n");
        if (joined.length > maxChangelogCharacters) {
            joined = joined.slice(0, maxChangelogCharacters);
            cut = true;
        }
        return { text: cut ? joined + "\n(cut)" : joined, cut: cut, none: false };
    }

    // The longest start of `text` whose UTF-8 form fits in `maxBytes` (the file is read up to
    // that many bytes; a character is never split)
    function _utf8Prefix(text, maxBytes) {
        let bytes = 0;
        let length = 0;
        for (const character of text) {
            const code = character.codePointAt(0);
            bytes += code < 0x80 ? 1 : code < 0x800 ? 2 : code < 0x10000 ? 3 : 4;
            if (bytes > maxBytes)
                break;
            length += character.length;
        }
        return text.slice(0, length);
    }

    // A text's lines as plain text: tabs as spaces, other control characters and bidi
    // controls dropped (they could reorder what a line seems to say)
    function _changelogLines(text) {
        return text.replace(/\r\n?/g, "\n").split("\n")
            .map(line => line.replace(/\t/g, "    ").replace(/[\u0000-\u001f\u007f-\u009f‎‏‪-‮⁦-⁩]/g, ""));
    }

    // ---- Whether a found version is offered (§6.3) ----

    // What a check found, judged against the record. `record`: the record's entry; `check`:
    // { version, commit } — the newest tag or the branch's head.
    // → { offer, reason, version, commit, sameVersion, downloadedDir }
    //   reason "current" (the active commit), "refused" (the version the user refused: never
    //   offered again, never switched to automatically — a newer one is), "older" (before the
    //   active version), "available" (a newer version, or the same version from a new
    //   commit), "unknown" (record or check cannot be read: nothing offered);
    //   `downloadedDir` the kept directory holding it already, else "".
    function offerFor(record, check) {
        const entry = _record(record);
        const version = typeof check?.version === "string" ? check.version : "";
        const commit = _commit(check?.commit);
        const answer = (offer, reason, extra) => Object.assign({ offer: offer, reason: reason, version: version, commit: commit,
                                                                 sameVersion: false, downloadedDir: "" }, extra ?? {});
        if (!entry || !ModuleRules.isObject(check) || check.ok === false || commit === "")
            return answer(false, "unknown");
        const active = _activeVersion(entry);
        if (_sameCommit(commit, active.commit))
            return answer(false, "current");
        if (_isRefused({ version: version, commit: commit }, entry.refused))
            return answer(false, "refused");
        const order = compareVersions(version, active.version);
        if (order !== null && order < 0)
            return answer(false, "older");
        const kept = entry.versions.find(each => _sameCommit(each.commit, commit));
        return answer(true, "available", { sameVersion: version === active.version, downloadedDir: kept ? kept.dir : "" });
    }

    // ---- The automatic run (§6.3) ----

    // Whether the daily automatic update run is due. `state`: what autoRunRecord keeps
    // ({ lastAttemptAt (ms) — the last run's start, failures — runs failed in a row,
    // lastOutcome }); `enabled`: modules.autoUpdate is "Automatically" now; `locked`: false
    // only when the session is known unlocked now; `nowMs`: the clock.
    // → { due, reason, nextAt } — reason "off", "locked", "first" (never ran), "daily",
    //   "retry" (after failures: 15 min, doubling, at most a day), "waiting", "unknown"
    //   (a last run that cannot be read or lies in the future: due, so a broken record never
    //   stops updates), "noClock" (no time to decide by: not due).
    function autoRunDue(state, enabled, locked, nowMs) {
        if (enabled !== true)
            return { due: false, reason: "off", nextAt: null };
        if (locked !== false)
            return { due: false, reason: "locked", nextAt: null };
        if (!ModuleRules.isNumber(nowMs))
            return { due: false, reason: "noClock", nextAt: null };
        const last = state?.lastAttemptAt;
        if (last === undefined || last === null)
            return { due: true, reason: "first", nextAt: nowMs };
        if (!ModuleRules.isNumber(last) || last > nowMs)
            return { due: true, reason: "unknown", nextAt: nowMs };
        const failures = Number.isInteger(state?.failures) && state.failures > 0 ? state.failures : 0;
        const wait = failures === 0 ? dayMs : Math.min(dayMs, firstRetryMs * Math.pow(2, Math.min(failures - 1, 20)));
        const nextAt = last + wait;
        if (nowMs >= nextAt)
            return { due: true, reason: failures === 0 ? "daily" : "retry", nextAt: nextAt };
        return { due: false, reason: "waiting", nextAt: nextAt };
    }

    // The automatic run's state after a run with `outcome` ("ok" or "failed") at `nowMs`, and
    // whether to log it: only when the outcome differs from the last one.
    // → { state: { lastAttemptAt, failures, lastOutcome }, log } — only what the run leaves
    //   behind is kept; whether runs are on and the lock are read anew each time
    function autoRunRecord(state, outcome, nowMs) {
        const failed = outcome !== "ok";
        const previous = Number.isInteger(state?.failures) && state.failures > 0 ? state.failures : 0;
        const next = {
            lastAttemptAt: ModuleRules.isNumber(nowMs) ? nowMs : null,
            failures: failed ? previous + 1 : 0,
            lastOutcome: failed ? "failed" : "ok"
        };
        return { state: next, log: state?.lastOutcome !== next.lastOutcome };
    }

    // ---- Configuration backups (§6.10) ----

    // What a configuration backup of module `id` holds and where it goes. `manifest`: the
    // active version's manifest — its `backup` lists paths inside its data directory that
    // belong in a backup; `options`: { dataHome, configHome, version, commit, reason (one of
    // backupReasons), nowMs }.
    // → { ok, problem, directory, staging, name, items, skipped, meta }
    //   items: { what: "settings", prefix: "mod.<id>." } (every profile, values as stored),
    //          { what: "store", from: <stores>/<id>, to: "store", noLinks: true },
    //          { what: "data", from: <data>/<id>/<path>, to: "data/<path>", noLinks: true } —
    //            `noLinks`: copied without following links (a link is copied as a link, never
    //            what it points to), and `from` used only when its resolved path lies inside
    //            the store or the data directory — a link must not pull other files in;
    //            data items only for the paths the manifest names, the data directory itself
    //            never;
    //   skipped: [{ path, why }] — named paths refused (outside the data directory, not a
    //     plain relative path, beyond the cap);
    //   directory: <backups>/<id>/<version>-<YYYYMMDD-HHMMSS> (UTC), written in `staging`
    //     beside it and renamed in;
    //   meta: meta.json's { id, version, commit, takenAt, reason, includesData }.
    function backupPlan(id, manifest, options) {
        const refused = problem => ({ ok: false, problem: problem, directory: "", staging: "", name: "", items: [], skipped: [], meta: null });
        if (!ModuleManifestRules.validId(id))
            return refused("Not a module id");
        if (!backupReasons.includes(options?.reason))
            return refused("No reason given for the backup");
        const places = ModuleInstallRules.paths(options?.dataHome, options?.configHome);
        if (places.backups === "" || places.stores === "" || places.data === "")
            return refused("The data or config home is not an absolute path");
        if (!ModuleRules.isNumber(options?.nowMs))
            return refused("No time for the backup's name");
        const moment = new Date(options.nowMs);
        const pad = number => (number < 10 ? "0" : "") + number;
        const stamp = moment.getUTCFullYear() + pad(moment.getUTCMonth() + 1) + pad(moment.getUTCDate()) + "-"
                    + pad(moment.getUTCHours()) + pad(moment.getUTCMinutes()) + pad(moment.getUTCSeconds());
        const version = typeof options.version === "string" && ModuleInstallRules._versionDirectory(options.version)
                        && options.version.length <= ModuleInstallRules.maxVersionLength ? options.version : "unknown";
        const name = version + "-" + stamp;
        const items = [{ what: "settings", prefix: "mod." + id + "." },
                       { what: "store", from: places.stores + "/" + id, to: "store", noLinks: true }];
        const skipped = [];
        const named = manifest?.backup;
        if (named !== undefined && !Array.isArray(named))
            skipped.push({ path: ModuleRules.show(named), why: "not a list of paths" });
        for (const path of _list(named)) {
            const why = _backupPathProblem(path);
            if (why !== "")
                skipped.push({ path: typeof path === "string" ? _plain(path) : ModuleRules.show(path), why: why });
            else if (items.filter(item => item.what === "data").length >= maxBackupPaths)
                skipped.push({ path: _plain(path), why: "more than " + maxBackupPaths + " paths named" });
            else if (!items.some(item => item.what === "data" && item.to === "data/" + _cleanRelative(path)))
                items.push({ what: "data", from: places.data + "/" + id + "/" + _cleanRelative(path), to: "data/" + _cleanRelative(path), noLinks: true });
        }
        return {
            ok: true, problem: "", name: name,
            directory: places.backups + "/" + id + "/" + name,
            staging: places.backups + "/" + id + "/.incoming-" + name,
            items: items, skipped: skipped,
            meta: { id: id, version: version, commit: _commit(options.commit), takenAt: options.nowMs, reason: options.reason,
                    includesData: items.some(item => item.what === "data") }
        };
    }

    // Why a path the manifest names for a backup is refused, "" when it is a plain path
    // inside the data directory
    function _backupPathProblem(path) {
        if (typeof path !== "string" || path === "")
            return "not a path";
        if (path.length > maxBackupPathLength)
            return "longer than " + maxBackupPathLength + " characters";
        if (/[\u0000-\u001f\u007f]/.test(path))
            return "contains control characters";
        if (path.startsWith("/") || path.startsWith("~"))
            return "outside its data directory";
        const parts = path.split("/").filter(part => part !== "" && part !== ".");
        if (parts.includes(".."))
            return "outside its data directory";
        if (parts.length === 0)
            return "the whole data directory";
        return "";
    }

    function _cleanRelative(path) {
        return path.split("/").filter(part => part !== "" && part !== ".").join("/");
    }

    // Which backups of a module stay once a new one is in. `entries`: the backup directories,
    // each { dir, takenAt } — `takenAt` from its meta.json, else the time in its name.
    // → { keep: [dirs], delete: [dirs], unknown: [dirs] } — the newest maxBackups kept; one
    //   whose name or time cannot be read, or a staging leftover (a name starting with "."),
    //   is left alone and not counted (never deleted on a guess).
    function backupKeepPlan(entries) {
        const readable = [];
        const unknown = [];
        for (const entry of _list(entries)) {
            const dir = typeof entry === "string" ? entry : entry?.dir;
            // A name starting with "." is a staging directory left over, never a backup
            if (!ModuleInstallRules._versionDirectory(dir) || dir.startsWith(".")) {
                if (typeof dir === "string")
                    unknown.push(dir);
                continue;
            }
            let time = _moment(entry?.takenAt);
            if (Number.isNaN(time)) {
                const stamp = /-(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})$/.exec(dir);
                time = stamp ? Date.UTC(Number(stamp[1]), Number(stamp[2]) - 1, Number(stamp[3]), Number(stamp[4]),
                                        Number(stamp[5]), Number(stamp[6])) : NaN;
            }
            if (Number.isNaN(time))
                unknown.push(dir);
            else
                readable.push({ dir: dir, time: time });
        }
        readable.sort((first, second) => second.time - first.time || (first.dir < second.dir ? 1 : -1));
        return { keep: readable.slice(0, maxBackups).map(each => each.dir),
                 delete: readable.slice(maxBackups).map(each => each.dir), unknown: unknown };
    }
}
