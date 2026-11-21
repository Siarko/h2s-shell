import QtQuick
import Quickshell
import qs.singletons.io

// The module installer (notes/plans/modules-management.md §6): installs a module from a git
// address or a folder, with the modules it needs; switches an installed module to another
// kept version, deletes a kept version, removes a module; goes back to the version before
// when an update or a switch does not start. No views: Settings → Modules and
// `qs ipc call modules install|remove|switchVersion|…` (Modules.qml) call it.
//
// Everything is the user's own, under the data and config homes (§8b), done as the user —
// no privileges. Nothing from a module's files is ever run: git runs with no hooks, no
// submodules, no credential prompt, only the https/ssh/git/file protocols, the address after
// "--" (ModuleInstallRules.downloadCommands); a folder is copied without following links.
// Every command is a run of the installer's own CommandRunner, under a time limit; what
// comes back from outside (git's lines, a manifest's words) is plain text, capped.
//
// Installing, in steps (`phase`): "downloading" into a new directory under
// <dataHome>/h2s-shell/module-staging (git's progress in `progress`, read as git redraws it;
// the directory measured while git or the copy writes it and once it is there — past
// `maxDownloadBytes` the download is stopped; a link out of the module refuses it);
// "verifying" — the host's own file check and manifest rules on the staged directory
// (ModuleHost.checkDirectory), the id free or the shell's own (ModuleInstallRules.installTarget:
// a folder or link placed by hand, under any name, is never replaced or joined), then the
// dependency chain (ModuleDependencyRules.plan: each missing dependency with a source
// downloaded and checked the same way, until nothing is left to fetch; one that cannot be had
// stops the install unless `anyway`); "installing" — each staged directory renamed to
// module-versions/<id>/<version>-<commit7>, the record (module-sources.json, by a temporary
// file and a rename) written listing the new versions, each link modules/<id> moved onto its
// version in one rename (providers first), and the record written again with the new
// versions active; a step that fails takes back the ones before
// (ModuleDependencyRules.rollbackPlan: links, versions, the record's entries) so the user
// root is as it was. Then the host searches again and loads (rediscover()); an updated module
// that does not start goes back to its version before (ModuleInstallRules.backOnFailedStart).
// With `enable` (the default) the new modules are acknowledged and turned on — the preview,
// or a typed IPC command, was the user's confirmation; without, they stay off. Both act only
// on the module as loaded from the version directory this job made. tidy(), at the shell's
// start, puts right what a run cut off left (staging, temporary links, the record).
//
// Late answers lose: one job at a time, and every answer is checked against the job it was
// started for. Nothing starts while the session is locked; a download that is still running
// when it locks is given up before anything moves in. A record that cannot be read is
// never written over (installing refuses; Remove treats the module as placed by hand). A
// path is deleted only where ModuleInstallRules.deletionTarget allows, never through a link.
Scope {
    id: root

    // The host whose modules these are (Modules.host; the suites their own)
    property var host: null
    // The data and config homes (SystemFacts.dataHome; XDG_CONFIG_HOME) and the home (for
    // the words of Remove); "" — nothing can be done
    property string dataHome: ""
    property string configHome: ""
    property string home: ""
    // Added to every command's environment (the suites: a PATH with a stand-in git first)
    property var environment: ({})
    // How long one git command may take, the file steps, and the load after the search
    property int downloadTimeoutMs: 120000
    property int stepTimeoutMs: 30000
    property int loadTimeoutMs: 30000
    // The largest download (ModuleInstallRules.maxDownloadBytes; the suites a smaller one),
    // and how often a download's directory is measured while git writes it
    property real maxDownloadBytes: ModuleInstallRules.maxDownloadBytes
    property int measureIntervalMs: 1000

    readonly property var places: ModuleInstallRules.paths(dataHome, configHome)
    // A job runs (one at a time)
    readonly property bool busy: _job !== null
    // What it does now: "", "downloading", "verifying", "installing", "loading", "removing",
    // "switching", "deleting"
    property string phase: ""
    // What the step is about (an address, a folder, a module's name), plain text
    property string subject: ""
    // git's progress while it gives numbers ({ phase, percent, bytes, rate }), else null: a
    // step of unknown length
    property var progress: null
    // How the last job ended: { ok, action, message, ids }
    property var lastResult: null

    signal finished(var result)

    property var _job: null
    property int _jobCount: 0

    // ---- Starting a job ----

    // Why nothing may start now, "" when a job may
    function _refusal() {
        if (!host)
            return "No module host";
        if (host.locked)
            return "Refused while the session is locked";
        if (_job !== null)
            return "Another module job is running";
        if (places.user === "" || places.staging === "")
            return "The data home is not known";
        return "";
    }

    function _start(action, fields) {
        const job = Object.assign({ number: ++_jobCount, action: action, staged: [], done: [], fetched: {}, notes: [], ids: [] }, fields);
        _job = job;
        phase = "";
        subject = "";
        progress = null;
        return job;
    }

    function _alive(job) {
        return _job === job;
    }

    function _finish(job, ok, message) {
        if (!_alive(job))
            return;
        const text = ModuleInstallRules._plain(message, 400);
        // `job` names the job (its subject: whoever started it knows its answer by that);
        // `details` what a caller needs beyond the words (fetchUpdate's version, the modules
        // a switch took back)
        const result = { ok: ok, action: job.action, message: text, ids: job.ids.slice(), job: job.number,
                         details: Object.assign({ back: (job.back ?? []).slice() }, job.details ?? {}) };
        _job = null;
        phase = "";
        subject = "";
        progress = null;
        lastResult = result;
        // A quiet job (the start's tidying) says only what it changed or what failed
        if (!ok)
            console.warn("[Modules] " + job.action + " failed: " + text);
        else if (job.quiet !== true)
            console.info("[Modules] " + text);
        finished(result);
    }

    // Install a module from `source` — a git address ("<url>#<ref>" allowed) or an absolute
    // folder path — with the modules it needs. `options`: { enable (default true): acknowledge
    // and turn on what is new; anyway: install what resolves when a dependency cannot be had;
    // alsoInstall: [ids] — soft dependencies to install too }. → "" when it started, else why
    // not (the outcome: lastResult, finished(), the log)
    function install(source, options) {
        const refusal = _refusal();
        if (refusal !== "")
            return refusal;
        const given = ModuleInstallRules.installSource(source);
        if (given.kind === "")
            return given.problem;
        const job = _start("install", {
            enable: options?.enable !== false, anyway: options?.anyway === true,
            alsoInstall: Array.isArray(options?.alsoInstall) ? options.alsoInstall.filter(id => typeof id === "string") : [],
            source: given
        });
        _readSources(job, () => _download(job, given, "", staged => {
            job.root = staged;
            job.ids = [staged.manifest.id];
            job.rootTarget = _target(job, staged.manifest.id);
            if (job.rootTarget.kind === "taken") {
                _abandon(job, job.rootTarget.problem);
                return;
            }
            _resolve(job);
        }));
        return "";
    }

    // Remove module `id`, found at `directory` (as `modules list` shows it — the subject: a
    // module that now lives elsewhere is not removed). `options`: { withData — its data
    // directory, store, backups and settings too; alsoRemove: [ids] — dependencies installed
    // for it that nothing else uses (ModuleDependencyRules.orphans) }. → "" when it started
    function remove(id, directory, options) {
        const refusal = _refusal();
        if (refusal !== "")
            return refusal;
        const status = host.status(id);
        const canonical = ModuleFileRules.canonicalPath(String(directory ?? ""));
        if (!status)
            return "No module \"" + ModuleInstallRules._plain(String(id ?? ""), 60) + "\"";
        if (canonical === "" || canonical !== status.directory)
            return "The module changed: " + id + " is now " + ModuleInstallRules._plain(status.directory);
        const job = _start("remove", { withData: options?.withData === true,
                                       alsoRemove: Array.isArray(options?.alsoRemove) ? options.alsoRemove.filter(each => typeof each === "string") : [] });
        job.ids = [id];
        phase = "removing";
        subject = status.name || id;
        _readSources(job, () => _removeWith(job, id, status), true);
        return "";
    }

    // Make another kept version of module `id` the active one (`dir`: its directory name, as
    // the record lists it, or its path). → "" when it started
    function switchVersion(id, dir) {
        const refusal = _refusal();
        if (refusal !== "")
            return refusal;
        const job = _start("switch", {});
        job.ids = [String(id)];
        phase = "switching";
        subject = String(id);
        _readSources(job, () => {
            const found = ModuleInstallRules.installedEntry(id, job.sources, job.records);
            const record = found ? job.records.modules[id] : null;
            const plan = ModuleInstallRules.switchPlan(id, dir, found, record);
            if (!plan.ok) {
                _finish(job, false, plan.problem);
                return;
            }
            const versionPath = places.versions + "/" + id + "/" + plan.dir;
            host.checkDirectory(versionPath, check => {
                if (!_alive(job))
                    return;
                const problem = ModuleInstallRules.stagedProblem(check, id);
                if (problem !== "") {
                    _finish(job, false, id + " " + plan.dir + ": " + problem);
                    return;
                }
                _switchTo(job, id, plan.dir, plan.previousDir, directory => {
                    const step = { id: id, kind: "switch", dir: plan.dir, previousDir: plan.previousDir, directory: directory };
                    _reload(job, loaded => _afterStart(job, [step], loaded, () =>
                        _finish(job, true, id + " switched to " + plan.dir + _notesText(job))));
                });
            });
        });
        return "";
    }

    // Delete a kept version of module `id` that is not the active one. → "" when it started
    function deleteVersion(id, dir) {
        const refusal = _refusal();
        if (refusal !== "")
            return refusal;
        const job = _start("deleteVersion", {});
        job.ids = [String(id)];
        phase = "deleting";
        subject = String(id);
        _readSources(job, () => {
            const found = ModuleInstallRules.installedEntry(id, job.sources, job.records);
            const record = found ? job.records.modules[id] : null;
            const plan = ModuleInstallRules.deleteVersionPlan(id, dir, found, record);
            if (!plan.ok) {
                _finish(job, false, plan.problem);
                return;
            }
            const records = ModuleInstallRules.recordWithoutVersions(job.records.modules, id, [plan.dir]);
            _writeRecord(job, records, ok => {
                if (!ok) {
                    _finish(job, false, "the record of installed modules could not be written: nothing deleted");
                    return;
                }
                _fileOps(job, [{ op: "tree", path: places.versions + "/" + id + "/" + plan.dir }], problems =>
                    _finish(job, problems.length === 0, problems.length === 0 ? id + " " + plan.dir + " deleted" : problems.join("; ")));
            });
        });
        return "";
    }

    // Download a new version of module `id` — the shell's own, from its recorded address at
    // `ref` ("" the recorded ref) — and move it in beside the kept versions without linking it
    // (the updater's background download, §6.3): verified as an install is, the record
    // listing it, the active version and the recorded ref unchanged; the versions beyond the
    // kept ones go (ModuleUpdateRules.keepPlan, the new one kept as waiting). A version the
    // record keeps already (the same commit) is taken as it is. → "" when it started (its
    // number: `jobNumber`); the outcome's `details`: { dir, version, commit, directory }
    function fetchUpdate(id, ref) {
        const refusal = _refusal();
        if (refusal !== "")
            return refusal;
        if (!ModuleManifestRules.validId(id))
            return "Not a module id: " + ModuleInstallRules._plain(String(id ?? ""), 60);
        if (typeof ref !== "string" || (ref !== "" && ModuleInstallRules._refProblem(ref) !== ""))
            return "Not a tag, branch or commit: " + ModuleInstallRules._plain(String(ref ?? ""), 60);
        const job = _start("fetchUpdate", {});
        job.ids = [id];
        _readSources(job, () => {
            const found = ModuleInstallRules.installedEntry(id, job.sources, job.records);
            const record = found ? job.records.modules[id] : null;
            if (!record || record.kind !== "repository") {
                _finish(job, false, id + (record ? ": copied from a folder, nothing to download" : " was not installed by the shell"));
                return;
            }
            const source = ModuleInstallRules.fetchSource({ address: record.address, ref: ref !== "" ? ref : record.ref });
            if (source.kind !== "repository") {
                _finish(job, false, id + ": " + (source.problem || "its recorded address cannot be used"));
                return;
            }
            _download(job, source, id, staged => _moveInBeside(job, id, record, staged));
        });
        return "";
    }

    // fetchUpdate's download moved to its version directory and listed in the record, not linked
    function _moveInBeside(job, id, record, staged) {
        if (host.locked) {
            _abandon(job, "the session was locked: nothing downloaded");
            return;
        }
        phase = "installing";
        const dir = ModuleInstallRules.versionDirectoryName(staged.manifest.version, staged.commit, Date.now());
        const kept = record.versions.some(each => each.dir === dir);
        _run(["sh", "-c", "s=$1; v=$2; id=$3; dir=$4; mode=$5; umask 077; mkdir -p -- \"$v/$id\" || exit 1; "
              + "[ ! -L \"$v/$id\" ] || exit 1; d=$v/$id/$dir; [ ! -L \"$d\" ] || exit 1; "
              + "if [ -e \"$d\" ]; then if [ \"$mode\" = reuse ]; then rm -rf -- \"$s\"; exit 0; fi; rm -rf -- \"$d\" || exit 1; fi; "
              + "mv -T -- \"$s\" \"$d\"",
              "sh", staged.dir, places.versions, id, dir, kept ? "reuse" : "replace"], {
            timeoutMs: stepTimeoutMs,
            done: result => {
                if (!_alive(job))
                    return;
                if (!result.ok) {
                    _abandon(job, id + ": the download could not be moved into place");
                    return;
                }
                job.staged = job.staged.filter(each => each !== staged.dir);
                let modules = ModuleInstallRules.recordStaged(job.records.modules, id, {
                    kind: "repository", address: record.address, ref: record.ref, dir: dir,
                    version: staged.manifest.version, commit: staged.commit, fetchedAt: new Date().toISOString(),
                    installedFor: record.installedFor
                });
                const keep = ModuleUpdateRules.keepPlan(modules[id], { pendingDir: dir });
                const dropped = keep.ok ? keep.delete : [];
                modules = ModuleInstallRules.recordWithoutVersions(modules, id, dropped);
                _writeRecord(job, modules, ok => {
                    if (!ok) {
                        _fileOps(job, kept ? [] : [{ op: "tree", path: places.versions + "/" + id + "/" + dir }], () =>
                            _finish(job, false, "the record of installed modules could not be written; nothing downloaded"));
                        return;
                    }
                    job.records = { ok: true, modules: modules, dropped: [] };
                    job.details = { dir: dir, version: String(staged.manifest.version ?? ""), commit: staged.commit,
                                    directory: places.versions + "/" + id + "/" + dir };
                    _fileOps(job, dropped.map(each => ({ op: "tree", path: places.versions + "/" + id + "/" + each })), problems => {
                        if (problems.length > 0)
                            console.warn("[Modules] older versions could not be deleted: " + problems.join("; "));
                        _finish(job, true, id + " " + dir + " downloaded");
                    });
                });
            }
        });
    }

    // Remember that the user refused version `version` (`commit`) of module `id` (§6.4): the
    // record's `refused`, so it is never offered again nor switched to. → "" when it started
    function rememberRefusal(id, version, commit) {
        const refusal = _refusal();
        if (refusal !== "")
            return refusal;
        if (!ModuleManifestRules.validId(id) || typeof version !== "string" || typeof commit !== "string" || !/^[0-9a-f]{0,64}$/.test(commit))
            return "Not a version to refuse";
        const job = _start("refuse", { quiet: true });
        job.ids = [id];
        _readSources(job, () => {
            if (!ModuleInstallRules.installedEntry(id, job.sources, job.records)) {
                _finish(job, false, id + " was not installed by the shell");
                return;
            }
            const modules = JSON.parse(JSON.stringify(job.records.modules));
            modules[id].refused = { version: version.slice(0, 64), commit: commit };
            _writeRecord(job, modules, ok => _finish(job, ok, ok ? id + " " + version + " refused" : "the record of installed modules could not be written"));
        });
        return "";
    }

    // Stops the download of the job running now (`job`: its number — the subject: another
    // job is never stopped): nothing moves in, staging is emptied. → true when there was
    // one to stop
    function cancelDownload(job) {
        if (!_job || _job.number !== job || phase !== "downloading")
            return false;
        _job.cancelled = true;
        _downloading?.handle?.cancel();
        return true;
    }

    // The number of the job started last: right after a call that started one, its subject
    // (lastResult.job names the job an outcome belongs to)
    readonly property int jobNumber: _jobCount

    // What the shell installed, read now without a job (the updater's checks): done({ ok,
    // records: parseRecord's result, found: { id: installedEntry's result } }) — ok false when
    // the modules folder or the record cannot be read
    function readInstalled(done) {
        if (!host || places.user === "") {
            Qt.callLater(() => done({ ok: false, records: { ok: false, modules: {}, dropped: [] }, found: {} }));
            return;
        }
        _sourceCheck((sources, records) => {
            const found = {};
            if (sources.complete && records.ok)
                for (const id of Object.keys(records.modules)) {
                    const entry = ModuleInstallRules.installedEntry(id, sources, records);
                    if (entry)
                        found[id] = entry;
                }
            done({ ok: sources.complete && records.ok && records.dropped.length === 0, records: records, found: found });
        });
    }

    // At the shell's start: what an earlier run left — the staging place emptied, temporary
    // links in the user root removed, and the record put right where a run was cut off
    // between moving a version in and writing it (ModuleInstallRules.reconcileRecord).
    // → "" when it started, else why not
    function tidy() {
        const refusal = _refusal();
        if (refusal !== "")
            return refusal;
        const job = _start("tidy", { quiet: true });
        _run(["sh", "-c", "d=$1; u=$2; if [ -d \"$d\" ] && [ ! -L \"$d\" ]; then "
              + "for e in \"$d\"/* \"$d\"/.[!.]*; do { [ -e \"$e\" ] || [ -L \"$e\" ]; } || continue; rm -rf -- \"$e\"; done; fi; "
              + "if [ -d \"$u\" ] && [ ! -L \"$u\" ]; then for e in \"$u\"/.*.link.*; do [ -L \"$e\" ] && rm -f -- \"$e\"; done; fi; true",
              "sh", places.staging, places.user], {
            timeoutMs: stepTimeoutMs,
            done: result => {
                if (!_alive(job))
                    return;
                if (!result.ok)
                    console.warn("[Modules] the staging place could not be emptied");
                _readSources(job, () => {
                    const fixed = ModuleInstallRules.reconcileRecord(job.sources, job.records);
                    for (const note of fixed.notes)
                        console.warn("[Modules] " + note);
                    if (!fixed.changed) {
                        _finish(job, true, "nothing to put right");
                        return;
                    }
                    job.quiet = false;
                    _writeRecord(job, fixed.modules, ok => _finish(job, ok, ok ? "the record of installed modules put right after a run that was cut off"
                                                                              : "the record of installed modules could not be put right"));
                });
            }
        });
        return "";
    }

    // ---- Reading what is there ----

    // The installer's own look at the user root, the versions and the record (the host's
    // source check, ModuleInstallRules.sourceCheckScript) → job.sources, job.records. A
    // record that cannot be read refuses anything that would write it, except a removal
    // (`forRemoval`), which then treats the module as placed by hand
    function _readSources(job, next, forRemoval) {
        _sourceCheck((sources, records) => {
            if (!_alive(job))
                return;
            job.sources = sources;
            if (!job.sources.complete) {
                _finish(job, false, "your modules folder could not be read");
                return;
            }
            job.records = records;
            if (!forRemoval && (!job.records.ok || job.records.dropped.length > 0)) {
                _finish(job, false, "the record of installed modules (" + places.record + ") cannot be read: nothing is changed");
                return;
            }
            next();
        });
    }

    // The source check run → done(sources, records); records unreadable when the check did
    // not finish
    function _sourceCheck(done) {
        const given = ModuleRules.isObject(host.sourcePlaces) ? host.sourcePlaces : {};
        const placesNow = { user: places.user, versions: places.versions, record: places.record,
                            builtin: typeof given.builtin === "string" ? given.builtin : "",
                            developer: host._plainList(given.developer), system: host._plainList(given.system) };
        const lines = [];
        _run(["sh", "-c", ModuleInstallRules.sourceCheckScript, "sh"].concat(ModuleInstallRules.sourceCheckArguments(placesNow)), {
            timeoutMs: stepTimeoutMs,
            onLine: (line, stream) => {
                if (stream === "stdout")
                    lines.push(line);
            },
            done: () => {
                const sources = ModuleInstallRules.parseSourceCheck(lines);
                const record = sources.record;
                const records = !sources.complete ? { ok: false, modules: {}, dropped: [] }
                              : record.state === "missing" ? { ok: true, modules: {}, dropped: [] }
                              : record.state === "ok" ? ModuleInstallRules.parseRecord(record.text) : { ok: false, modules: {}, dropped: [] };
                done(sources, records);
            }
        });
    }

    // ---- Downloading and verifying ----

    // Fetches `source` (installSource's result) into a new staging directory and checks it;
    // `expectedId` the id the chain asked for ("" for the module asked for). → done({ dir,
    // manifest, commit, source }); a failure ends the job
    function _download(job, source, expectedId, done) {
        if (job.staged.length > ModuleDependencyRules.maxModules) {
            _abandon(job, "the chain has more than " + ModuleDependencyRules.maxModules + " modules");
            return;
        }
        const label = expectedId !== "" ? expectedId : ModuleInstallRules.addressShown(source.address);
        phase = "downloading";
        subject = label;
        progress = null;
        _run(["sh", "-c", "umask 077; mkdir -p -- \"$1\" && mktemp -d -p \"$1\" install.XXXXXXXX", "sh", places.staging], {
            timeoutMs: stepTimeoutMs,
            done: result => {
                if (!_alive(job))
                    return;
                const dir = String(result.stdout ?? "").trim();
                if (!result.ok || !ModuleInstallRules.deletionTarget(dir, places).ok || ModuleInstallRules._parentOf(dir) !== places.staging) {
                    _abandon(job, label + ": the staging place could not be made");
                    return;
                }
                job.staged.push(dir);
                const fetched = commit => _measure(job, label, dir, () => _verify(job, label, dir, expectedId, commit, source, done));
                if (source.kind === "folder")
                    _copyFolder(job, label, source.folder, dir, () => fetched(""));
                else
                    _clone(job, label, source.address, dir, fetched);
            }
        });
    }

    function _copyFolder(job, label, folder, dir, next) {
        const download = { job: job, dir: dir, handle: null, tooLarge: false, measuring: false };
        // (bash: `ulimit -f` counts 1024-byte blocks there — a file past the cap stops cp)
        download.handle = _run(["bash", "-c", "ulimit -f \"$3\" || exit 1; [ -d \"$1\" ] || { echo 'not a folder' >&2; exit 1; }; "
                                + "cp -R --no-dereference -- \"$1/.\" \"$2/\" && rm -rf -- \"$2/.git\"",
                                "bash", folder, dir, String(_fileBlocks())], {
            timeoutMs: downloadTimeoutMs,
            done: result => {
                if (_downloading === download)
                    _downloading = null;
                if (!_alive(job))
                    return;
                if (result.code === _fileTooLargeStatus)
                    download.tooLarge = true;
                if (download.tooLarge) {
                    _abandon(job, label + ": " + ModuleInstallRules.downloadProblem(result, "", { tooLarge: true, cap: maxDownloadBytes }));
                    return;
                }
                if (!result.ok) {
                    _abandon(job, label + ": the folder could not be copied" + (result.timedOut ? " in time" : ""));
                    return;
                }
                next();
            }
        });
        // Measured while it copies, as a download is
        _downloading = download;
        _measureTimer.restart();
    }

    // The git commands of a download, one after the other, then the commit it got; .git goes
    // (the version directory holds the module's files only). git redraws its progress with
    // carriage returns: each command runs behind a reader that ends a line there too, so the
    // progress — and a size past the cap — is seen while it downloads, not once it is done.
    // The directory is measured every measureIntervalMs as well (what git says is the pack;
    // the checkout comes after it), and the command stopped once it is past the cap
    function _clone(job, label, address, dir, next) {
        const commands = ModuleInstallRules.downloadCommands(address, dir);
        if (!commands.ok) {
            _abandon(job, label + ": " + commands.problem);
            return;
        }
        const runNext = index => {
            if (job.cancelled === true) {
                _abandon(job, label + ": cancelled");
                return;
            }
            if (index >= commands.commands.length) {
                _commitOf(job, label, dir, next);
                return;
            }
            const command = commands.commands[index];
            const download = { job: job, dir: dir, handle: null, tooLarge: false, measuring: false };
            let lastLine = "";
            download.handle = _run(["bash", "-c", root._progressReader, "bash", String(CommandTools.setpriv ?? ""), String(_fileBlocks())].concat(command.argv), {
                environment: command.environment, timeoutMs: downloadTimeoutMs, keepOutput: false,
                onLine: (line, stream) => {
                    if (stream !== "stderr" || !_alive(job))
                        return;
                    const read = ModuleInstallRules.progressOf(line);
                    if (read === null) {
                        if (line.trim() !== "")
                            lastLine = line;
                        return;
                    }
                    progress = { phase: read.phase, percent: read.percent, bytes: read.bytes, rate: read.rate };
                    if (read.bytes !== null && read.bytes > maxDownloadBytes)
                        _stopTooLarge(download);
                },
                done: result => {
                    if (_downloading === download)
                        _downloading = null;
                    if (!_alive(job))
                        return;
                    if (result.code === _fileTooLargeStatus)
                        download.tooLarge = true;
                    if (job.cancelled === true) {
                        _abandon(job, label + ": cancelled");
                        return;
                    }
                    if (!result.ok || download.tooLarge) {
                        _abandon(job, label + ": download failed — "
                                 + ModuleInstallRules.downloadProblem(result, lastLine, { timeoutMs: downloadTimeoutMs, tooLarge: download.tooLarge, cap: maxDownloadBytes }));
                        return;
                    }
                    runNext(index + 1);
                }
            });
            _downloading = download;
            _measureTimer.restart();
        };
        runNext(0);
    }

    // Runs a git command (from $3 on) with its standard error read in pieces ended by a
    // carriage return or a line break, each written out as a line at once; its standard
    // output goes; its exit status is the command's. $1: setpriv (CommandTools; "" where it was
    // not found) — git dies with this reader, so a shell that goes mid-download (the reader
    // ends with it) or a cancel (TERM to the reader) leaves no git behind; $2: the largest
    // file it may write, in bash's 1024-byte blocks (`ulimit -f`: a file past it stops git
    // with SIGXFSZ at once, before the next measuring of the whole directory)
    readonly property string _progressReader: "guard=$1; blocks=$2; shift 2; ulimit -f \"$blocks\" || exit 1; set -o pipefail; "
        + "if [ -n \"$guard\" ]; then set -- \"$guard\" --pdeathsig KILL -- \"$@\"; fi; \"$@\" 2>&1 >/dev/null | "
        + "while IFS= read -r -d $'\\r' part || [ -n \"$part\" ]; do printf '%s\\n' \"$part\"; done >&2"

    // The status of a command stopped by `ulimit -f` (SIGXFSZ, 25, as bash reports a signal)
    readonly property int _fileTooLargeStatus: 128 + 25

    // maxDownloadBytes in bash's `ulimit -f` blocks (1024 bytes), at least one
    function _fileBlocks() {
        return Math.max(1, Math.ceil(maxDownloadBytes / 1024));
    }

    // The download running now, measured by _measureTimer
    property var _downloading: null

    function _stopTooLarge(download) {
        if (download.tooLarge)
            return;
        download.tooLarge = true;
        download.handle?.cancel();
    }

    Timer {
        id: _measureTimer
        interval: Math.max(50, root.measureIntervalMs)
        repeat: true
        onTriggered: {
            const download = root._downloading;
            if (!download || !root._alive(download.job)) {
                stop();
                return;
            }
            if (download.measuring)
                return;
            download.measuring = true;
            root._run(["du", "-sk", "--", download.dir], {
                timeoutMs: root.stepTimeoutMs,
                done: result => {
                    download.measuring = false;
                    // du says what it could read and its total even when a file went away
                    // under it (exit status 1): the total counts all the same
                    if (root._downloading !== download)
                        return;
                    const lines = String(result.stdout ?? "").split("\n").filter(line => line !== "");
                    const total = lines.length > 0 ? lines[lines.length - 1] : "";
                    const problem = ModuleInstallRules.stagedSizeProblem(total, root.maxDownloadBytes);
                    if (problem !== "" && problem !== ModuleInstallRules.stagedSizeProblem("", root.maxDownloadBytes))
                        root._stopTooLarge(download);
                }
            });
        }
    }

    function _commitOf(job, label, dir, next) {
        _run(["git", "-C", dir, "-c", "core.hooksPath=/dev/null", "rev-parse", "HEAD"], {
            environment: ModuleInstallRules.gitEnvironment, timeoutMs: stepTimeoutMs,
            done: result => {
                if (!_alive(job))
                    return;
                const commit = String(result.stdout ?? "").trim();
                if (!result.ok || !/^(?:[0-9a-f]{40}|[0-9a-f]{64})$/.test(commit)) {
                    _abandon(job, label + ": the commit downloaded could not be read");
                    return;
                }
                _run(["rm", "-rf", "--", dir + "/.git"], {
                    timeoutMs: stepTimeoutMs,
                    done: removed => {
                        if (!_alive(job))
                            return;
                        if (!removed.ok) {
                            _abandon(job, label + ": the download could not be tidied");
                            return;
                        }
                        next(commit);
                    }
                });
            }
        });
    }

    // Its size, and the links in it that lead out
    function _measure(job, label, dir, next) {
        const lines = [];
        _run(["sh", "-c", "s=$(du -sk -- \"$1\") || exit 1; printf 'size\\t%s\\n' \"$s\"; "
              + "find \"$1\" -type l -exec sh -c 'for l do printf \"link\\t%s\\t%s\\n\" \"$l\" \"$(readlink -f -- \"$l\")\"; done' sh {} +",
              "sh", dir], {
            timeoutMs: stepTimeoutMs,
            onLine: (line, stream) => {
                if (stream === "stdout")
                    lines.push(line);
            },
            done: result => {
                if (!_alive(job))
                    return;
                const size = lines.find(line => line.startsWith("size\t"));
                const problem = !result.ok ? "it could not be measured"
                    : ModuleInstallRules.stagedSizeProblem(size ? size.slice(5) : "", maxDownloadBytes)
                      || ModuleInstallRules.linkProblem(lines.filter(line => line.startsWith("link\t")).map(line => line.slice(5)), dir);
                if (problem !== "") {
                    _abandon(job, label + ": " + problem);
                    return;
                }
                next();
            }
        });
    }

    function _verify(job, label, dir, expectedId, commit, source, done) {
        phase = "verifying";
        progress = null;
        host.checkDirectory(dir, check => {
            if (!_alive(job))
                return;
            const problem = ModuleInstallRules.stagedProblem(check, expectedId);
            if (problem !== "") {
                _abandon(job, label + ": " + problem);
                return;
            }
            done({ dir: dir, manifest: check.manifest, commit: commit, source: source });
        });
    }

    // ---- The chain ----

    // What module `id` finds in the user root (ModuleInstallRules.installTarget), with every
    // module of that id the host has: one placed by hand under another name is never joined
    function _target(job, id) {
        const directories = host.statuses.filter(status => status.id === id).map(status => status.directory);
        return ModuleInstallRules.installTarget(id, job.sources, job.records, directories);
    }

    // The modules installed now, as the plan takes them
    function _installed(job) {
        const counted = host.statuses.filter(status => status.state !== "duplicate" && status.shadowedBy === "");
        return ModuleInstallRules.installedModules(counted.map(status => ({ status: status, manifest: host.manifestOf(status.directory) })), job.records);
    }

    // Plans the chain with what is fetched so far: fetches the next, or installs
    function _resolve(job) {
        if (!_alive(job))
            return;
        const fetched = {};
        for (const id of Object.keys(job.fetched))
            fetched[id] = job.fetched[id].manifest;
        const plan = ModuleDependencyRules.plan(job.root.manifest, _installed(job), fetched,
                                                { shellApi: host.apiVersion, alsoInstall: job.alsoInstall });
        if (plan.refused !== "") {
            _abandon(job, plan.refused);
            return;
        }
        if (plan.fetch.length > 0) {
            const next = plan.fetch[0];
            if (ModuleRules.has(job.fetched, next.id)) {
                _abandon(job, next.id + ": fetched, still asked for");
                return;
            }
            const source = ModuleInstallRules.fetchSource(next);
            if (source.kind === "") {
                _abandon(job, next.id + ": " + source.problem);
                return;
            }
            _download(job, source, next.id, staged => {
                job.fetched[next.id] = staged;
                _resolve(job);
            });
            return;
        }
        if (plan.blocking.length > 0 && !job.anyway) {
            _abandon(job, "not installed: " + plan.blocking.join("; "));
            return;
        }
        if (host.locked) {
            _abandon(job, "the session was locked: nothing installed");
            return;
        }
        const items = [];
        for (const id of plan.order) {
            const staged = id === job.root.manifest.id ? job.root : job.fetched[id];
            if (!staged)
                continue;
            const target = id === job.root.manifest.id ? job.rootTarget : _target(job, id);
            if (target.kind === "taken") {
                _abandon(job, target.problem);
                return;
            }
            items.push({ id: id, staged: staged, target: target });
        }
        job.ids = items.map(item => item.id);
        job.notes.push(...plan.blocking);
        _installItems(job, items, 0);
    }

    // A failure before anything moved in: every staging directory goes
    function _abandon(job, message) {
        if (!_alive(job))
            return;
        _rollback(job, () => _finish(job, false, message));
    }

    // ---- Installing ----

    // Each module's staged directory moved to its version directory (no link yet)
    function _installItems(job, items, index) {
        if (!_alive(job))
            return;
        phase = "installing";
        progress = null;
        if (index >= items.length) {
            _recordStaged(job, items);
            return;
        }
        const item = items[index];
        const manifest = item.staged.manifest;
        subject = String(manifest.name || item.id);
        const dir = ModuleInstallRules.versionDirectoryName(manifest.version, item.staged.commit, Date.now());
        const update = item.target.kind === "update";
        // A version the record keeps is the same files (its directory names the commit): taken
        // as it is; anything else of that name there is a leftover of the shell's and replaced
        const kept = update && (item.target.previousRecord?.versions ?? []).some(each => each.dir === dir);
        item.dir = dir;
        const lines = [];
        _run(["sh", "-c", "s=$1; v=$2; id=$3; dir=$4; mode=$5; umask 077; mkdir -p -- \"$v/$id\" || exit 1; "
              + "[ ! -L \"$v/$id\" ] || exit 1; d=$v/$id/$dir; [ ! -L \"$d\" ] || exit 1; "
              + "if [ -e \"$d\" ]; then if [ \"$mode\" = reuse ]; then rm -rf -- \"$s\"; echo existed; exit 0; fi; rm -rf -- \"$d\" || exit 1; fi; "
              + "mv -T -- \"$s\" \"$d\" || exit 1; echo moved",
              "sh", item.staged.dir, places.versions, item.id, dir, kept ? "reuse" : "replace"], {
            timeoutMs: stepTimeoutMs,
            onLine: (line, stream) => {
                if (stream === "stdout")
                    lines.push(line);
            },
            done: result => {
                if (!_alive(job))
                    return;
                const existed = lines.includes("existed");
                if (existed || lines.includes("moved")) {
                    job.staged = job.staged.filter(each => each !== item.staged.dir);
                    item.step = { id: item.id, kind: update ? "update" : "install", dir: dir, previousDir: item.target.previousDir,
                                  existed: existed, previousRecord: item.target.previousRecord ?? null, directory: "" };
                    job.done.push(item.step);
                }
                if (!result.ok) {
                    _rollback(job, () => _finish(job, false, item.id + ": could not be moved into place; nothing installed"));
                    return;
                }
                _installItems(job, items, index + 1);
            }
        });
    }

    // The record before any link moves: every new version listed, the active ones as they
    // were (a run cut off after this leaves versions the record names, never a module that
    // reads as placed by hand)
    function _recordStaged(job, items) {
        let modules = job.records.modules;
        const fetchedAt = new Date().toISOString();
        const rootId = job.root.manifest.id;
        for (const item of items) {
            const source = item.staged.source;
            modules = ModuleInstallRules.recordStaged(modules, item.id, {
                kind: source.kind, address: source.kind === "folder" ? source.folder : source.url, ref: source.ref,
                dir: item.dir, version: item.staged.manifest.version, commit: item.staged.commit, fetchedAt: fetchedAt,
                installedFor: item.id === rootId ? "" : rootId
            });
        }
        _writeRecord(job, modules, ok => {
            if (!ok) {
                _rollback(job, () => _finish(job, false, "the record of installed modules could not be written; nothing installed"));
                return;
            }
            job.recordWritten = true;
            job.records = { ok: true, modules: modules, dropped: [] };
            _linkItems(job, items, 0);
        });
    }

    // Each link moved onto its new version, providers first
    function _linkItems(job, items, index) {
        if (!_alive(job))
            return;
        if (index >= items.length) {
            _recordActive(job, items);
            return;
        }
        const item = items[index];
        _link(job, item.id, item.dir, (ok, directory) => {
            if (!ok) {
                _rollback(job, () => _finish(job, false, item.id + ": its link could not be made; nothing installed"));
                return;
            }
            item.step.directory = directory;
            _linkItems(job, items, index + 1);
        });
    }

    // Moves the link modules/<id> onto version `dir` in one rename. → done(ok, the version's
    // canonical directory — what the host loads it from)
    function _link(job, id, dir, done) {
        const lines = [];
        _run(["sh", "-c", "v=$1; id=$2; dir=$3; u=$4; { [ -d \"$v/$id/$dir\" ] && [ ! -L \"$v/$id\" ] && [ ! -L \"$v/$id/$dir\" ]; } || exit 1; "
              + "mkdir -p -- \"$u\" || exit 1; t=$u/.$id.link.$$; rm -f -- \"$t\"; ln -s -- \"$v/$id/$dir\" \"$t\" || exit 1; "
              + "mv -T -- \"$t\" \"$u/$id\" || { rm -f -- \"$t\"; exit 1; }; cd -P -- \"$v/$id/$dir\" && pwd",
              "sh", places.versions, id, dir, places.user], {
            timeoutMs: stepTimeoutMs,
            onLine: (line, stream) => {
                if (stream === "stdout")
                    lines.push(line);
            },
            done: result => {
                if (_alive(job))
                    done(result.ok, result.ok ? ModuleFileRules.canonicalPath(lines[lines.length - 1] ?? "") : "");
            }
        });
    }

    // Every link is in place: the record names the new versions active; the versions beyond
    // the kept ones go; then the load
    function _recordActive(job, items) {
        let modules = job.records.modules;
        const dropped = [];
        for (const item of items) {
            modules = ModuleInstallRules.recordSwitched(modules, item.id, item.dir) ?? modules;
            if (item.target.kind === "update") {
                const keep = ModuleUpdateRules.keepPlan(modules[item.id], { previousDir: item.target.previousDir });
                if (keep.ok && keep.delete.length > 0) {
                    modules = ModuleInstallRules.recordWithoutVersions(modules, item.id, keep.delete);
                    dropped.push(...keep.delete.map(dir => places.versions + "/" + item.id + "/" + dir));
                }
            }
        }
        _writeRecord(job, modules, ok => {
            if (!ok) {
                _rollback(job, () => _finish(job, false, "the record of installed modules could not be written; nothing installed"));
                return;
            }
            job.records = { ok: true, modules: modules, dropped: [] };
            const loadNext = () => {
                // Off before the load: they never start, even for a moment
                if (!job.enable)
                    for (const step of job.done)
                        if (step.kind === "install")
                            host.setEnabled(step.id, false);
                _reload(job, loaded => _afterStart(job, job.done, loaded, () => _turnOn(job, loaded)));
            };
            if (dropped.length === 0)
                loadNext();
            else
                _fileOps(job, dropped.map(path => ({ op: "tree", path: path })), problems => {
                    if (problems.length > 0)
                        console.warn("[Modules] older versions could not be deleted: " + problems.join("; "));
                    loadNext();
                });
        });
    }

    // The host's status of the module a step put in place — loaded from the version directory
    // this job made, nothing else of that id — or null
    function _statusAt(step) {
        return host.statuses.find(status => status.id === step.id && step.directory !== "" && status.directory === step.directory) ?? null;
    }

    // The new modules acknowledged and turned on ("Install and enable": the preview, or the
    // typed command, was the confirmation) — each only as loaded from its version directory;
    // updated ones keep their state
    function _turnOn(job, loaded) {
        const installed = job.done.filter(step => step.kind === "install");
        const updated = job.done.filter(step => step.kind === "update").map(step => step.id);
        if (job.enable && loaded) {
            for (const step of installed) {
                const status = _statusAt(step);
                if (!status) {
                    job.notes.push(step.id + ": not loaded from the version installed");
                    continue;
                }
                if (host.confirmations && (status.state === "unconfirmed" || status.state === "approval")) {
                    const why = host.confirm(step.id, step.directory);
                    if (why !== "")
                        job.notes.push(step.id + ": " + why);
                } else if (!status.enabled) {
                    host.setEnabled(step.id, true);
                }
            }
        }
        const parts = [];
        if (installed.length > 0)
            parts.push("installed " + installed.map(step => step.id).join(", ") + (job.enable ? "" : " (kept off)"));
        if (updated.length > 0)
            parts.push("updated " + updated.join(", "));
        _finish(job, true, (parts.join("; ") || "nothing to install") + _notesText(job));
    }

    function _notesText(job) {
        return job.notes.length > 0 ? " — " + job.notes.join("; ") : "";
    }

    // ---- After the load: back on a failed start ----

    // Each module this job moved to another version that did not start — as loaded from that
    // version's directory — goes back to the one before (relinked, the record's active
    // version back); then one more load
    function _afterStart(job, steps, loaded, next) {
        if (!_alive(job))
            return;
        const back = loaded ? steps.filter(step => ModuleInstallRules.backOnFailedStart(step, _statusAt(step))) : [];
        if (back.length === 0) {
            next();
            return;
        }
        job.back = (job.back ?? []).concat(back.map(step => step.id));
        const reasons = back.map(step => step.id + " " + step.dir + " did not start ("
                                 + ModuleInstallRules._plain(String((_statusAt(step)?.errors ?? [])[0] ?? "failed"), 160)
                                 + "): back to " + step.previousDir);
        const relinkAll = index => {
            if (index >= back.length) {
                let modules = job.records.modules;
                for (const step of back)
                    modules = ModuleInstallRules.recordSwitched(modules, step.id, step.previousDir) ?? modules;
                _writeRecord(job, modules, ok => {
                    job.records = ok ? { ok: true, modules: modules, dropped: [] } : job.records;
                    job.notes.push(...reasons);
                    if (!ok)
                        job.notes.push("the record of installed modules could not be written");
                    _reload(job, () => next());
                });
                return;
            }
            _link(job, back[index].id, back[index].previousDir, ok => {
                if (!ok)
                    reasons[index] += " — the link could not be moved back";
                relinkAll(index + 1);
            });
        };
        relinkAll(0);
    }

    // ---- Switch version ----

    function _switchTo(job, id, dir, previousDir, next) {
        _link(job, id, dir, (ok, directory) => {
            if (!ok) {
                _finish(job, false, id + ": the link could not be moved to " + dir);
                return;
            }
            let modules = ModuleInstallRules.recordSwitched(job.records.modules, id, dir);
            const keep = ModuleUpdateRules.keepPlan(modules[id], { previousDir: previousDir });
            const dropped = keep.ok ? keep.delete : [];
            modules = ModuleInstallRules.recordWithoutVersions(modules, id, dropped);
            _writeRecord(job, modules, written => {
                if (!written) {
                    // The link goes back: the record still names the version before
                    _link(job, id, previousDir, () => _finish(job, false, "the record of installed modules could not be written; " + id + " stays at " + previousDir));
                    return;
                }
                job.records = { ok: true, modules: modules, dropped: [] };
                if (dropped.length === 0) {
                    next(directory);
                    return;
                }
                _fileOps(job, dropped.map(each => ({ op: "tree", path: places.versions + "/" + id + "/" + each })), problems => {
                    if (problems.length > 0)
                        console.warn("[Modules] older versions could not be deleted: " + problems.join("; "));
                    next(directory);
                });
            });
        });
    }

    // ---- Remove ----

    function _removeWith(job, id, status) {
        const directory = status.directory;
        const found = ModuleInstallRules.sourceOf(directory, ModuleInstallRules.linkFor(directory, job.sources.entries), job.sources.roots, job.records);
        const known = host.statuses.filter(each => each.state !== "duplicate" && each.shadowedBy === "").map(each => ({
            id: each.id, name: each.name, uses: host.manifestOf(each.directory)?.uses ?? null, state: each.state,
            source: each.source, installedFor: each.installedFor, directory: each.directory, version: each.version
        }));
        const dependents = ModuleDependencyRules.dependents(id, known);
        const nameOf = other => known.find(each => each.id === other)?.name || other;
        const offered = ModuleDependencyRules.orphans(id, known).map(each => each.id);
        const alsoRemove = job.alsoRemove.filter(other => offered.includes(other)).map(other => {
            const module = known.find(each => each.id === other);
            return {
                found: ModuleInstallRules.sourceOf(module.directory, ModuleInstallRules.linkFor(module.directory, job.sources.entries), job.sources.roots, job.records),
                module: { id: other, name: module.name, version: module.version },
                record: job.records.ok && ModuleRules.has(job.records.modules, other) ? job.records.modules[other] : null
            };
        });
        const plan = ModuleInstallRules.removalPlan(found, { id: id, name: status.name, version: status.version },
                                                    job.records.ok && ModuleRules.has(job.records.modules, id) ? job.records.modules[id] : null, {
            withData: job.withData, dataHome: dataHome, configHome: configHome, home: home,
            dependents: { hard: dependents.hard.map(nameOf), soft: dependents.soft.map(nameOf) }, alsoRemove: alsoRemove
        });
        if (!plan.ok) {
            _finish(job, false, plan.reason);
            return;
        }
        const plans = [plan].concat(plan.also.filter(each => each.ok));
        const steps = [].concat(...plans.map(each => each.steps));
        const fileSteps = steps.filter(step => step.op === "unlink" || step.op === "deleteTree")
            .map(step => ({ op: step.op === "unlink" ? "unlink" : "tree", path: step.path }));
        for (const step of steps)
            if (step.op === "disable")
                host.setEnabled(step.id, false);
        const left = offered.filter(other => !job.alsoRemove.includes(other));
        _fileOps(job, fileSteps, problems => {
            const dropRecords = steps.filter(step => step.op === "dropRecord").map(step => step.id);
            const afterRecord = written => {
                for (const step of steps) {
                    if (step.op === "dropAcknowledgement")
                        host.dropAcknowledgement(step.id);
                    else if (step.op === "deleteSettings")
                        Profiles.deleteSettings(step.prefix);
                }
                job.ids = plans.map(each => each.subject.id);
                if (!written)
                    problems.push("the record of installed modules could not be written");
                _reload(job, () => {
                    const words = "removed " + job.ids.join(", ") + (job.withData ? " with its data" : "")
                        + (left.length > 0 ? " — also installed for it, used by nothing else: " + left.map(nameOf).join(", ") : "")
                        + (dependents.hard.length > 0 ? " — these stop working: " + dependents.hard.map(nameOf).join(", ") : "");
                    _finish(job, problems.length === 0, problems.length === 0 ? words : words + "; " + problems.join("; "));
                });
            };
            if (dropRecords.length === 0 || job.sources.record.state !== "ok") {
                afterRecord(true);
                return;
            }
            // Spliced from the text as read: only the removed entries go — what this shell
            // does not read (an entry it drops, a field it does not know) stays as it was
            const text = ModuleInstallRules.recordTextWithout(job.sources.record.text, dropRecords);
            if (text === null) {
                afterRecord(false);
                return;
            }
            _writeRecordText(job, text, afterRecord);
        });
    }

    // ---- Taking back a run ----

    // ModuleDependencyRules.rollbackPlan on what this job moved in and staged, carried out:
    // links moved back, then links removed, versions it made and staging deleted, then — when
    // this job wrote the record — the record's entries dropped or put back as they were
    function _rollback(job, next) {
        const plan = ModuleDependencyRules.rollbackPlan({ stagingRoot: places.staging, staged: job.staged, done: job.done });
        for (const problem of plan.problems)
            console.warn("[Modules] taking back the install: " + problem);
        const ops = [];
        const relinks = [];
        for (const action of plan.actions) {
            if (action.action === "unlink")
                ops.push({ op: "unlink", path: places.user + "/" + action.id });
            else if (action.action === "deleteVersion")
                ops.push({ op: "tree", path: places.versions + "/" + action.id + "/" + action.dir });
            else if (action.action === "deleteStaging")
                ops.push({ op: "tree", path: action.directory });
            else if (action.action === "relink")
                relinks.push(action);
        }
        // A new module's versions directory, made by this run, goes when nothing is left in it
        for (const action of plan.actions)
            if (action.action === "unlink")
                ops.push({ op: "prune", path: places.versions + "/" + action.id });
        let modules = job.records?.modules ?? {};
        for (const action of plan.actions) {
            if (action.action === "dropRecord")
                modules = ModuleInstallRules.recordWithout(modules, action.id);
            else if (action.action === "restoreRecord")
                modules = ModuleInstallRules.recordRestored(modules, action.id, action.previous);
        }
        const restoreRecord = job.recordWritten === true;
        job.done = [];
        job.staged = [];
        job.recordWritten = false;
        const relinkAll = index => {
            if (index >= relinks.length) {
                _fileOps(job, ops, problems => {
                    if (problems.length > 0)
                        console.warn("[Modules] taking back the install left: " + problems.join("; "));
                    if (!restoreRecord) {
                        next();
                        return;
                    }
                    _writeRecord(job, modules, ok => {
                        if (ok)
                            job.records = { ok: true, modules: modules, dropped: [] };
                        else
                            console.warn("[Modules] taking back the install: the record of installed modules could not be put back");
                        next();
                    });
                });
                return;
            }
            _link(job, relinks[index].id, relinks[index].dir, ok => {
                if (!ok)
                    console.warn("[Modules] taking back the install: " + relinks[index].id + " could not be linked back to " + relinks[index].dir);
                relinkAll(index + 1);
            });
        };
        relinkAll(0);
    }

    // ---- Files ----

    // Deletes (`tree`: a directory, never through a link), unlinks (`unlink`: a link only) or
    // removes when empty (`prune`) each path, where ModuleInstallRules.deletionTarget allows
    // it; nothing on the way below the shell's place may be a link. → done([problems])
    function _fileOps(job, ops, done) {
        const problems = [];
        const args = [];
        for (const each of ops) {
            const target = ModuleInstallRules.deletionTarget(each.path, places);
            if (!target.ok)
                problems.push(ModuleInstallRules._plain(each.path) + ": " + target.problem);
            else
                args.push(each.op, target.root, target.relative);
        }
        if (args.length === 0) {
            Qt.callLater(() => {
                if (_alive(job))
                    done(problems);
            });
            return;
        }
        const lines = [];
        _run(["sh", "-c", "while [ $# -ge 3 ]; do op=$1; r=$2; rel=$3; shift 3; p=$r/$rel; "
              + "case $rel in */*) if [ -L \"$r/${rel%%/*}\" ]; then printf 'fail\\t%s\\tleads through a link\\n' \"$p\"; continue; fi ;; esac; "
              + "if [ \"$op\" = prune ]; then { [ -d \"$p\" ] && [ ! -L \"$p\" ] && rmdir -- \"$p\" 2>/dev/null; } || true; "
              + "elif [ \"$op\" = unlink ]; then "
              + "if [ -L \"$p\" ]; then rm -f -- \"$p\" || { printf 'fail\\t%s\\tnot removed\\n' \"$p\"; continue; }; "
              + "elif [ -e \"$p\" ]; then printf 'fail\\t%s\\tnot a link\\n' \"$p\"; continue; fi; "
              + "else "
              + "if [ -L \"$p\" ]; then printf 'fail\\t%s\\tis a link\\n' \"$p\"; continue; "
              + "elif [ -d \"$p\" ]; then rm -rf -- \"$p\" || { printf 'fail\\t%s\\tnot deleted\\n' \"$p\"; continue; }; "
              + "elif [ -e \"$p\" ]; then printf 'fail\\t%s\\tnot a directory\\n' \"$p\"; continue; fi; "
              + "fi; printf 'ok\\t%s\\n' \"$p\"; done",
              "sh"].concat(args), {
            timeoutMs: stepTimeoutMs,
            onLine: (line, stream) => {
                if (stream === "stdout")
                    lines.push(line);
            },
            done: result => {
                if (!_alive(job))
                    return;
                for (const line of lines) {
                    const fields = line.split("\t");
                    if (fields[0] === "fail")
                        problems.push(ModuleInstallRules._plain(fields[1] ?? "") + ": " + ModuleInstallRules._plain(fields[2] ?? ""));
                }
                const answered = lines.filter(line => line.startsWith("ok\t") || line.startsWith("fail\t")).length;
                if (answered < args.length / 3)
                    problems.push((args.length / 3 - answered) + " " + (args.length / 3 - answered === 1 ? "path was" : "paths were") + " not handled"
                                  + (result.timedOut ? " in time" : ""));
                done(problems);
            }
        });
    }

    // The record written by a temporary file and a rename. → done(ok)
    function _writeRecord(job, modules, done) {
        _writeRecordText(job, ModuleInstallRules.recordText(modules), done);
    }

    function _writeRecordText(job, text, done) {
        const chunks = ModuleInstallRules.recordChunks(text);
        if (chunks === null || places.record === "") {
            Qt.callLater(() => {
                if (_alive(job))
                    done(false);
            });
            return;
        }
        _run(["sh", "-c", "f=$1; shift; umask 077; mkdir -p -- \"${f%/*}\" || exit 1; t=$(mktemp -- \"$f.XXXXXX\") || exit 1; "
              + "if printf '%s' \"$@\" > \"$t\" && mv -f -- \"$t\" \"$f\"; then exit 0; fi; rm -f -- \"$t\"; exit 1",
              "sh", places.record].concat(chunks), {
            timeoutMs: stepTimeoutMs,
            done: result => {
                if (_alive(job))
                    done(result.ok);
            }
        });
    }

    // ---- The load ----

    // The host searches again and loads what it finds; → next(loaded) once that load has
    // settled — false when there is no search here, it failed, or it took longer than
    // loadTimeoutMs (said in the job's notes)
    function _reload(job, next) {
        if (!_alive(job))
            return;
        phase = "loading";
        const before = host.loadCount;
        const why = host.rediscover();
        if (why !== "") {
            job.notes.push("loads at the next start (" + why + ")");
            Qt.callLater(() => {
                if (_alive(job))
                    next(false);
            });
            return;
        }
        _waiting = { job: job, before: before, deadline: Date.now() + loadTimeoutMs, next: next };
        _loadWatch.start();
    }

    property var _waiting: null

    Timer {
        id: _loadWatch
        interval: 50
        repeat: true
        onTriggered: {
            const waiting = root._waiting;
            if (!waiting || !root._alive(waiting.job)) {
                stop();
                root._waiting = null;
                return;
            }
            const host = root.host;
            let loaded = null;
            if (host.loadCount > waiting.before && !host.discovering && host.settled)
                loaded = true;
            else if (host.loadCount === waiting.before && !host.discovering) {
                waiting.job.notes.push("the modules could not be searched again: they load at the next start");
                loaded = false;
            } else if (Date.now() > waiting.deadline) {
                waiting.job.notes.push("the modules did not load within " + Math.round(root.loadTimeoutMs / 1000) + " s");
                loaded = false;
            }
            if (loaded === null)
                return;
            stop();
            root._waiting = null;
            waiting.next(loaded);
        }
    }

    // ---- Commands ----

    function _run(argv, options) {
        return _runner.start(argv, Object.assign({ killAfterMs: 1000 }, options, {
            environment: Object.assign({}, options?.environment ?? {}),
            done: result => {
                if (result.error !== "")
                    console.warn("[Modules] an installer step could not be run: " + result.error);
                options.done(result);
            }
        }));
    }

    CommandRunner {
        id: _runner
        environment: root.environment
    }
}
