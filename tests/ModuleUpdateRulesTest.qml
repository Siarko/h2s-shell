import QtQuick
import qs.singletons

// ModuleUpdateRules (pure): consent for an update and what is only shown after, the update
// queue (dependency order, approval, refusal, failures, one restart offer at its end), the
// versions kept on disk, the "Switch version" list, the changelog shown with its caps, which
// found version is offered, the daily automatic run with its backoff, and what a backup
// holds and which backups stay. Malformed input never reads as fine.
TestCase {
    id: suite
    suiteName: "ModuleUpdateRules"

    readonly property string _commitA: "a".repeat(40)
    readonly property string _commitB: "b".repeat(40)
    readonly property string _commitC: "c".repeat(40)
    readonly property string _commitD: "d".repeat(40)
    readonly property string _commitE: "e".repeat(40)
    readonly property string _address: "https://codeberg.org/anna/weather"

    function _record(versions, active, refused) {
        return { kind: "repository", address: _address, ref: "main", versions: versions, active: active,
                 refused: refused ?? null, installedFor: "", checkedAt: "" };
    }

    function _version(dir, version, commit, fetchedAt) {
        return { dir: dir, version: version, commit: commit, fetchedAt: fetchedAt };
    }

    function _weatherRecord() {
        return _record([_version("1.2.0-aaaaaaa", "1.2.0", _commitA, 1000)], "1.2.0-aaaaaaa");
    }

    function _acknowledgement(extra) {
        return Object.assign({ source: "repository", address: _address, author: "Anna", privileged: false }, extra ?? {});
    }

    function _manifest(extra) {
        return Object.assign({ id: "weather", name: "Weather", version: "1.3.0", author: "Anna", programs: [], optionalPrograms: [],
                               uses: [] }, extra ?? {});
    }

    readonly property var _cleanPlan: ({ refused: "", entries: [], offers: [], fetch: [], complete: true, blocking: [],
                                         ready: true, order: ["weather"], rootBreaks: [] })

    function _kinds(result) {
        return result.reasons.map(reason => reason.kind).join(",");
    }

    function run() {
        _versions();
        _consent();
        _consentChain();
        _consentMalformed();
        _afterNotes();
        _queueOfThree();
        _queueRefusal();
        _queueFailures();
        _queueHeld();
        _queueMalformed();
        _keepPlan();
        _versionList();
        _changelog();
        _offer();
        _autoRun();
        _backupPlan();
        _backupKeepPlan();
    }

    function _versions() {
        assertEqual(ModuleUpdateRules.compareVersions("1.10.0", "1.9.0"), 1, "versions: numeric, not text order");
        assertEqual(ModuleUpdateRules.compareVersions("2.0.0-rc.1", "2.0.0"), -1, "versions: a pre-release before its release");
        assertEqual(ModuleUpdateRules.compareVersions("2.0.0-rc.2", "2.0.0-rc.10"), -1, "versions: pre-release numbers numeric");
        assertEqual(ModuleUpdateRules.compareVersions("v1.2", "1.2.0"), 0, "versions: a leading v and a missing patch");
        assertEqual(ModuleUpdateRules.compareVersions("latest", "1.2.0"), null, "versions: unparsed is no order, not a guess");
        assertEqual(ModuleUpdateRules.parseVersion(42), null, "versions: no text, no version");
    }

    function _consent() {
        const same = ModuleUpdateRules.consentFor(_acknowledgement(), _weatherRecord(), _manifest(), _address + "#v1.3.0",
                                                  { dependencyPlan: _cleanPlan });
        assertEqual(same.needed, false, "consent: same source, author, no privileged — none needed");
        assertEqual(same.reasons.length, 0, "consent: and no reasons");

        const moved = ModuleUpdateRules.consentFor(_acknowledgement(), _weatherRecord(), _manifest(), "https://github.com/x/weather.git",
                                                   { dependencyPlan: _cleanPlan });
        assertEqual(_kinds(moved), "source", "consent: another address needs approval");
        assertEqual(moved.reasons[0].line, "Weather 1.3.0 comes from a different source.", "consent: the source line");
        assertEqual(moved.reasons[0].detail, "From github.com/x/weather, was codeberg.org/anna/weather", "consent: from where, was where");

        const otherKind = ModuleUpdateRules.consentFor(_acknowledgement({ source: "folder" }), _weatherRecord(), _manifest(), _address,
                                                       { dependencyPlan: _cleanPlan });
        assertEqual(_kinds(otherKind), "source", "consent: another source kind at the same address needs approval");

        const author = ModuleUpdateRules.consentFor(_acknowledgement(), _weatherRecord(), _manifest({ author: "Mallory" }), _address,
                                                    { dependencyPlan: _cleanPlan });
        assertEqual(_kinds(author), "author", "consent: another author needs approval");
        assertEqual(author.reasons[0].detail, "By Mallory, was Anna", "consent: the authors named");
        const added = ModuleUpdateRules.consentFor(_acknowledgement({ author: "" }), _weatherRecord(), _manifest(), _address,
                                                   { dependencyPlan: _cleanPlan });
        assertEqual(_kinds(added), "author", "consent: an author named where none was counts as changed");

        const printers = _manifest({ id: "printers", name: "Printers", version: "0.5.0",
                                     privileged: { why: "Add and remove printers", programs: ["lpadmin"] } });
        const first = ModuleUpdateRules.consentFor(_acknowledgement(), _weatherRecord(), printers, _address, { dependencyPlan: _cleanPlan });
        assertEqual(_kinds(first), "privileged", "consent: first declaring administrator actions needs approval");
        assertEqual(first.reasons[0].line, "Printers 0.5.0 asks for administrator rights.", "consent: the privileged line");
        assertEqual(first.reasons[0].detail, "For: Add and remove printers. Programs: lpadmin. 1.2.0 did not ask.",
                    "consent: what for, which programs, the running version did not ask");

        const morePrograms = Object.assign({}, printers, { privileged: { why: "Printers", programs: ["lpadmin", "nft"] } });
        const already = ModuleUpdateRules.consentFor(_acknowledgement({ privileged: true }), _weatherRecord(), morePrograms, _address, {
            dependencyPlan: _cleanPlan,
            currentManifest: _manifest({ id: "printers", version: "0.4.0", privileged: { why: "Printers", programs: ["lpadmin"] } })
        });
        assertEqual(already.needed, false, "consent: a program added to an approved declaration needs none (§10, 4)");
        assertEqual(already.after.map(note => note.line).join("|"), "Now also runs nft as administrator", "consent: it is shown after");

        const less = ModuleUpdateRules.consentFor(_acknowledgement({ privileged: true }), _weatherRecord(), _manifest(), _address,
                                                  { dependencyPlan: _cleanPlan });
        assertEqual(less.needed, false, "consent: a version that declares less never asks");

        const shownAfter = ModuleUpdateRules.consentFor(_acknowledgement(), _weatherRecord(),
                                                        _manifest({ version: "2.0.0", programs: ["curl"] }), _address,
                                                        { dependencyPlan: _cleanPlan, currentManifest: _manifest({ version: "1.2.0" }),
                                                          found: { curl: true } });
        assertEqual(shownAfter.needed, false, "consent: new programs and a major version need none");
        assertEqual(shownAfter.after.map(note => note.line).join("|"), "Needs the program curl — found|Now 2.0: a major version",
                    "consent: they come back as notes for after");
    }

    function _consentChain() {
        // A real chain: Notes 0.4.0 newly uses Clipboard, which is not installed
        const notes = { id: "notes", name: "Notes", version: "0.4.0", api: "1.36", exports: null, author: "Anna",
                        uses: [{ id: "clipboard", version: "0.2", optional: false, source: "file:///r/clipboard" }] };
        const clipboard = { id: "clipboard", name: "Clipboard", version: "0.2.0", api: "1.36", exports: { version: "0.2" }, uses: [] };
        const plan = ModuleDependencyRules.plan(notes, { notes: { id: "notes", name: "Notes", version: "0.3.0", api: "1.36", uses: [] } },
                                                { clipboard: clipboard }, { shellApi: "1.36" });
        const newModule = ModuleUpdateRules.consentFor(_acknowledgement(), _weatherRecord(), notes, _address, { dependencyPlan: plan });
        assertEqual(_kinds(newModule), "newModule", "consent chain: a module not installed yet needs approval");
        assertEqual(newModule.reasons[0].line, "Notes 0.4.0 needs Clipboard, which is not installed.", "consent chain: the line");

        const breaking = Object.assign({}, _cleanPlan, {
            entries: [{ id: "tailscale", name: "Tailscale", kind: "update", to: "2.0.0", breaks: ["exitmap"] }],
            rootBreaks: ["clock"], blocking: ["Needs Calendar 1.0 — not installed, no address given"]
        });
        const stops = ModuleUpdateRules.consentFor(_acknowledgement(), _weatherRecord(), _manifest(), _address,
                                                   { dependencyPlan: breaking, names: { exitmap: "Exit map" } });
        assertEqual(_kinds(stops), "breaks,breaks,unresolved", "consent chain: a dependent stopped, twice, and an unresolved one");
        assertEqual(stops.reasons[0].line, "Tailscale 2.0.0 would stop Exit map.", "consent chain: the provider's new major names who stops");
        assertEqual(stops.reasons[1].line, "Weather 1.3.0 would stop clock.", "consent chain: the root's own, a name not known shown as its id");
        assertEqual(stops.reasons[2].line, "Needs Calendar 1.0 — not installed, no address given.", "consent chain: the unresolved line");

        const refusedChain = ModuleUpdateRules.consentFor(_acknowledgement(), _weatherRecord(), _manifest(), _address,
                                                          { dependencyPlan: Object.assign({}, _cleanPlan, { refused: "uses form a cycle: a → b → a" }) });
        assertEqual(_kinds(refusedChain), "chain", "consent chain: a refused chain needs approval, never passes");
        const incomplete = ModuleUpdateRules.consentFor(_acknowledgement(), _weatherRecord(), _manifest(), _address,
                                                        { dependencyPlan: Object.assign({}, _cleanPlan, { complete: false }) });
        assertEqual(_kinds(incomplete), "unknown", "consent chain: a chain still downloading is unknown");
        const noPlan = ModuleUpdateRules.consentFor(_acknowledgement(), _weatherRecord(), _manifest(), _address, {});
        assertEqual(_kinds(noPlan), "unknown", "consent chain: no plan is unknown, never fine");
    }

    function _consentMalformed() {
        const noAck = ModuleUpdateRules.consentFor(null, _weatherRecord(), _manifest(), _address, { dependencyPlan: _cleanPlan });
        assert(noAck.needed && _kinds(noAck) === "unknown", "consent malformed: an unreadable acknowledgement asks");
        const noRecord = ModuleUpdateRules.consentFor(_acknowledgement(), { kind: "elsewhere" }, _manifest(), _address,
                                                      { dependencyPlan: _cleanPlan });
        assert(noRecord.needed && _kinds(noRecord) === "unknown", "consent malformed: an unreadable record asks");
        const noManifest = ModuleUpdateRules.consentFor(_acknowledgement(), _weatherRecord(), "weather", _address, { dependencyPlan: _cleanPlan });
        assert(noManifest.needed && noManifest.reasons[0].kind === "unknown", "consent malformed: an unreadable manifest asks");
        const badAddress = ModuleUpdateRules.consentFor(_acknowledgement(), _weatherRecord(), _manifest(), "ext::sh -c id",
                                                        { dependencyPlan: _cleanPlan });
        assertEqual(_kinds(badAddress), "source", "consent malformed: an unusable address is another source");
        assertEqual(badAddress.reasons[0].detail, "From an unusable address, was codeberg.org/anna/weather",
                    "consent malformed: the unusable address is not shown");
        const injected = ModuleUpdateRules.consentFor(_acknowledgement(), _weatherRecord(), _manifest({ name: "<b>Bold</b>\nline" }),
                                                      _address, { dependencyPlan: Object.assign({}, _cleanPlan, { refused: "x" }) });
        assertEqual(injected.reasons[0].line, "<b>Bold</b> line 1.3.0: x.", "consent malformed: a name stays plain text on one line");
    }

    function _afterNotes() {
        const old = { version: "1.4.0", programs: ["git"], optionalPrograms: [], uses: [{ id: "base", version: "1.0" }] };
        const fresh = { version: "1.5.0", programs: ["git", "curl", "jq"], optionalPrograms: ["notify-send"],
                        uses: [{ id: "base", version: "1.0" }, { id: "clipboard", version: "0.2" }, { id: "calendar", version: "1.0", optional: true }] };
        const notes = ModuleUpdateRules.afterNotes(old, fresh, { found: { curl: true, jq: false }, names: { clipboard: "Clipboard" } });
        assertEqual(notes.map(note => note.line).join("|"),
                    "Needs the program curl — found|Needs the program jq — missing|Can use the program notify-send"
                    + "|Now uses Clipboard|Now can use calendar", "after: new programs with their verdict, new uses");
        assertEqual(notes.some(note => note.kind === "major"), false, "after: a minor version is no major note");

        const unread = ModuleUpdateRules.afterNotes(null, { version: "1.0.0", programs: ["curl"], uses: [] }, {});
        assertEqual(unread.map(note => note.line).join("|"), "Needs the program curl", "after: an unreadable old manifest tells everything");
        assertEqual(ModuleUpdateRules.afterNotes({}, null, {}).length, 0, "after: no new manifest, nothing to tell");

        const many = { version: "1.0.0", programs: Array.from({ length: 20 }, (unused, i) => "tool" + i), uses: [] };
        const capped = ModuleUpdateRules.afterNotes({ version: "1.0.0" }, many, {});
        assertEqual(capped.length, ModuleUpdateRules.maxAfterNotes, "after: capped");
        assertEqual(capped[capped.length - 1].line, "And 9 more", "after: the rest counted in one line");
    }

    // Three modules as one queue: Notes uses Weather (updated before it), Printers needs
    // approval and waits; one restart offer and one notification once the queue has ended
    function _queueOfThree() {
        const added = ModuleUpdateRules.queueStep(null, { type: "add", items: [
            { id: "notes", name: "Notes", from: "0.3.0", to: "0.4.0", uses: [{ id: "weather", version: "1.3" }] },
            { id: "printers", name: "Printers", from: "0.4.0", to: "0.5.0", uses: [] },
            { id: "weather", name: "Weather", from: "1.2.0", to: "1.3.0", uses: [] }
        ] });
        assertEqual(added.actions.map(action => action.action + ":" + action.id).join(","),
                    "download:notes,download:printers,download:weather", "queue: downloads side by side");
        assertEqual(added.queue.rows.map(row => row.id).join(","), "weather,notes,printers", "queue: providers before their dependents");
        assertEqual(added.summary.title + " " + added.summary.count, "Updating 0 of 3", "queue: the title line");

        let step = ModuleUpdateRules.queueStep(added.queue, { type: "progress", id: "weather",
                                                              progress: ModuleInstallRules.progressOf("Receiving objects:  45% (120/266), 1.20 MiB | 2.40 MiB/s") });
        assertEqual(ModuleUpdateRules.rowText(step.queue.rows[0]), "Weather 1.2.0 → 1.3.0 — Downloading 45% · 2.4 MiB/s",
                    "queue: a downloading row with its percent and speed");
        assertEqual(added.queue.rows[0].progress, null, "queue: the caller's queue is not changed");

        step = ModuleUpdateRules.queueStep(step.queue, { type: "downloaded", id: "notes" });
        assertEqual(step.actions.map(action => action.action).join(","), "verify", "queue: downloaded → verify");
        step = ModuleUpdateRules.queueStep(step.queue, { type: "verified", id: "notes", to: "0.4.0", commit: _commitB,
                                                         uses: [{ id: "weather", version: "1.3" }], consent: { needed: false, reasons: [] } });
        assertEqual(step.actions.length, 0, "queue: Notes waits for Weather, still downloading");
        assertEqual(ModuleUpdateRules.rowText(step.queue.rows[1]), "Notes 0.3.0 → 0.4.0 — Waiting", "queue: the waiting row");

        step = ModuleUpdateRules.queueStep(step.queue, { type: "downloaded", id: "weather" });
        step = ModuleUpdateRules.queueStep(step.queue, { type: "verified", id: "weather", to: "1.3.0", commit: _commitC, uses: [],
                                                         consent: { needed: false, reasons: [] } });
        assertEqual(JSON.stringify(step.actions), JSON.stringify([{ action: "switch", id: "weather", subject: { id: "weather", to: "1.3.0", commit: _commitC } }]),
                    "queue: Weather switches first, with its subject");

        step = ModuleUpdateRules.queueStep(step.queue, { type: "downloaded", id: "printers" });
        step = ModuleUpdateRules.queueStep(step.queue, { type: "verified", id: "printers", to: "0.5.0", commit: _commitD, uses: [],
                                                         consent: { needed: true, reasons: [{ kind: "privileged", line: "Printers 0.5.0 asks for administrator rights." }] } });
        assertEqual(ModuleUpdateRules.rowText(step.queue.rows[2]), "Printers 0.4.0 → 0.5.0 — Approval required", "queue: a row waits for approval");
        assertEqual(step.actions.length, 0, "queue: one switch at a time");

        step = ModuleUpdateRules.queueStep(step.queue, { type: "backedUp", id: "weather" });
        assertEqual(ModuleUpdateRules.rowText(step.queue.rows[0]), "Weather 1.2.0 → 1.3.0 — Installing", "queue: backed up → installing");
        step = ModuleUpdateRules.queueStep(step.queue, { type: "installed", id: "weather", restart: true });
        assertEqual(step.actions.map(action => action.action + ":" + action.id).join(","), "switch:notes", "queue: then Notes");
        assertEqual(step.offer, null, "queue: no restart offered while the queue runs");
        step = ModuleUpdateRules.queueStep(step.queue, { type: "backedUp", id: "notes" });
        step = ModuleUpdateRules.queueStep(step.queue, { type: "installed", id: "notes", restart: true });
        assertEqual(step.summary.title + " " + step.summary.count, "Updates finished 3 of 3", "queue: ended, the approval row counted");
        assertEqual(JSON.stringify(step.offer), JSON.stringify({ text: "Restart the shell to load the new files of Weather and Notes.", ids: ["weather", "notes"] }),
                    "queue: one restart offer for both");
        assertEqual(step.notification.title, "Restart needed", "queue: the notification merged with the restart");
        assertEqual(step.notification.body, "Modules updated: Weather 1.3.0, Notes 0.4.0. Printers: approval required. "
                    + "Restart the shell to finish updating Weather and Notes.", "queue: one notification, every module in it");
        assertEqual(step.notification.opens, "restart", "queue: it leads to the restart button");

        const late = ModuleUpdateRules.queueStep(step.queue, { type: "approved", id: "printers", to: "0.4.9", commit: _commitD });
        assert(late.ignored && late.actions.length === 0, "queue: an answer about another version is ignored");
        const lateCommit = ModuleUpdateRules.queueStep(step.queue, { type: "approved", id: "printers", to: "0.5.0", commit: _commitE });
        assert(lateCommit.ignored, "queue: an answer about another commit is ignored");

        step = ModuleUpdateRules.queueStep(step.queue, { type: "approved", id: "printers", to: "0.5.0", commit: _commitD });
        assertEqual(step.actions.map(action => action.action + ":" + action.id).join(","), "switch:printers", "queue: approved later, it switches");
        assertEqual(step.summary.title, "Updating", "queue: running again");
        step = ModuleUpdateRules.queueStep(step.queue, { type: "backedUp", id: "printers" });
        step = ModuleUpdateRules.queueStep(step.queue, { type: "installed", id: "printers", restart: false });
        assertEqual(step.offer, null, "queue: no restart offered again for what was offered");
        assertEqual(step.notification.body, "Modules updated: Printers 0.5.0.", "queue: only the newly finished one is told");
        assertEqual(step.notification.opens + " " + step.notification.ids.join(","), "changelog printers", "queue: it opens the changelog");

        const again = ModuleUpdateRules.queueStep(added.queue, { type: "add", items: [{ id: "weather", name: "Weather" }] });
        assert(again.ignored, "queue: a module already queued is not queued twice");
    }

    function _queueRefusal() {
        let step = ModuleUpdateRules.queueStep(ModuleUpdateRules.emptyQueue(), { type: "add", items: [
            { id: "printers", name: "Printers", from: "0.4.0", to: "0.5.0", commit: _commitD, staged: true, uses: [],
              consent: { needed: true, reasons: [{ kind: "privileged", line: "asks" }] } }
        ] });
        assertEqual(step.queue.rows[0].phase, "approval", "refusal: a staged item goes straight to approval");
        step = ModuleUpdateRules.queueStep(step.queue, { type: "refused", id: "printers", to: "0.5.0", commit: _commitD.slice(0, 7) });
        assertEqual(JSON.stringify(step.actions), JSON.stringify([{ action: "rememberRefusal", id: "printers", version: "0.5.0", commit: _commitD }]),
                    "refusal: remembered with its version and commit (a short commit id matches)");
        assertEqual(ModuleUpdateRules.rowText(step.queue.rows[0]), "Printers 0.4.0 → 0.5.0 — Not finished", "refusal: the row");
        assertEqual(step.notification.body, "Printers: not finished.", "refusal: told once, in the notification");
        const twice = ModuleUpdateRules.queueStep(step.queue, { type: "refused", id: "printers", to: "0.5.0", commit: _commitD });
        assert(twice.ignored && twice.notification === null, "refusal: a second answer changes nothing");

        // The record keeps the refusal: that version is not offered again, a newer one is
        const record = _record([_version("0.4.0-aaaaaaa", "0.4.0", _commitA, 1), _version("0.5.0-ddddddd", "0.5.0", _commitD, 2)],
                               "0.4.0-aaaaaaa", { version: "0.5.0", commit: _commitD });
        assertEqual(ModuleUpdateRules.offerFor(record, { version: "0.5.0", commit: _commitD }).reason, "refused", "refusal: not offered again");
        const newer = ModuleUpdateRules.offerFor(record, { version: "0.5.1", commit: _commitE });
        assert(newer.offer && newer.reason === "available", "refusal: a newer version is offered");
    }

    function _queueFailures() {
        const staged = (id, name, uses) => ({ id: id, name: name, from: "1.0.0", to: "1.1.0", commit: _commitB, staged: true, uses: uses,
                                              consent: { needed: false, reasons: [] } });
        let step = ModuleUpdateRules.queueStep(null, { type: "add", items: [staged("notes", "Notes", [{ id: "weather", version: "1.1" }]),
                                                                           staged("weather", "Weather", [])] });
        assertEqual(step.actions.map(action => action.action + ":" + action.id).join(","), "switch:weather", "failures: staged items switch at once, provider first");
        step = ModuleUpdateRules.queueStep(step.queue, { type: "failed", id: "weather", reason: "1.1.0 failed to start; 1.0.0 is active again" });
        assertEqual(ModuleUpdateRules.rowText(step.queue.rows[0]), "Weather 1.0.0 → 1.1.0 — Failed: 1.1.0 failed to start; 1.0.0 is active again",
                    "failures: the row says what and why");
        assertEqual(ModuleUpdateRules.rowText(step.queue.rows[1]), "Notes 1.0.0 → 1.1.0 — Failed: needs Weather, which was not updated",
                    "failures: the dependent does not switch without its provider");
        assertEqual(step.notification.title + " / " + step.notification.body, "Module updates / Weather: failed. Notes: failed.",
                    "failures: the notification");

        const cycle = ModuleUpdateRules.queueStep(null, { type: "add", items: [staged("alpha", "Alpha", [{ id: "beta", version: "1.0" }]),
                                                                             staged("beta", "Beta", [{ id: "alpha", version: "1.0" }])] });
        assert(cycle.queue.rows.every(row => row.phase === "failed" && row.reason === "its uses form a cycle in the queue"),
               "failures: rows waiting on each other fail instead of waiting for ever");

        const unread = ModuleUpdateRules.queueStep(null, { type: "add", items: [staged("weather", "Weather", "broken")] });
        assertEqual(unread.queue.rows[0].reason, "its manifest could not be read", "failures: uses that cannot be read fail the row");
        const notAnswer = ModuleUpdateRules.queueStep(null, { type: "add", items: [Object.assign(staged("weather", "Weather", []), { consent: "yes" })] });
        assertEqual(notAnswer.queue.rows[0].phase, "approval", "failures: a consent that cannot be read asks");
        const lateFailure = ModuleUpdateRules.queueStep(notAnswer.queue, { type: "failed", id: "weather", reason: "x" });
        assert(lateFailure.ignored, "failures: a failure for a row not running is ignored");
    }

    // A provider waiting for approval holds its dependent; approving it lets both go on
    function _queueHeld() {
        let step = ModuleUpdateRules.queueStep(null, { type: "add", items: [
            { id: "weather", name: "Weather", from: "1.2.0", to: "2.0.0", commit: _commitC, staged: true, uses: [],
              consent: { needed: true, reasons: [{ kind: "breaks", line: "Weather 2.0.0 would stop Notes." }] } },
            { id: "notes", name: "Notes", from: "0.3.0", to: "0.4.0", commit: _commitB, staged: true, uses: [{ id: "weather", version: "2.0" }],
              consent: { needed: false, reasons: [] } }
        ] });
        assertEqual(ModuleUpdateRules.rowText(step.queue.rows[1]), "Notes 0.3.0 → 0.4.0 — Waits for Weather", "held: the dependent waits");
        assertEqual(step.summary.title, "Updates finished", "held: a queue left waiting for answers has ended");
        assertEqual(step.notification.body, "Weather: approval required.", "held: the approval told");
        step = ModuleUpdateRules.queueStep(step.queue, { type: "approved", id: "weather", to: "2.0.0", commit: _commitC });
        assertEqual(step.actions.map(action => action.id).join(","), "weather", "held: the provider switches first");
        step = ModuleUpdateRules.queueStep(step.queue, { type: "backedUp", id: "weather" });
        step = ModuleUpdateRules.queueStep(step.queue, { type: "installed", id: "weather" });
        assertEqual(step.actions.map(action => action.action + ":" + action.id).join(","), "switch:notes", "held: then its dependent");

        const fresh = ModuleUpdateRules.queueStep(step.queue, { type: "add", items: [{ id: "radio", name: "Radio", to: "1.0.0" }] });
        assertEqual(fresh.queue.rows.map(row => row.id).join(","), "weather,notes,radio", "held: a running queue takes more rows");
    }

    function _queueMalformed() {
        const broken = ModuleUpdateRules.queueStep({ rows: "x" }, { type: "downloaded", id: "weather" });
        assert(broken.ignored && broken.queue.rows.length === 0, "queue malformed: an unreadable queue starts empty");
        const unknownEvent = ModuleUpdateRules.queueStep(null, { type: "explode", id: "weather" });
        assert(unknownEvent.ignored, "queue malformed: an unknown event is ignored");
        const badItems = ModuleUpdateRules.queueStep(null, { type: "add", items: [{ id: "../x" }, null, "weather"] });
        assert(badItems.ignored && badItems.queue.rows.length === 0, "queue malformed: items without a valid id are skipped");
        assertEqual(ModuleUpdateRules.queueSummary(null).count, "0 of 0", "queue malformed: a summary of nothing");
    }

    function _keepPlan() {
        const four = _record([_version("1.1.0-aaaaaaa", "1.1.0", _commitA, 1), _version("1.2.0-bbbbbbb", "1.2.0", _commitB, 2),
                              _version("1.3.0-ccccccc", "1.3.0", _commitC, 3), _version("1.4.0-ddddddd", "1.4.0", _commitD, 4)],
                             "1.3.0-ccccccc", { version: "1.1.0", commit: _commitA });
        const plan = ModuleUpdateRules.keepPlan(four, { previousDir: "1.2.0-bbbbbbb" });
        assertEqual(plan.keep.join(","), "1.3.0-ccccccc,1.1.0-aaaaaaa,1.2.0-bbbbbbb", "keep: the active, the refused, the previous");
        assertEqual(plan.delete.join(","), "1.4.0-ddddddd", "keep: at most three, a newer download goes rather than the refused one");

        const noRefusal = Object.assign({}, four, { refused: null });
        const pending = ModuleUpdateRules.keepPlan(noRefusal, { previousDir: "1.2.0-bbbbbbb", pendingDir: "1.4.0-ddddddd" });
        assertEqual(pending.delete.join(","), "1.1.0-aaaaaaa", "keep: with a waiting download, the oldest goes");
        const newest = ModuleUpdateRules.keepPlan(noRefusal, {});
        assertEqual(newest.keep.join(","), "1.3.0-ccccccc,1.4.0-ddddddd,1.2.0-bbbbbbb", "keep: without hints, the newest fetched");

        const byVersion = Object.assign({}, four, { refused: { version: "1.4.0", commit: "" } });
        assert(ModuleUpdateRules.keepPlan(byVersion, {}).keep.includes("1.4.0-ddddddd"), "keep: a refusal without a commit holds by version");
        const broken = ModuleUpdateRules.keepPlan(Object.assign({}, four, { active: "gone" }), {});
        assert(!broken.ok && broken.delete.length === 0, "keep: a record that cannot be read deletes nothing");
        assertEqual(ModuleUpdateRules.keepPlan(_weatherRecord(), {}).delete.length, 0, "keep: one version, nothing to delete");
    }

    function _versionList() {
        const record = _record([_version("0.5.2-aaaaaaa", "0.5.2", _commitA, 1), _version("0.6.0-bbbbbbb", "0.6.0", _commitB, 2),
                                _version("0.7.0-ccccccc", "0.7.0", _commitC, 3)], "0.6.0-bbbbbbb");
        const hex = i => i.toString(16).padStart(40, "0");
        const tags = Array.from({ length: 12 }, (unused, i) => ({ name: "v0." + (i + 1) + ".0", commit: hex(i + 1) }));
        tags.push({ name: "nightly", commit: hex(99), date: "2026-11-01T00:00:00Z" });
        tags.push({ name: "v0.6.0", commit: _commitB });           // the active one: not repeated
        tags.push({ name: "-x", commit: hex(98) });                // no tag name: left out
        const list = ModuleUpdateRules.versionList(record, tags, { branch: "main", commit: "1a2b3c4" + "0".repeat(33) });
        assertEqual(list.kept.map(entry => entry.label).join("|"), "0.7.0 — downloaded|0.6.0 — active|0.5.2 — kept · older",
                    "versions list: the kept ones, newest first, the older one marked");
        assertEqual(list.tags.length, ModuleUpdateRules.maxListedTags, "versions list: the ten newest tags");
        assertEqual(list.tags[0].label + " " + list.tags[0].ref, "v0.12.0 v0.12.0", "versions list: newest by version order, not text");
        assertEqual(list.more, 3, "versions list: the rest behind More…");
        assertEqual(list.head.label, "main — latest commit 1a2b3c4", "versions list: the branch head");
        assert(list.tags.some(entry => entry.older) && !list.tags[0].older, "versions list: tags before the active version are older");

        const refused = Object.assign({}, record, { refused: { version: "0.7.0", commit: _commitC } });
        assertEqual(ModuleUpdateRules.versionList(refused, [], null).kept[0].label, "0.7.0 — not finished", "versions list: the refused one");
        const fewTags = ModuleUpdateRules.versionList(record, [{ name: "nightly", commit: hex(5), date: 2 }, { name: "v9.0.0", commit: hex(6) },
                                                               { name: "older", commit: hex(7), date: 1 }], { branch: "main", commit: _commitB });
        assertEqual(fewTags.tags.map(entry => entry.label).join(","), "v9.0.0,nightly,older", "versions list: semver first, then by date");
        assertEqual(fewTags.head, null, "versions list: a head already kept is not repeated");
        assert(!ModuleUpdateRules.versionList({}, tags, null).ok, "versions list: a record that cannot be read lists nothing");
    }

    function _changelog() {
        const text = "# Changelog\n\n## Unreleased\n- wip\n\n## [1.3.0] - 2026-11-01\n- three\n\n## 1.2.1\n- two one\n\n## 1.2.0\n- two\n\n## 1.1.0\n- one\n";
        assertEqual(ModuleUpdateRules.changelogSince(text, "1.2.0", "1.3.0").text, "## [1.3.0] - 2026-11-01\n- three\n\n## 1.2.1\n- two one",
                    "changelog: the sections after the installed version up to the new one");
        const install = ModuleUpdateRules.changelogSince(text, "", "1.3.0").text;
        assert(install.startsWith("## [1.3.0]") && install.includes("## 1.2.0") && !install.includes("1.1.0"), "changelog: an install shows the newest few");
        const sameVersion = ModuleUpdateRules.changelogSince(text, "1.3.0", "1.3.0");
        assert(sameVersion.text.startsWith("# Changelog") && !sameVersion.none, "changelog: the same version from a new commit shows the text's start");
        assertEqual(ModuleUpdateRules.changelogSince("Just words\n", "1.0.0", "1.1.0").text, "Just words", "changelog: no headings, the text");

        const long = Array.from({ length: 300 }, (unused, i) => "line " + i).join("\n");
        const byLines = ModuleUpdateRules.changelogSince(long, "1.0.0", "1.1.0");
        assert(byLines.cut && byLines.text.endsWith("line 199\n(cut)"), "changelog: over its lines, cut at 200");
        const wide = "## 1.1.0\n" + "x".repeat(30000);
        const byCharacters = ModuleUpdateRules.changelogSince(wide, "1.0.0", "1.1.0");
        assertEqual(byCharacters.text.length, ModuleUpdateRules.maxChangelogCharacters + "\n(cut)".length, "changelog: over its characters, cut at 20 000");
        const huge = "x".repeat(70000) + "\n## 2.0.0\n- far away";
        assert(!ModuleUpdateRules.changelogSince(huge, "1.0.0", "2.0.0").text.includes("far away"), "changelog: only the first 64 KiB is read");

        const plain = ModuleUpdateRules.changelogSince("## 1.1.0\n- <b>bold</b>\t‮evil\u0007\r\n- next", "1.0.0", "1.1.0");
        assertEqual(plain.text, "## 1.1.0\n- <b>bold</b>    evil\n- next", "changelog: plain text, controls gone, line breaks kept");
        assert(ModuleUpdateRules.changelogSince("", "1.0.0", "1.1.0").none, "changelog: empty is none");
        assertEqual(ModuleUpdateRules.changelogSince(null, "1.0.0", "1.1.0").text, "No changelog", "changelog: none says so");
    }

    function _offer() {
        const record = _record([_version("1.2.0-aaaaaaa", "1.2.0", _commitA, 1), _version("1.3.0-bbbbbbb", "1.3.0", _commitB, 2)],
                               "1.2.0-aaaaaaa");
        assertEqual(ModuleUpdateRules.offerFor(record, { version: "1.2.0", commit: _commitA.slice(0, 7) }).reason, "current",
                    "offer: the active commit is current");
        const sameVersion = ModuleUpdateRules.offerFor(record, { version: "1.2.0", commit: _commitE });
        assert(sameVersion.offer && sameVersion.sameVersion, "offer: the same version from a new commit is offered");
        const downloaded = ModuleUpdateRules.offerFor(record, { version: "1.3.0", commit: _commitB });
        assertEqual(downloaded.downloadedDir, "1.3.0-bbbbbbb", "offer: a version already kept is named");
        assertEqual(ModuleUpdateRules.offerFor(record, { version: "1.1.0", commit: _commitD }).reason, "older", "offer: an older version is not offered");
        assert(ModuleUpdateRules.offerFor(record, { version: "main", commit: _commitD }).offer, "offer: a version without order, a new commit");
        assertEqual(ModuleUpdateRules.offerFor(record, { version: "1.4.0", commit: "zzz" }).reason, "unknown", "offer: a check without a commit is unknown");
        assertEqual(ModuleUpdateRules.offerFor(record, { ok: false }).offer, false, "offer: a failed check offers nothing");
        assertEqual(ModuleUpdateRules.offerFor(null, { version: "1.4.0", commit: _commitD }).reason, "unknown", "offer: no record, nothing offered");
    }

    function _autoRun() {
        const hour = 60 * 60 * 1000;
        const day = 24 * hour;
        const start = Date.UTC(2026, 10, 21, 8, 0, 0);
        const due = (state, now) => ModuleUpdateRules.autoRunDue(Object.assign({ enabled: true, locked: false }, state), now);
        assertEqual(due({ enabled: false }, start).reason, "off", "auto: off by default");
        assertEqual(due({ locked: true }, start).due, false, "auto: not while locked");
        assertEqual(due({ locked: undefined }, start).reason, "locked", "auto: a lock state not known counts as locked");
        assertEqual(due({}, start).reason, "first", "auto: never ran, due");
        assertEqual(due({ lastAttemptAt: start, failures: 0 }, start + 23 * hour).due, false, "auto: not again within the day");
        assertEqual(due({ lastAttemptAt: start, failures: 0 }, start + day).reason, "daily", "auto: due after a day");

        // A failed check backs off: 15 min, 30 min, 1 h … never later than a day
        const failedOnce = due({ lastAttemptAt: start, failures: 1 }, start + 14 * 60 * 1000);
        assertEqual(failedOnce.nextAt - start, 15 * 60 * 1000, "auto: after one failure, again in 15 min");
        assertEqual(failedOnce.due, false, "auto: not before");
        assertEqual(due({ lastAttemptAt: start, failures: 3 }, start + hour).reason, "retry", "auto: after three, in an hour");
        assertEqual(due({ lastAttemptAt: start, failures: 3 }, start + hour - 1).due, false, "auto: not a moment before");
        assertEqual(due({ lastAttemptAt: start, failures: 40 }, start).nextAt - start, day, "auto: the backoff stops at a day");

        assertEqual(due({ lastAttemptAt: start + day }, start).reason, "unknown", "auto: a last run in the future is unknown, due");
        assertEqual(due({ lastAttemptAt: "yesterday" }, start).due, true, "auto: an unreadable last run is due, never 'checked'");
        assertEqual(due({}, NaN).due, false, "auto: no clock, not due");

        let record = ModuleUpdateRules.autoRunRecord({ enabled: true, locked: false }, "failed", start);
        assert(record.log && record.state.failures === 1 && record.state.lastAttemptAt === start, "auto: a first failure logged and counted");
        record = ModuleUpdateRules.autoRunRecord(record.state, "failed", start + hour);
        assert(!record.log && record.state.failures === 2, "auto: the same outcome again is not logged");
        record = ModuleUpdateRules.autoRunRecord(record.state, "ok", start + 2 * hour);
        assert(record.log && record.state.failures === 0, "auto: success after failures logged, the count reset");
    }

    function _backupPlan() {
        const options = { dataHome: "/home/u/.local/share", configHome: "/home/u/.config", version: "1.2.0", commit: _commitA,
                          reason: "update", nowMs: Date.UTC(2026, 10, 21, 14, 2, 0) };
        const manifest = { backup: ["notes.db", "cache/../../../etc/passwd", "/etc/passwd", "../x", "sub/./keep.json", "", ".", 42, "notes.db"] };
        const plan = ModuleUpdateRules.backupPlan("weather", manifest, options);
        assert(plan.ok, "backup: planned");
        assertEqual(plan.directory, "/home/u/.local/share/h2s-shell/module-backups/weather/1.2.0-20261121-140200",
                    "backup: named by version and time");
        assertEqual(plan.staging, "/home/u/.local/share/h2s-shell/module-backups/weather/.incoming-1.2.0-20261121-140200",
                    "backup: written beside it, then renamed in");
        assertEqual(JSON.stringify(plan.items), JSON.stringify([
            { what: "settings", prefix: "mod.weather." },
            { what: "store", from: "/home/u/.config/h2s_shell/modules/weather", to: "store" },
            { what: "data", from: "/home/u/.local/share/h2s-shell/module-data/weather/notes.db", to: "data/notes.db" },
            { what: "data", from: "/home/u/.local/share/h2s-shell/module-data/weather/sub/keep.json", to: "data/sub/keep.json" }
        ]), "backup: settings, store, and only the named files inside the data directory");
        assertEqual(plan.skipped.map(each => each.why).join(","),
                    "outside its data directory,outside its data directory,outside its data directory,not a path,the whole data directory,not a path",
                    "backup: paths outside the data directory, and the whole of it, are refused");
        assertEqual(JSON.stringify(plan.meta), JSON.stringify({ id: "weather", version: "1.2.0", commit: _commitA, takenAt: options.nowMs,
                                                               reason: "update", includesData: true }), "backup: meta.json");

        const without = ModuleUpdateRules.backupPlan("weather", {}, options);
        assert(without.items.length === 2 && without.meta.includesData === false, "backup: no named files, the data directory never");
        const notList = ModuleUpdateRules.backupPlan("weather", { backup: "notes.db" }, options);
        assert(notList.items.length === 2 && notList.skipped[0].why === "not a list of paths", "backup: a named path that is no list adds nothing");
        const many = ModuleUpdateRules.backupPlan("weather", { backup: Array.from({ length: 40 }, (unused, i) => "file" + i) }, options);
        assertEqual(many.items.length - 2 + "/" + many.skipped.length, "32/8", "backup: named paths capped");
        assertEqual(ModuleUpdateRules.backupPlan("weather", {}, Object.assign({}, options, { version: "../1" })).name,
                    "unknown-20261121-140200", "backup: a version that is no directory name is not used as one");

        assert(!ModuleUpdateRules.backupPlan("../weather", {}, options).ok, "backup: not a module id");
        assert(!ModuleUpdateRules.backupPlan("weather", {}, Object.assign({}, options, { reason: "whim" })).ok, "backup: a reason is needed");
        assert(!ModuleUpdateRules.backupPlan("weather", {}, Object.assign({}, options, { dataHome: "relative" })).ok, "backup: homes must be absolute");
        assert(!ModuleUpdateRules.backupPlan("weather", {}, Object.assign({}, options, { nowMs: undefined })).ok, "backup: a time is needed");
    }

    function _backupKeepPlan() {
        const entries = ["1.0.0-20261101-100000", "1.0.0-20261102-100000", "1.1.0-20261103-100000", "1.1.0-20261104-100000",
                         "1.2.0-20261105-100000", "1.2.0-20261106-100000"].map(dir => ({ dir: dir }));
        entries.push({ dir: "1.3.0-20261001-100000", takenAt: Date.UTC(2026, 10, 20) });   // meta.json's time counts first
        entries.push({ dir: "broken" });
        entries.push({ dir: "../outside" });
        const plan = ModuleUpdateRules.backupKeepPlan(entries);
        assertEqual(plan.keep.join(","), "1.3.0-20261001-100000,1.2.0-20261106-100000,1.2.0-20261105-100000,1.1.0-20261104-100000,1.1.0-20261103-100000",
                    "backup keep: the newest five");
        assertEqual(plan.delete.join(","), "1.0.0-20261102-100000,1.0.0-20261101-100000", "backup keep: the older ones go");
        assertEqual(plan.unknown.join(","), "broken,../outside", "backup keep: unreadable ones are left alone, never deleted");
        assertEqual(ModuleUpdateRules.backupKeepPlan(null).delete.length, 0, "backup keep: no list, nothing deleted");
    }
}
