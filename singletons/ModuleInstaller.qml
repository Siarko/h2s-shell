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
// <dataHome>/h2s-shell/module-staging (git's progress in `progress`; a download larger than
// ModuleInstallRules.maxDownloadBytes is stopped, a folder or a download measured again once
// there; a link out of the module refuses it); "verifying" — the host's own file check and
// manifest rules on the staged directory (ModuleHost.checkDirectory), the id free or the
// shell's own (ModuleInstallRules.installTarget: a folder or link placed by hand is never
// replaced), then the dependency chain (ModuleDependencyRules.plan: each missing dependency
// with a source downloaded and checked the same way, until nothing is left to fetch; one
// that cannot be had stops the install unless `anyway`); "installing" — each module of the
// chain in dependency order: its staged directory renamed to
// module-versions/<id>/<version>-<commit7> and the link modules/<id> moved onto it in one
// rename, then the record (module-sources.json) written once, by a temporary file and a
// rename; a step that fails takes back the ones before (ModuleDependencyRules.rollbackPlan)
// so the user root is as it was. Then the host searches again and loads (rediscover()); an
// updated module that does not start goes back to its version before
// (ModuleInstallRules.backOnFailedStart). With `enable` (the default) the new modules are
// acknowledged and turned on — the preview, or a typed IPC command, was the user's
// confirmation; without, they stay off.
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
        const result = { ok: ok, action: job.action, message: text, ids: job.ids.slice() };
        _job = null;
        phase = "";
        subject = "";
        progress = null;
        lastResult = result;
        if (ok)
            console.info("[Modules] " + text);
        else
            console.warn("[Modules] " + job.action + " failed: " + text);
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
            job.rootTarget = ModuleInstallRules.installTarget(staged.manifest.id, job.sources, job.records);
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
                _switchTo(job, id, plan.dir, plan.previousDir, () => {
                    const step = { id: id, kind: "switch", dir: plan.dir, previousDir: plan.previousDir };
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

    // Empties the staging place: what an earlier run left there (the shell's start)
    function cleanStaging() {
        if (_job !== null || places.staging === "")
            return;
        _run(["sh", "-c", "d=$1; { [ -d \"$d\" ] && [ ! -L \"$d\" ]; } || exit 0; "
              + "for e in \"$d\"/* \"$d\"/.[!.]*; do { [ -e \"$e\" ] || [ -L \"$e\" ]; } || continue; rm -rf -- \"$e\"; done",
              "sh", places.staging], { timeoutMs: stepTimeoutMs, done: result => {
                  if (!result.ok)
                      console.warn("[Modules] the staging place could not be emptied");
              } });
    }

    // ---- Reading what is there ----

    // The installer's own look at the user root, the versions and the record (the host's
    // source check, ModuleInstallRules.sourceCheckScript) → job.sources, job.records. A
    // record that cannot be read refuses anything that would write it, except a removal
    // (`forRemoval`), which then treats the module as placed by hand
    function _readSources(job, next, forRemoval) {
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
            done: result => {
                if (!_alive(job))
                    return;
                job.sources = ModuleInstallRules.parseSourceCheck(lines);
                if (!job.sources.complete) {
                    _finish(job, false, "your modules folder could not be read");
                    return;
                }
                const record = job.sources.record;
                job.records = record.state === "missing" ? { ok: true, modules: {}, dropped: [] }
                            : record.state === "ok" ? ModuleInstallRules.parseRecord(record.text) : { ok: false, modules: {}, dropped: [] };
                if (!forRemoval && (!job.records.ok || job.records.dropped.length > 0)) {
                    _finish(job, false, "the record of installed modules (" + places.record + ") cannot be read: nothing is changed");
                    return;
                }
                next();
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
        _run(["sh", "-c", "[ -d \"$1\" ] || { echo 'not a folder' >&2; exit 1; }; cp -R --no-dereference -- \"$1/.\" \"$2/\" && rm -rf -- \"$2/.git\"",
              "sh", folder, dir], {
            timeoutMs: downloadTimeoutMs,
            done: result => {
                if (!_alive(job))
                    return;
                if (!result.ok) {
                    _abandon(job, label + ": the folder could not be copied" + (result.timedOut ? " in time" : ""));
                    return;
                }
                next();
            }
        });
    }

    // The git commands of a download, one after the other, then the commit it got; .git goes
    // (the version directory holds the module's files only)
    function _clone(job, label, address, dir, next) {
        const commands = ModuleInstallRules.downloadCommands(address, dir);
        if (!commands.ok) {
            _abandon(job, label + ": " + commands.problem);
            return;
        }
        const runNext = index => {
            if (index >= commands.commands.length) {
                _commitOf(job, label, dir, next);
                return;
            }
            const command = commands.commands[index];
            let lastLine = "";
            let tooLarge = false;
            let handle = null;
            handle = _run(command.argv, {
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
                    if (read.bytes !== null && read.bytes > ModuleInstallRules.maxDownloadBytes && !tooLarge) {
                        tooLarge = true;
                        handle?.cancel();
                    }
                },
                done: result => {
                    if (!_alive(job))
                        return;
                    if (!result.ok || tooLarge) {
                        _abandon(job, label + ": download failed — "
                                 + ModuleInstallRules.downloadProblem(result, lastLine, { timeoutMs: downloadTimeoutMs, tooLarge: tooLarge }));
                        return;
                    }
                    runNext(index + 1);
                }
            });
        };
        runNext(0);
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
                    : ModuleInstallRules.stagedSizeProblem(size ? size.slice(5) : "")
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
            const target = id === job.root.manifest.id ? job.rootTarget : ModuleInstallRules.installTarget(id, job.sources, job.records);
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

    function _installItems(job, items, index) {
        if (!_alive(job))
            return;
        phase = "installing";
        progress = null;
        if (index >= items.length) {
            _recordInstall(job, items);
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
                    job.done.push({ id: item.id, kind: update ? "update" : "install", dir: dir, previousDir: item.target.previousDir,
                                    existed: existed, previousRecord: item.target.previousRecord ?? null });
                }
                if (!result.ok) {
                    _rollback(job, () => _finish(job, false, item.id + ": could not be moved into place; nothing installed"));
                    return;
                }
                _link(job, item.id, dir, ok => {
                    if (!ok) {
                        _rollback(job, () => _finish(job, false, item.id + ": its link could not be made; nothing installed"));
                        return;
                    }
                    _installItems(job, items, index + 1);
                });
            }
        });
    }

    // Moves the link modules/<id> onto version `dir` in one rename. → done(ok)
    function _link(job, id, dir, done) {
        _run(["sh", "-c", "v=$1; id=$2; dir=$3; u=$4; { [ -d \"$v/$id/$dir\" ] && [ ! -L \"$v/$id\" ] && [ ! -L \"$v/$id/$dir\" ]; } || exit 1; "
              + "mkdir -p -- \"$u\" || exit 1; t=$u/.$id.link.$$; rm -f -- \"$t\"; ln -s -- \"$v/$id/$dir\" \"$t\" || exit 1; "
              + "mv -T -- \"$t\" \"$u/$id\" || { rm -f -- \"$t\"; exit 1; }",
              "sh", places.versions, id, dir, places.user], {
            timeoutMs: stepTimeoutMs,
            done: result => {
                if (_alive(job))
                    done(result.ok);
            }
        });
    }

    // Every module is in place: the record, written once; the versions beyond the kept ones
    // go; then the load
    function _recordInstall(job, items) {
        let modules = job.records.modules;
        const fetchedAt = new Date().toISOString();
        const rootId = job.root.manifest.id;
        const dropped = [];
        for (const item of items) {
            const source = item.staged.source;
            modules = ModuleInstallRules.recordInstalled(modules, item.id, {
                kind: source.kind, address: source.kind === "folder" ? source.folder : source.url, ref: source.ref,
                dir: item.dir, version: item.staged.manifest.version, commit: item.staged.commit, fetchedAt: fetchedAt,
                installedFor: item.id === rootId ? "" : rootId
            });
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

    // The new modules acknowledged and turned on ("Install and enable": the preview, or the
    // typed command, was the confirmation); updated ones keep their state
    function _turnOn(job, loaded) {
        const installed = job.done.filter(step => step.kind === "install").map(step => step.id);
        const updated = job.done.filter(step => step.kind === "update").map(step => step.id);
        if (job.enable && loaded) {
            for (const id of installed) {
                const status = host.status(id);
                if (!status)
                    continue;
                if (host.confirmations && (status.state === "unconfirmed" || status.state === "approval")) {
                    const why = host.confirm(id, status.directory);
                    if (why !== "")
                        job.notes.push(id + ": " + why);
                } else if (!status.enabled) {
                    host.setEnabled(id, true);
                }
            }
        }
        const parts = [];
        if (installed.length > 0)
            parts.push("installed " + installed.join(", ") + (job.enable ? "" : " (kept off)"));
        if (updated.length > 0)
            parts.push("updated " + updated.join(", "));
        _finish(job, true, (parts.join("; ") || "nothing to install") + _notesText(job));
    }

    function _notesText(job) {
        return job.notes.length > 0 ? " — " + job.notes.join("; ") : "";
    }

    // ---- After the load: back on a failed start ----

    // Each module this job moved to another version that did not start goes back to the one
    // before (relinked, the record's active version back); then one more load
    function _afterStart(job, steps, loaded, next) {
        if (!_alive(job))
            return;
        const back = loaded ? steps.filter(step => ModuleInstallRules.backOnFailedStart(step, host.status(step.id))) : [];
        if (back.length === 0) {
            next();
            return;
        }
        const reasons = back.map(step => step.id + " " + step.dir + " did not start ("
                                 + ModuleInstallRules._plain(String((host.status(step.id)?.errors ?? [])[0] ?? "failed"), 160)
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
        _link(job, id, dir, ok => {
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
                    next();
                    return;
                }
                _fileOps(job, dropped.map(each => ({ op: "tree", path: places.versions + "/" + id + "/" + each })), problems => {
                    if (problems.length > 0)
                        console.warn("[Modules] older versions could not be deleted: " + problems.join("; "));
                    next();
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
            if (dropRecords.length === 0 || !job.records.ok) {
                afterRecord(true);
                return;
            }
            let modules = job.records.modules;
            for (const other of dropRecords)
                modules = ModuleInstallRules.recordWithout(modules, other);
            _writeRecord(job, modules, afterRecord);
        });
    }

    // ---- Taking back a run ----

    // ModuleDependencyRules.rollbackPlan on what this job moved in and staged, carried out:
    // links removed or moved back, versions it made deleted, staging deleted. The record is
    // written only after every module is in place, so it never needs taking back here
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
        job.done = [];
        job.staged = [];
        const relinkAll = index => {
            if (index >= relinks.length) {
                _fileOps(job, ops, problems => {
                    if (problems.length > 0)
                        console.warn("[Modules] taking back the install left: " + problems.join("; "));
                    next();
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
        const chunks = ModuleInstallRules.recordChunks(ModuleInstallRules.recordText(modules));
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
