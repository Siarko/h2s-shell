import QtQuick
import Quickshell
import qs.singletons.io

// The module updater (notes/plans/modules-management.md §6.3–§6.5): checks the modules the
// shell installed from a repository for a newer version, downloads it in the background,
// and switches through one queue — by hand ("Update", "Update all", `modules update`) or,
// with modules.autoUpdate "automatic", by the daily run. No views: Settings → Modules and
// `qs ipc call modules check|update|approve|refuse|…` (Modules.qml) call it.
//
// A check is `git ls-remote` of the recorded address (ModuleUpdateRules.checkCommand: the
// installer's git options and environment, the address after "--"), read by
// ModuleUpdateRules.parseLsRemote and checkFound and judged by offerFor: a version the user
// refused is never offered again (a newer one is). A check by hand downloads what it finds
// beside the kept versions (ModuleInstaller.fetchUpdate) — nothing changes until "Update".
//
// The queue is ModuleUpdateRules.queueStep's state machine; this carries out its actions one
// at a time through the installer (download, then the host's check of the new version and
// ModuleUpdateRules.consentFor, then the switch — ModuleInstaller.switchVersion, which goes
// back to the version before when the new one does not start), and feeds it their answers,
// each keyed to the row's run token: an answer from an earlier run, or after cancel(), is
// ignored. A row that needs consent waits at "Approval required" (approve() / refuse(),
// keyed to the version directory asked about); a refusal is remembered in the record. When
// the whole queue has ended: one notification (the updated modules, what waits for approval,
// the restart — clicking it asks to open Settings → Modules, `openRequested`), and one
// restart offer for the modules whose new files only a restart loads (`restartOffer`,
// `restartNeeded`: in memory, so a restart clears it by being the restart). The restart
// reminder carries the hint `x-h2s-restart-for` (this process, `restartToken`); at start any
// reminder another process left is closed.
//
// The daily run (ModuleUpdateRules.autoRunDue, autoRunRecord): once a day, not while
// locked, sooner after a failure with a backoff, logged on a change of outcome only. Nothing
// here prompts, and nothing acts while the session is locked: the queue's actions wait for
// the unlock, and checks and updates by hand are refused then.
Scope {
    id: root

    property var host: null
    property var installer: null
    // Where notifications go (Notifier: send(summary, options) → a progress handle with
    // update() and close()), and the server whose notifications are looked through at start
    // (Notifications: notifications.values, each with hints and dismiss()); the suites give
    // stand-ins
    property var notifier: Notifier
    property var notificationServer: Notifications
    // The clock (the suites' a fake one)
    property var now: function () {
        return Date.now();
    }
    // modules.autoUpdate is "automatic"
    property bool automatic: false
    // The daily run's remembered state (Config.moduleUpdates read: { lastAttemptAt, failures,
    // lastOutcome }) — nothing runs by itself before it is known
    property var autoState: ({})
    property bool autoStateKnown: false
    // The run's new state, to be remembered
    signal autoStateWritten(var state)
    // How often whether the daily run is due is asked
    property int autoCheckIntervalMs: 5 * 60 * 1000
    // One check's time limit
    property int checkTimeoutMs: 30000
    // This process (ModuleUpdateRules.restartToken), for the restart reminder
    property string restartToken: ""

    // What the last checks found, by id: { outcome "current" | "available" | "failed",
    // checkedAt, version, commit, ref, reason, refused, downloading, downloadedDir }
    property var checks: ({})
    // A check runs: which one of how many ("Checking 2 of 4…")
    property bool checking: false
    property int checkingIndex: 0
    property int checkingTotal: 0
    // The queue (ModuleUpdateRules.queueStep's) and its title line
    property var queue: ModuleUpdateRules.emptyQueue()
    readonly property var queueSummary: ModuleUpdateRules.queueSummary(queue)
    // The one "Restart shell" offer once a queue ended ({ text, ids }), null after "Later"
    property var restartOffer: null
    // The names of the modules updated whose new files only a restart loads (until it)
    property var restartNeeded: []
    // What's new, by id: { name, from, to, text, cut, none } (ModuleUpdateRules.changelogSince)
    property var changelogs: ({})
    // What changed besides, by id (ModuleUpdateRules.afterNotes' lines: "New in this version")
    property var afterNotes: ({})
    // Why a row waits for approval, by id: consentFor's reasons ({ kind, line, detail }) and the
    // version directory the answer must name
    property var approvals: ({})
    // The last request to open Settings → Modules (a notification clicked): { page, show
    // "changelog" | "restart", ids } — the page (M5) shows the changelogs or the offer
    property var openRequest: null
    signal openRequested(var request)

    // ---- Internals ----

    property int _generation: 0
    property var _info: ({})        // id → what the last check found: { dir, ref, commit, version, record }
    // id → what its row of the queue works on, for that row's run only: { run, ref, dir (the
    // download), verifiedDir (the one the host checked and consentFor judged — the only one a
    // switch or an approval takes), manifest, record, ackWritten, ackPrevious, restartBefore }
    property var _rowData: ({})
    property var _failedCommits: ({})   // id → the commit whose update last failed (not re-tried by the daily run)
    property var _announced: []         // what a notification already told, by row ("phase|id|commit|reason")
    property var _offeredIds: []        // modules a restart offer named
    property var _changelogAsked: ({})  // id → the token of the newest changelog read
    property var _pending: []       // queue actions and background downloads waiting for the installer
    property var _current: null     // the action in flight: { action, id, run, job, generation, … }
    property var _autoRun: null     // the daily run in progress: { failedChecks, ids }
    property var _restartHandle: null
    property var _lastCheckOutcome: ({})

    CommandRunner {
        id: _runner
        environment: root.installer?.environment ?? {}
    }

    // ---- Checking ----

    // Checks module `id` ("" — every module the shell installed from a repository). By hand:
    // what it finds is downloaded in the background. → "" when it started, else why not
    function check(id) {
        if (!host || !installer)
            return "No module host";
        if (host.locked)
            return "Refused while the session is locked";
        if (checking)
            return "A check is running";
        if (typeof id !== "string" || (id !== "" && !ModuleManifestRules.validId(id)))
            return "Not a module id";
        _checkModules(id, false, null);
        return "";
    }

    function _checkModules(id, automatically, done) {
        const generation = _generation;
        checking = true;
        checkingIndex = 0;
        checkingTotal = 0;
        installer.readInstalled(read => {
            if (generation !== _generation) {
                done?.([]);
                return;
            }
            if (!read.ok) {
                checking = false;
                _logCheck("", "failed", "the record of installed modules cannot be read");
                done?.([{ id: "", outcome: "failed" }]);
                return;
            }
            const ids = Object.keys(read.found).filter(each => read.records.modules[each]?.kind === "repository"
                                                            && (id === "" || each === id)).sort();
            if (id !== "" && ids.length === 0) {
                checking = false;
                _setCheck(id, { outcome: "failed", checkedAt: now(), reason: "not installed by the shell from a repository" });
                done?.([{ id: id, outcome: "failed" }]);
                return;
            }
            checkingTotal = ids.length;
            const results = [];
            const next = index => {
                if (generation !== _generation) {
                    done?.(results);
                    return;
                }
                if (index >= ids.length) {
                    checking = false;
                    done?.(results);
                    return;
                }
                checkingIndex = index + 1;
                _checkOne(ids[index], read.records.modules[ids[index]], generation, automatically, outcome => {
                    results.push(outcome);
                    next(index + 1);
                });
            };
            next(0);
        });
    }

    function _checkOne(id, record, generation, automatically, done) {
        const command = ModuleUpdateRules.checkCommand(record);
        if (!command.ok) {
            _setCheck(id, { outcome: "failed", checkedAt: now(), reason: command.problem });
            Qt.callLater(() => done({ id: id, outcome: "failed" }));
            return;
        }
        let lastLine = "";
        _runner.start(command.argv, {
            environment: command.environment, timeoutMs: checkTimeoutMs, killAfterMs: 1000, maxOutputBytes: 262144,
            onLine: (line, stream) => {
                if (stream === "stderr" && line.trim() !== "")
                    lastLine = line;
            },
            done: result => {
                // Late answers lose: a cancel or a newer check came meanwhile
                if (generation !== _generation) {
                    done({ id: id, outcome: "cancelled" });
                    return;
                }
                const checkedAt = now();
                if (!result.ok) {
                    const reason = ModuleInstallRules.downloadProblem(result, lastLine, { timeoutMs: checkTimeoutMs });
                    _setCheck(id, { outcome: "failed", checkedAt: checkedAt, reason: reason });
                    done({ id: id, outcome: "failed" });
                    return;
                }
                const listing = ModuleUpdateRules.parseLsRemote(String(result.stdout ?? "").split("\n"));
                const found = ModuleUpdateRules.checkFound(record, listing);
                if (!found.ok) {
                    _setCheck(id, { outcome: "failed", checkedAt: checkedAt, reason: found.problem });
                    done({ id: id, outcome: "failed" });
                    return;
                }
                const offer = ModuleUpdateRules.offerFor(record, found);
                const available = offer.offer === true;
                // A module whose row of the queue has not ended is not downloaded again: the
                // row works on what it was queued with
                const fetchNow = available && !automatically && offer.downloadedDir === "" && !_rowBusy(id);
                if (!_rowBusy(id))
                    _info = Object.assign({}, _info, { [id]: { dir: offer.downloadedDir, ref: found.mode === "tag" ? found.ref : "",
                                                               commit: offer.commit, version: offer.version, record: record } });
                _setCheck(id, { outcome: available ? "available" : offer.reason === "unknown" ? "failed" : "current",
                                checkedAt: checkedAt, version: offer.version, commit: offer.commit, ref: found.ref,
                                reason: offer.reason === "unknown" ? "the answer could not be judged" : "",
                                refused: offer.reason === "refused",
                                downloading: fetchNow, downloadedDir: offer.downloadedDir });
                if (fetchNow)
                    _enqueue({ action: "fetch", id: id, generation: generation });
                done({ id: id, outcome: available ? "available" : "current" });
            }
        });
    }

    function _rowBusy(id) {
        const row = queue.rows.find(each => each.id === id);
        return row !== undefined && !["done", "failed", "notFinished"].includes(row.phase);
    }

    function _setCheck(id, result) {
        const entry = Object.assign({ outcome: "", checkedAt: 0, version: "", commit: "", ref: "", reason: "", refused: false,
                                      downloading: false, downloadedDir: "" }, result);
        entry.reason = ModuleInstallRules._plain(String(entry.reason ?? ""), 200);
        checks = Object.assign({}, checks, { [id]: entry });
        _logCheck(id, entry.outcome, entry.reason);
    }

    // Logged on a change of outcome only
    function _logCheck(id, outcome, reason) {
        const key = id || "*";
        if (_lastCheckOutcome[key] === outcome)
            return;
        _lastCheckOutcome = Object.assign({}, _lastCheckOutcome, { [key]: outcome });
        if (outcome === "failed")
            console.warn("[Modules] checking " + (id || "for updates") + " failed: " + reason);
        else if (outcome === "available")
            console.info("[Modules] " + id + ": " + (checks[id]?.version || "a new version") + " available");
    }

    // ---- Updating ----

    // Queues the update of module `id` that the last check found. → "" when queued
    function update(id) {
        return updateAll(typeof id === "string" ? [id] : null);
    }

    // Queues every update the last checks found (`ids`: only these). → "" when queued
    function updateAll(ids) {
        if (!host || !installer)
            return "No module host";
        if (host.locked)
            return "Refused while the session is locked";
        const wanted = Array.isArray(ids) ? ids : Object.keys(checks).filter(each => checks[each]?.outcome === "available");
        if (wanted.length === 0)
            return "No update found: check first";
        for (const each of wanted)
            if (checks[each]?.outcome !== "available")
                return "No update found for " + ModuleInstallRules._plain(String(each), 60) + ": check first";
        const result = _step({ type: "add", items: wanted.map(each => _item(each)) });
        return result.ignored ? "Already in the queue" : "";
    }

    function _item(id) {
        const status = host.status(id);
        return { id: id, name: status?.name || id, from: status?.version ?? "", to: checks[id]?.version ?? "", commit: checks[id]?.commit ?? "",
                 uses: null, staged: false };
    }

    // The user approves the update of `id` to the version in `dir` (the version directory the
    // question was about: refused when the row now asks about another). → "" when taken
    function approve(id, dir) {
        return _answer(id, dir, true);
    }

    // The user refuses it: the old version stays, the refusal is remembered. → "" when taken
    function refuse(id, dir) {
        return _answer(id, dir, false);
    }

    function _answer(id, dir, approved) {
        if (!host || !installer)
            return "No module host";
        if (host.locked)
            return "Refused while the session is locked";
        const row = queue.rows.find(each => each.id === id);
        const asked = approvals[id];
        if (!row || row.phase !== "approval" || !asked)
            return ModuleInstallRules._plain(String(id ?? ""), 60) + " waits for no approval";
        if (asked.dir !== dir)
            return "The update changed: " + id + " now asks about " + asked.dir;
        const data = _rowData[id];
        if (!data || data.run !== row.run || data.verifiedDir !== dir)
            return "The update changed: " + id + " " + dir + " is not the version checked";
        let previous = null;
        if (approved) {
            // Written before the switch, so the new version loads without asking again; put
            // back when the update does not go through (_settleRows)
            previous = ModuleRules.isObject(host.acknowledgements) && ModuleRules.has(host.acknowledgements, id)
                ? Object.assign({}, host.acknowledgements[id]) : null;
            const why = host.acknowledgeUpdate(id, ModuleInstallRules.acknowledgementOf(
                { source: data.record?.kind ?? "", address: data.record?.address ?? "" }, data.manifest ?? {}));
            if (why !== "")
                return why;
            _setRow(id, { ackWritten: true, ackPrevious: previous });
        }
        const result = _step({ type: approved ? "approved" : "refused", id: id, to: row.to, commit: row.commit });
        if (result.ignored) {
            if (approved)
                _restoreAcknowledgement(id);
            return "The update changed";
        }
        const left = Object.assign({}, approvals);
        delete left[id];
        approvals = left;
        return "";
    }

    // Stops what runs: the check, the download, the rows not yet switched (failed,
    // "cancelled"); an answer that comes after is ignored. A switch under way finishes.
    function cancel() {
        _generation++;
        checking = false;
        if (_current && (_current.action === "download" || _current.action === "fetch"))
            installer.cancelDownload(_current.job);
        if (_current && _current.action !== "switch" && _current.action !== "rememberRefusal")
            _current = null;
        _pending = _pending.filter(action => action.action === "switch" || action.action === "rememberRefusal");
        const stopped = {};
        for (const id of Object.keys(checks))
            stopped[id] = checks[id].downloading ? Object.assign({}, checks[id], { downloading: false }) : checks[id];
        checks = stopped;
        for (const row of queue.rows.filter(each => each.phase === "downloading" || each.phase === "verifying"))
            _step({ type: "failed", id: row.id, run: row.run, reason: "cancelled" });
        Qt.callLater(_pump);
    }

    // "Later": the offer goes, the pending restart stays (restartNeeded)
    function dismissRestartOffer() {
        restartOffer = null;
    }

    // Asks to open Settings → Modules on what a notification is about
    function open(request) {
        openRequest = request;
        openRequested(request);
        if ((Shell.settingsPageIds ?? []).includes("modules"))
            Shell.openSettings("modules");
    }

    // One step of the queue, and what it says to do
    function _step(event) {
        const result = ModuleUpdateRules.queueStep(queue, event);
        if (result.ignored)
            return result;
        queue = result.queue;
        _settleRows();
        for (const action of result.actions)
            _enqueue(action);
        if (result.offer) {
            restartOffer = result.offer;
            _offeredIds = _offeredIds.concat(result.offer.ids.filter(each => !_offeredIds.includes(each)));
            const names = result.offer.ids.map(each => queue.rows.find(row => row.id === each)?.name || each);
            restartNeeded = restartNeeded.concat(names.filter(name => !restartNeeded.includes(name)));
        }
        if (result.notification && _newsIn(result.notification))
            _notify(result.notification);
        if (queue.ended) {
            Qt.callLater(_autoRunEnded);
            Qt.callLater(_lateRestarts);
        }
        Qt.callLater(_pump);
        return result;
    }

    function _setRow(id, changes) {
        _rowData = Object.assign({}, _rowData, { [id]: Object.assign({}, _rowData[id], changes) });
    }

    // Each row's own data, made when the row is (from what the check found then); an update
    // that did not go through puts back the acknowledgement its approval wrote, and is not
    // tried again by the daily run at the same commit
    function _settleRows() {
        for (const row of queue.rows) {
            const data = _rowData[row.id];
            if (!data || data.run !== row.run)
                _setRow(row.id, { run: row.run, ref: _info[row.id]?.ref ?? "", dir: _info[row.id]?.dir ?? "", verifiedDir: "", manifest: null,
                                  record: _info[row.id]?.record ?? null, ackWritten: false, ackPrevious: null, restartBefore: false });
            if (row.phase === "failed" || row.phase === "notFinished")
                _restoreAcknowledgement(row.id);
            if (row.phase === "failed" && row.reason !== "cancelled" && _failedCommits[row.id] !== row.commit)
                _failedCommits = Object.assign({}, _failedCommits, { [row.id]: row.commit });
            if (row.phase === "done" && _failedCommits[row.id] !== undefined) {
                const left = Object.assign({}, _failedCommits);
                delete left[row.id];
                _failedCommits = left;
            }
        }
    }

    function _restoreAcknowledgement(id) {
        const data = _rowData[id];
        if (!data?.ackWritten)
            return;
        _setRow(id, { ackWritten: false });
        if (ModuleRules.isObject(data.ackPrevious))
            host.acknowledgeUpdate(id, data.ackPrevious);
        else
            host.dropAcknowledgement(id);
        console.info("[Modules] " + id + ": the update did not go through, its earlier approval is back");
    }

    // Whether a queue's notification tells anything not told before: the same module failing
    // the same way at the same commit, or still waiting, is not told again
    function _newsIn(note) {
        if (note.opens === "restart")
            return true;
        const keys = queue.rows.filter(row => ["done", "failed", "notFinished", "approval"].includes(row.phase))
            .map(row => row.phase + "|" + row.id + "|" + row.commit + "|" + (row.phase === "failed" ? row.reason : ""));
        const fresh = keys.filter(key => !_announced.includes(key));
        _announced = _announced.concat(fresh).slice(-200);
        return fresh.length > 0;
    }

    function _enqueue(action) {
        _pending = _pending.concat([action]);
        Qt.callLater(_pump);
    }

    // The next action, when the installer is free and the session unlocked
    function _pump() {
        if (_current !== null || !host || !installer || host.locked || installer.busy || _pending.length === 0)
            return;
        const action = _pending[0];
        _pending = _pending.slice(1);
        const row = queue.rows.find(each => each.id === action.id);
        const live = action.action === "fetch" || action.action === "rememberRefusal"
                     || (row && row.run === action.subject?.run);
        if (!live) {
            Qt.callLater(_pump);
            return;
        }
        const run = action.subject?.run ?? 0;
        switch (action.action) {
        case "fetch":
            if (action.generation !== _generation || checks[action.id]?.downloading !== true || _rowBusy(action.id)) {
                if (checks[action.id]?.downloading)
                    checks = Object.assign({}, checks, { [action.id]: Object.assign({}, checks[action.id], { downloading: false }) });
                Qt.callLater(_pump);
                return;
            }
            _startJob(action, () => installer.fetchUpdate(action.id, _info[action.id]?.ref ?? ""));
            return;
        case "download": {
            const data = _rowData[action.id];
            if (data?.run !== run) {
                Qt.callLater(_pump);
                return;
            }
            if (data.dir !== "") {
                _step({ type: "downloaded", id: action.id, run: run });
                return;
            }
            _startJob(action, () => installer.fetchUpdate(action.id, data.ref));
            return;
        }
        case "verify":
            _verify(action, run);
            return;
        case "switch": {
            // Only the version the host checked and consentFor judged
            const data = _rowData[action.id];
            if (data?.run !== run || data.verifiedDir === "") {
                _step({ type: "failed", id: action.id, run: run, reason: "the version to switch to was not checked" });
                return;
            }
            // (Configuration backups come with M3c: nothing to back up here yet)
            _step({ type: "backedUp", id: action.id, run: run });
            _setRow(action.id, { restartBefore: (host.restartNeededIds ?? []).includes(action.id) });
            _startJob(action, () => installer.switchVersion(action.id, data.verifiedDir));
            return;
        }
        case "rememberRefusal":
            _startJob(action, () => installer.rememberRefusal(action.id, action.version, action.commit));
            return;
        }
        Qt.callLater(_pump);
    }

    // Starts the installer's job for an action; a refusal that may pass (another job, the
    // lock) puts the action back first in line
    function _startJob(action, start) {
        const why = start();
        if (why === "") {
            _current = Object.assign({}, action, { job: installer.jobNumber, generation: _generation });
            return;
        }
        if (installer.busy || host.locked) {
            _pending = [action].concat(_pending);
            return;
        }
        _jobAnswered(action, { ok: false, message: why, details: {} });
    }

    Connections {
        target: root.installer
        function onFinished(result) {
            const current = root._current;
            if (!current || current.job !== result.job) {
                Qt.callLater(root._pump);
                return;
            }
            root._current = null;
            // Given up because the session locked: tried again after the unlock
            if (!result.ok && root.host.locked && (current.action === "download" || current.action === "fetch")) {
                root._pending = [current].concat(root._pending);
                return;
            }
            root._jobAnswered(current, result);
            Qt.callLater(root._pump);
        }
        function onProgressChanged() {
            const current = root._current;
            if (current?.action === "download" && root.installer.progress)
                root._step({ type: "progress", id: current.id, run: current.subject.run, progress: root.installer.progress });
        }
    }

    function _jobAnswered(action, result) {
        const id = action.id;
        const run = action.subject?.run ?? 0;
        switch (action.action) {
        case "fetch": {
            // A row queued meanwhile keeps its own
            if (result.ok && !_rowBusy(id))
                _info = Object.assign({}, _info, { [id]: Object.assign({}, _info[id], { dir: result.details.dir }) });
            if (checks[id])
                checks = Object.assign({}, checks, { [id]: Object.assign({}, checks[id], {
                    downloading: false, downloadedDir: result.ok ? result.details.dir : "",
                    outcome: result.ok ? checks[id].outcome : "failed", reason: result.ok ? "" : ModuleInstallRules._plain(result.message, 200) }) });
            if (result.ok)
                _readChangelog(id, result.details.directory, host.status(id)?.version ?? "", result.details.version);
            return;
        }
        case "download":
            if (!result.ok) {
                _step({ type: "failed", id: id, run: run, reason: result.message });
                return;
            }
            if (_rowData[id]?.run === run)
                _setRow(id, { dir: result.details.dir });
            _step({ type: "downloaded", id: id, run: run });
            return;
        case "switch": {
            const row = queue.rows.find(each => each.id === id);
            if (!result.ok) {
                _step({ type: "failed", id: id, run: run, reason: result.message });
                return;
            }
            if ((result.details?.back ?? []).includes(id)) {
                _step({ type: "failed", id: id, run: run, reason: (row?.to || "the new version") + " failed to start; "
                                                                  + (row?.from || "the version before") + " is active again" });
                return;
            }
            const restart = (host.restartNeededIds ?? []).includes(id) && _rowData[id]?.restartBefore !== true;
            _step({ type: "installed", id: id, run: run, restart: restart });
            return;
        }
        case "rememberRefusal":
            if (!result.ok)
                console.warn("[Modules] the refusal of " + id + " " + action.version + " could not be remembered: " + result.message);
            return;
        }
    }

    // The new version checked by the host and judged: whether it needs consent
    function _verify(action, run) {
        const id = action.id;
        const generation = _generation;
        _current = Object.assign({}, action, { job: -1, generation: generation });
        const stillAsked = () => _current?.action === "verify" && _current.id === id && _current.subject.run === run && generation === _generation;
        const answer = event => {
            if (!stillAsked())
                return;
            _current = null;
            _step(event);
        };
        installer.readInstalled(read => {
            if (!stillAsked())
                return;
            const record = read.ok ? read.records.modules[id] : null;
            const data = _rowData[id];
            const dir = data?.run === run ? data.dir : "";
            if (dir === "" || !record || !read.found[id] || !record.versions.some(each => each.dir === dir)) {
                answer({ type: "failed", id: id, run: run, reason: "the downloaded version is no longer there" });
                return;
            }
            const directory = installer.places.versions + "/" + id + "/" + dir;
            host.checkDirectory(directory, checked => {
                if (!stillAsked())
                    return;
                const problem = ModuleInstallRules.stagedProblem(checked, id);
                if (problem !== "") {
                    answer({ type: "failed", id: id, run: run, reason: problem });
                    return;
                }
                const manifest = checked.manifest;
                const kept = record.versions.find(each => each.dir === dir);
                const status = host.status(id);
                const counted = host.statuses.filter(each => each.state !== "duplicate" && each.shadowedBy === "");
                const names = {};
                for (const each of counted)
                    names[each.id] = each.name || each.id;
                const installed = ModuleInstallRules.installedModules(counted.map(each => ({ status: each, manifest: host.manifestOf(each.directory) })), read.records);
                const plan = ModuleDependencyRules.plan(manifest, installed, {}, { shellApi: host.apiVersion });
                const consent = ModuleUpdateRules.consentFor(host.acknowledgements?.[id], record, manifest, record.address, {
                    dependencyPlan: plan, currentManifest: status ? host.manifestOf(status.directory) : null, found: {}, names: names
                });
                _setRow(id, { verifiedDir: dir, manifest: manifest, record: record });
                afterNotes = Object.assign({}, afterNotes, { [id]: consent.after.map(note => note.line) });
                if (consent.needed)
                    approvals = Object.assign({}, approvals, { [id]: { dir: dir, version: String(manifest.version ?? ""), reasons: consent.reasons } });
                _readChangelog(id, directory, status?.version ?? "", String(manifest.version ?? ""));
                answer({ type: "verified", id: id, run: run, to: String(manifest.version ?? ""), commit: kept?.commit ?? "",
                         uses: manifest.uses ?? [], consent: consent });
            });
        });
    }

    // The new version's CHANGELOG.md, at most ModuleUpdateRules.maxChangelogBytes, the part
    // after the version running now (a file that is a link is not read)
    function _readChangelog(id, directory, from, to) {
        const name = host.status(id)?.name || id;
        // Late answers lose: only the newest read of a module's changelog is taken
        const token = (_changelogAsked[id] ?? 0) + 1;
        _changelogAsked = Object.assign({}, _changelogAsked, { [id]: token });
        _runner.start(["sh", "-c", "f=$1/CHANGELOG.md; [ -f \"$f\" ] && [ ! -L \"$f\" ] || exit 3; head -c \"$2\" -- \"$f\"", "sh",
                       directory, String(ModuleUpdateRules.maxChangelogBytes)], {
            timeoutMs: 10000,
            done: result => {
                if (_changelogAsked[id] !== token)
                    return;
                const shown = ModuleUpdateRules.changelogSince(result.ok ? String(result.stdout ?? "") : null, from, to);
                changelogs = Object.assign({}, changelogs, { [id]: Object.assign({ name: name, from: from, to: to }, shown) });
            }
        });
    }

    // ---- The end of a queue: one notification ----

    function _notify(note) {
        const restart = note.opens === "restart";
        const request = { page: "modules", show: restart ? "restart" : "changelog", ids: (note.ids ?? []).slice() };
        const hints = restart && restartToken !== "" ? { "x-h2s-restart-for": restartToken } : {};
        // A restart reminder replaces the one before: one at a time
        if (restart && _restartHandle?.open)
            _restartHandle.close();
        const handle = notifier?.send(note.title, {
            body: note.body, format: "plain", handle: true, hints: hints,
            actions: [{ id: "default", label: "Open", onTriggered: () => root.open(request) }]
        });
        if (restart)
            _restartHandle = handle ?? null;
    }

    // Reminders an earlier process left: the restart they asked for has happened
    function closeStaleReminders() {
        if (restartToken === "")
            return 0;
        let closed = 0;
        for (const notification of (notificationServer?.notifications?.values ?? []).slice()) {
            if (ModuleUpdateRules.staleRestartReminder(notification?.hints, restartToken)) {
                notification.dismiss();
                closed++;
            }
        }
        return closed;
    }

    onRestartTokenChanged: Qt.callLater(closeStaleReminders)

    // ---- The daily run ----

    // Whether the daily run is due now, and if so runs it: checks every module, queues what
    // it finds (switched unless consent is due)
    function autoTick() {
        if (!autoStateKnown || !host || !installer || checking || _autoRun !== null)
            return;
        const due = ModuleUpdateRules.autoRunDue(autoState, automatic, host.locked, now());
        if (!due.due)
            return;
        _autoRun = { failedChecks: 0, ids: [], startedAt: now() };
        _checkModules("", true, results => {
            const run = _autoRun;
            if (run === null)
                return;
            run.failedChecks = results.filter(each => each.outcome === "failed").length;
            // An update that failed at this commit is not downloaded again by the daily run
            const found = results.filter(each => each.outcome === "available" && _failedCommits[each.id] !== checks[each.id]?.commit)
                .map(each => each.id);
            run.ids = found;
            // Queued even when the session locked meanwhile: the actions wait for the unlock
            if (found.length > 0)
                _step({ type: "add", items: found.map(each => _item(each)) });
            Qt.callLater(_autoRunEnded);
        });
    }

    // The run has ended once its rows rest: its outcome remembered (logged on a change)
    function _autoRunEnded() {
        const run = _autoRun;
        if (run === null || checking)
            return;
        const rows = queue.rows.filter(row => run.ids.includes(row.id));
        if (rows.some(row => !["done", "failed", "notFinished", "approval", "held"].includes(row.phase)))
            return;
        _autoRun = null;
        // A cancel is the user's: the run counts as made, not failed
        const failed = run.failedChecks > 0 || rows.some(row => row.phase === "failed" && row.reason !== "cancelled");
        const record = ModuleUpdateRules.autoRunRecord(autoState, failed ? "failed" : "ok", run.startedAt);
        autoState = record.state;
        autoStateWritten(record.state);
        if (record.log) {
            if (failed)
                console.warn("[Modules] the daily update run failed; it is tried again later");
            else
                console.info("[Modules] the daily update run went through");
        }
    }

    Timer {
        interval: Math.max(1000, root.autoCheckIntervalMs)
        repeat: true
        running: root.automatic && root.autoStateKnown && root.host !== null
        onTriggered: root.autoTick()
    }

    // The host names a module whose new files only a restart loads after the installer
    // already said the switch was done: its own offer
    function _lateRestarts() {
        const late = (host?.restartNeededIds ?? []).filter(id => !_offeredIds.includes(id) && _rowData[id]?.restartBefore === false
                                                             && queue.rows.some(row => row.id === id && row.phase === "done"));
        if (late.length === 0)
            return;
        // While the queue runs, the row takes it: the queue's one offer at its end names it
        if (!queue.ended) {
            const copy = JSON.parse(JSON.stringify(queue));
            for (const row of copy.rows)
                if (late.includes(row.id) && row.phase === "done")
                    row.restart = true;
            queue = copy;
            return;
        }
        _offeredIds = _offeredIds.concat(late);
        const ids = (restartOffer?.ids ?? []).concat(late);
        const nameOf = id => queue.rows.find(row => row.id === id)?.name || id;
        const names = ModuleUpdateRules._joinNames(ids.map(nameOf));
        restartOffer = { text: "Restart the shell to load the new files of " + names + ".", ids: ids };
        restartNeeded = restartNeeded.concat(late.map(nameOf).filter(name => !restartNeeded.includes(name)));
        _notify({ title: "Restart needed", body: "Restart the shell to finish updating " + ModuleUpdateRules._joinNames(late.map(nameOf)) + ".",
                  opens: "restart", ids: late });
    }

    // The lock ends: what waited goes on, and a run that was due runs
    Connections {
        target: root.host
        function onRestartNeededIdsChanged() {
            Qt.callLater(root._lateRestarts);
        }
        function onLockedChanged() {
            if (!root.host.locked) {
                Qt.callLater(root._pump);
                Qt.callLater(root.autoTick);
            }
        }
    }

    onAutomaticChanged: Qt.callLater(autoTick)
    onAutoStateKnownChanged: Qt.callLater(autoTick)
    Component.onCompleted: Qt.callLater(closeStaleReminders)
}
