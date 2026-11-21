import QtQuick
import Quickshell
import qs.singletons.io

// A module's configuration backups on disk (notes/plans/modules-management.md §6.10), for
// the installer, which takes one before every switch of a module's version and before a
// restore, inside its own job: `take` writes one, `list` reads a module's, `readSettings`
// and `writeBack` carry out a restore's file part. No job of its own and no decision: what
// a backup holds is ModuleUpdateRules.backupPlan, which stay backupKeepPlan, the rest
// ModuleBackupRules.
//
// <dataHome>/h2s-shell/module-backups/<id>/<version>-<YYYYMMDD-HHMMSS>/ holds settings.json
// (the module's `mod.<id>.*` values in every profile and the pinned globals, as stored),
// store.json (its store's file), data/<path> (only the paths its manifest names) and
// meta.json. It is written in a staging directory beside it (".incoming-…") and renamed in.
// Links are never followed: a store that is a link, and a named path whose resolved place is
// not inside the module's data directory, are left out (said in meta.json's `refused`); a
// link inside a named directory is copied as a link. Writing back goes by a temporary name
// and a rename. A failed read is never a backup, and never written over anything.
Scope {
    id: root

    property string dataHome: ""
    property string configHome: ""
    property var environment: ({})
    property int stepTimeoutMs: 30000

    readonly property var places: ModuleInstallRules.paths(dataHome, configHome)

    // What the last listing found, by id: ModuleBackupRules.listing's { ok, backups, unknown }
    property var lists: ({})
    // Every module's backups have been read once: a module missing from `lists` has none
    property bool allRead: false

    property int _asked: 0
    // id → the token of the listing whose answer `lists` holds for it: an older answer, of
    // one module or of all, never replaces a newer one
    property var _applied: ({})
    property var _warned: []    // "<id>\t<path>\t<why>" already said: each said once a run

    // ---- Taking one ----

    // A backup of module `id` now. `manifest`: its active version's (what data paths it
    // names); `options`: { version, commit, reason, protect: [backup names kept whatever
    // their age] }. The older ones beyond the kept number go once it is in.
    // → done({ ok, problem, name, meta })
    function take(id, manifest, options, done) {
        const failed = problem => Qt.callLater(() => done({ ok: false, problem: problem, name: "", meta: null }));
        const plan = ModuleUpdateRules.backupPlan(id, manifest, Object.assign({}, options, { dataHome: dataHome, configHome: configHome, nowMs: Date.now() }));
        if (!plan.ok) {
            failed(plan.problem);
            return;
        }
        const snapshot = Profiles.moduleSettings("mod." + id + ".");
        if (snapshot === null) {
            failed("your settings could not be read");
            return;
        }
        const parts = ModuleBackupRules.chunks(ModuleBackupRules.settingsText(snapshot));
        if (parts === null) {
            failed("its settings are too large");
            return;
        }
        const store = plan.items.find(item => item.what === "store");
        const paths = plan.items.filter(item => item.what === "data").map(item => item.to.slice("data/".length));
        const folder = places.backups + "/" + id;
        const lines = [];
        _run(["sh", "-c", root._copyScript, "sh", plan.staging, folder, store.from, places.data + "/" + id, String(parts.length)].concat(parts, paths), {
            onLine: (line, stream) => {
                if (stream === "stdout")
                    lines.push(line);
            },
            done: result => {
                const outcome = ModuleBackupRules.copyOutcome(lines, paths);
                const meta = result.ok ? ModuleBackupRules.takenMeta(plan, outcome) : null;
                if (meta === null) {
                    _drop(plan.staging, () => done({ ok: false, problem: "its files could not be copied", name: "", meta: null }));
                    return;
                }
                const named = [];
                _run(["sh", "-c", root._finishScript, "sh", plan.staging, folder, plan.name, JSON.stringify(meta)], {
                    onLine: (line, stream) => {
                        if (stream === "stdout" && line.startsWith("name\t"))
                            named.push(line.slice(5));
                    },
                    done: finished => {
                        if (!finished.ok || named.length !== 1) {
                            _drop(plan.staging, () => done({ ok: false, problem: "it could not be moved into place", name: "", meta: null }));
                            return;
                        }
                        for (const each of outcome.refused) {
                            const key = id + "\t" + each.path + "\t" + each.why;
                            if (!_warned.includes(key)) {
                                _warned = _warned.concat([key]).slice(-200);
                                console.warn("[Modules] " + id + ": left out of its backup: " + each.path + " (" + each.why + ")");
                            }
                        }
                        // The new one is never pruned at once (others may carry a later time);
                        // gone anyway, or the list unreadable: no backup to rely on
                        _prune(id, (options?.protect ?? []).concat([named[0]]), listed => {
                            if (listed.ok && listed.backups.some(each => each.name === named[0]))
                                done({ ok: true, problem: "", name: named[0], meta: meta });
                            else
                                done({ ok: false, problem: "it could not be read back", name: "", meta: null });
                        });
                    }
                });
            }
        });
    }

    // The staging directory, settings.json (its chunks), the store's file (never through a
    // link), each named path whose resolved place is inside the data directory (links in
    // it copied as links), then "done"
    readonly property string _copyScript: "s=$1; b=$2; st=$3; d=$4; n=$5; shift 5; umask 077; "
        + "case $s in \"$b\"/.incoming-*) ;; *) exit 1 ;; esac; "
        + "mkdir -p -- \"$b\" || exit 1; [ ! -L \"${b%/*}\" ] && [ ! -L \"$b\" ] || exit 1; "
        + "[ -L \"$s\" ] && exit 1; rm -rf -- \"$s\"; mkdir -- \"$s\" || exit 1; "
        + ": > \"$s/settings.json\" || exit 1; i=0; while [ \"$i\" -lt \"$n\" ]; do printf '%s' \"$1\" >> \"$s/settings.json\" || exit 1; shift; i=$((i+1)); done; "
        + "if [ -L \"$st\" ]; then printf 'store\\trefused\\tis a link\\n'; "
        + "elif [ -f \"$st\" ]; then cp -P --preserve=mode,timestamps -- \"$st\" \"$s/store.json\" || exit 1; printf 'store\\tok\\n'; "
        + "elif [ -e \"$st\" ]; then printf 'store\\trefused\\tnot a file\\n'; else printf 'store\\tabsent\\n'; fi; "
        + "base=; if [ -d \"$d\" ]; then base=$(realpath -e -- \"$d\") || exit 1; fi; "
        + "for rel; do p=$d/$rel; "
        + "if [ ! -e \"$p\" ] && [ ! -L \"$p\" ]; then printf 'data\\tabsent\\t%s\\n' \"$rel\"; continue; fi; "
        + "r=$(realpath -e -- \"$p\" 2>/dev/null) || { printf 'data\\trefused\\t%s\\tleads nowhere\\n' \"$rel\"; continue; }; "
        + "case $r in \"$base\"/?*) [ -n \"$base\" ] || { printf 'data\\trefused\\t%s\\tleads outside its data directory\\n' \"$rel\"; continue; } ;; "
        + "*) printf 'data\\trefused\\t%s\\tleads outside its data directory\\n' \"$rel\"; continue ;; esac; "
        + "q=$(realpath -e -- \"${p%/*}\") || exit 1; case $q in \"$base\"|\"$base\"/*) ;; *) printf 'data\\trefused\\t%s\\tleads outside its data directory\\n' \"$rel\"; continue ;; esac; "
        + "case $rel in */*) mkdir -p -- \"$s/data/${rel%/*}\" || exit 1 ;; *) mkdir -p -- \"$s/data\" || exit 1 ;; esac; "
        + "cp -a -P -- \"$p\" \"$s/data/$rel\" || exit 1; printf 'data\\tok\\t%s\\n' \"$rel\"; done; echo done"

    // meta.json written in the staging directory, which is then renamed in under the
    // backup's name ("-2" … after it when a backup of that second is there)
    readonly property string _finishScript: "s=$1; b=$2; n=$3; m=$4; umask 077; "
        + "[ -d \"$s\" ] && [ ! -L \"$s\" ] && [ ! -L \"$b\" ] || exit 1; "
        + "t=$(mktemp -- \"$s/.meta.XXXXXX\") || exit 1; printf '%s' \"$m\" > \"$t\" && mv -fT -- \"$t\" \"$s/meta.json\" || { rm -f -- \"$t\"; exit 1; }; "
        + "for k in '' -2 -3 -4 -5 -6 -7 -8 -9; do { [ -e \"$b/$n$k\" ] || [ -L \"$b/$n$k\" ]; } && continue; "
        + "mv -T -- \"$s\" \"$b/$n$k\" && { printf 'name\\t%s\\n' \"$n$k\"; exit 0; }; done; exit 1"

    function _drop(staging, next) {
        _run(["sh", "-c", "s=$1; [ -L \"$s\" ] || rm -rf -- \"$s\"", "sh", staging], { done: () => next() });
    }

    // The backups beyond the newest kept ones deleted (ModuleBackupRules.keepPlan: what
    // cannot be read, staging leftovers and `protect` are left alone), the list read again.
    // → next(the listing as it is after)
    function _prune(id, protect, next) {
        list(id, listed => {
            if (!listed.ok) {
                next(listed);
                return;
            }
            const plan = ModuleBackupRules.keepPlan(listed.backups.map(each => ({ dir: each.name, takenAt: each.takenAt })), protect);
            if (plan.delete.length === 0) {
                next(listed);
                return;
            }
            _run(["sh", "-c", "b=$1; shift; [ -L \"$b\" ] && exit 1; for n; do case $n in ''|.*|*/*) continue ;; esac; "
                  + "[ -d \"$b/$n\" ] && [ ! -L \"$b/$n\" ] && rm -rf -- \"$b/$n\"; done; true",
                  "sh", places.backups + "/" + id].concat(plan.delete), {
                done: result => {
                    if (!result.ok)
                        console.warn("[Modules] " + id + ": older backups could not be deleted");
                    list(id, after => next(after));
                }
            });
        });
    }

    // ---- Reading ----

    // Module `id`'s backups ("": every module's, into `lists`). → done(ModuleBackupRules.listing's
    // { ok, backups, unknown }) — for "", done(lists)
    function list(id, done) {
        const token = ++_asked;
        if (id !== "" && !ModuleManifestRules.validId(id)) {
            Qt.callLater(() => done({ ok: false, backups: [], unknown: [] }));
            return;
        }
        if (places.backups === "") {
            Qt.callLater(() => done({ ok: false, backups: [], unknown: [] }));
            return;
        }
        const lines = [];
        _run(["sh", "-c", root._listScript, "sh", places.backups, id, String(ModuleBackupRules.maxMetaBytes)], {
            onLine: (line, stream) => {
                if (stream === "stdout")
                    lines.push(line);
            },
            done: result => {
                const ok = result.ok && lines[lines.length - 1] === "done";
                const rows = ModuleBackupRules.listingRows(lines);
                if (id !== "") {
                    const listed = ModuleBackupRules.listing(id, rows[id] ?? [], ok);
                    if ((_applied[id] ?? 0) < token) {
                        lists = Object.assign({}, lists, { [id]: listed });
                        _applied = Object.assign({}, _applied, { [id]: token });
                    }
                    done(listed);
                    return;
                }
                if (ok) {
                    const merged = Object.assign({}, lists);
                    const applied = Object.assign({}, _applied);
                    for (const each of Object.keys(rows).concat(Object.keys(lists))) {
                        if ((applied[each] ?? 0) >= token)
                            continue;
                        applied[each] = token;
                        if (rows[each])
                            merged[each] = ModuleBackupRules.listing(each, rows[each], true);
                        else
                            delete merged[each];
                    }
                    lists = merged;
                    _applied = applied;
                    allRead = true;
                }
                done(lists);
            }
        });
    }

    // Reads `lists` again (id "" — every module's) for the views and `modules backups`
    function refresh(id) {
        list(typeof id === "string" ? id : "", () => {});
    }

    // Each backup directory of module `id` (or of every module): "B\t<id>\t<name>\t<kind>\t<meta,
    // on one line>", "X\t<id>" for a name that is not plain, then "done"
    readonly property string _listScript: "r=$1; one=$2; max=$3; [ -L \"$r\" ] && exit 1; [ -d \"$r\" ] || { echo done; exit 0; }; "
        + "for m in \"$r\"/*; do [ -e \"$m\" ] || [ -L \"$m\" ] || continue; id=${m##*/}; "
        + "[ -n \"$one\" ] && [ \"$id\" != \"$one\" ] && continue; [ -d \"$m\" ] && [ ! -L \"$m\" ] || continue; "
        + "for e in \"$m\"/* \"$m\"/.[!.]*; do [ -e \"$e\" ] || [ -L \"$e\" ] || continue; n=${e##*/}; "
        + "case $n in *[!A-Za-z0-9._+-]*) printf 'X\\t%s\\n' \"$id\"; continue ;; esac; "
        + "k=f; [ -L \"$e\" ] && k=l; [ -d \"$e\" ] && [ ! -L \"$e\" ] && k=d; meta=; "
        + "if [ \"$k\" = d ] && [ -f \"$e/meta.json\" ] && [ ! -L \"$e/meta.json\" ]; then meta=$(head -c \"$max\" -- \"$e/meta.json\" | tr '\\n\\t' '  ') || meta=; fi; "
        + "printf 'B\\t%s\\t%s\\t%s\\t%s\\n' \"$id\" \"$n\" \"$k\" \"$meta\"; done; done; echo done"

    // Backup `name`'s settings.json, read. → done(ModuleBackupRules.parseSettings' result)
    function readSettings(id, name, done) {
        if (!ModuleManifestRules.validId(id) || !ModuleBackupRules.validName(name) || places.backups === "") {
            Qt.callLater(() => done({ ok: false, problem: "not a backup", profiles: [], globals: {} }));
            return;
        }
        _run(["sh", "-c", "f=$1/$2/$3/settings.json; [ ! -L \"$1/$2\" ] && [ ! -L \"$1/$2/$3\" ] && [ -f \"$f\" ] && [ ! -L \"$f\" ] || exit 1; "
              + "[ \"$(wc -c < \"$f\")\" -le \"$4\" ] || exit 1; cat -- \"$f\"",
              "sh", places.backups, id, name, String(ModuleBackupRules.maxSettingsBytes)], {
            done: result => done(result.ok && !result.truncated ? ModuleBackupRules.parseSettings(result.stdout, "mod." + id + ".")
                                                                 : { ok: false, problem: "its settings could not be read", profiles: [], globals: {} })
        });
    }

    // ---- Writing back ----

    // A restore's file part (ModuleBackupRules.restorePlan): the store's file and each named
    // path put back from backup `plan.entry.name`, or removed where the backup did not hold
    // it — each by a temporary name and a rename, never through a link, never outside the
    // module's data directory. → done([problems])
    function writeBack(id, plan, done) {
        const pairs = [].concat(...plan.data.map(each => [each.op, each.path]));
        const lines = [];
        _run(["sh", "-c", root._writeScript, "sh", places.backups + "/" + id + "/" + plan.entry.name, places.stores + "/" + id + ".json",
              places.data + "/" + id, plan.store].concat(pairs), {
            onLine: (line, stream) => {
                if (stream === "stdout")
                    lines.push(line);
            },
            done: result => done(ModuleBackupRules.writeOutcome(lines, 1 + plan.data.length).problems)
        });
    }

    readonly property string _writeScript: "src=$1; st=$2; d=$3; sm=$4; shift 4; umask 077; "
        + "{ [ -d \"$src\" ] && [ ! -L \"$src\" ] && [ ! -L \"${src%/*}\" ]; } || { printf 'fail\\tbackup\\tnot readable\\n'; exit 1; }; "
        + "sd=${st%/*}; mkdir -p -- \"$sd\" || exit 1; "
        + "if [ \"$sm\" = put ]; then "
        + "if [ -f \"$src/store.json\" ] && [ ! -L \"$src/store.json\" ] && t=$(mktemp -- \"$sd/.restore.XXXXXX\"); then "
        + "if cp -P -- \"$src/store.json\" \"$t\" && chmod 600 -- \"$t\" && mv -fT -- \"$t\" \"$st\"; then printf 'ok\\tstore\\n'; else rm -f -- \"$t\"; printf 'fail\\tstore\\tnot written\\n'; fi; "
        + "else printf 'fail\\tstore\\tnot in the backup\\n'; fi; "
        + "elif [ \"$sm\" = keep ]; then printf 'ok\\tstore\\n'; "
        + "else if [ -L \"$st\" ] || [ -f \"$st\" ]; then rm -f -- \"$st\" && printf 'ok\\tstore\\n' || printf 'fail\\tstore\\tnot removed\\n'; "
        + "elif [ -e \"$st\" ]; then printf 'fail\\tstore\\tnot a file\\n'; else printf 'ok\\tstore\\n'; fi; fi; "
        + "mkdir -p -- \"$d\" && base=$(realpath -e -- \"$d\") || { while [ $# -ge 2 ]; do printf 'fail\\t%s\\tno data directory\\n' \"$2\"; shift 2; done; echo done; exit 0; }; "
        + "sb=; [ -d \"$src/data\" ] && [ ! -L \"$src/data\" ] && sb=$(realpath -e -- \"$src/data\"); "
        + "set -f; while [ $# -ge 2 ]; do op=$1; rel=$2; shift 2; "
        + "case $rel in */*) up=${rel%/*} ;; *) up= ;; esac; name=${rel##*/}; "
        // Its folders made one level at a time from the data directory down, none a link:
        // nothing is ever made through a link, inside the directory or out of it
        + "rp=$base; bad=; old=$IFS; IFS=/; for c in $up; do IFS=$old; [ -n \"$c\" ] || continue; "
        + "if [ -L \"$rp/$c\" ]; then bad='leads through a link'; break; fi; "
        + "[ -d \"$rp/$c\" ] || mkdir -- \"$rp/$c\" 2>/dev/null || { bad='its folder could not be made'; break; }; rp=$rp/$c; done; IFS=$old; "
        + "[ -z \"$bad\" ] || { printf 'fail\\t%s\\t%s\\n' \"$rel\" \"$bad\"; continue; }; "
        + "from=$src/data/$rel; "
        + "if [ \"$op\" = put ]; then fp=$(realpath -e -- \"${from%/*}\" 2>/dev/null) || fp=; "
        + "case $fp in \"$sb\"|\"$sb\"/*) [ -n \"$sb\" ] ;; *) false ;; esac && { [ -e \"$from\" ] || [ -L \"$from\" ]; } "
        + "|| { printf 'fail\\t%s\\tnot in the backup\\n' \"$rel\"; continue; }; fi; "
        + "tmp=$(mktemp -d -- \"$rp/.h2s-restore.XXXXXX\") || { printf 'fail\\t%s\\tnot written\\n' \"$rel\"; continue; }; "
        + "if [ \"$op\" = put ] && ! cp -a -P -- \"$from\" \"$tmp/new\"; then rm -rf -- \"$tmp\"; printf 'fail\\t%s\\tnot copied\\n' \"$rel\"; continue; fi; "
        + "t=$rp/$name; had=; if [ -e \"$t\" ] || [ -L \"$t\" ]; then mv -T -- \"$t\" \"$tmp/old\" || { rm -rf -- \"$tmp\"; printf 'fail\\t%s\\tnot replaced\\n' \"$rel\"; continue; }; had=1; fi; "
        + "if [ \"$op\" = put ] && ! mv -T -- \"$tmp/new\" \"$t\"; then [ -n \"$had\" ] && mv -T -- \"$tmp/old\" \"$t\"; rm -rf -- \"$tmp\"; printf 'fail\\t%s\\tnot replaced\\n' \"$rel\"; continue; fi; "
        + "rm -rf -- \"$tmp\"; printf 'ok\\t%s\\n' \"$rel\"; done; echo done"

    // ---- Commands ----

    function _run(argv, options) {
        return _runner.start(argv, Object.assign({ timeoutMs: stepTimeoutMs, killAfterMs: 1000 }, options, {
            done: result => {
                if (result.error !== "")
                    console.warn("[Modules] a backup step could not be run: " + result.error);
                options.done(result);
            }
        }));
    }

    CommandRunner {
        id: _runner
        environment: root.environment
    }
}
