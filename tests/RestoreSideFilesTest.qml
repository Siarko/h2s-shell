import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.singletons

// A restore puts back the side files of its backup with config.json (ConfigRestore,
// ConfigMigration's backups), on scratch config folders with a test-only file-scope
// migration: after a run that overwrote, removed and created theme files and edits made
// since, a restore of the run's backup brings back each file as it was and removes the one
// the run created; the files it replaced are kept with the restore's own backup, whose restore
// undoes it; the migrations run again on that give what a clean run gives. A step that fails
// midway puts everything back (config.json and each side file as they were, no staging
// folder left); a linked backup-side-files, a linked side folder, a link among the side files
// and a link in a side file's place refuse the whole restore, nothing changed.
TestCase {
    id: suite
    suiteName: "RestoreSideFiles"
    asynchronous: true

    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-restore-side-files-test-" + Date.now() + "-" + Math.floor(Math.random() * 1e6)

    property var _steps: []

    function _then(description, condition, action) {
        _steps.push({ description: description, condition: condition, action: action });
    }

    property Timer _clock: Timer {
        interval: 20
        repeat: true
        property int waited: 0
        onTriggered: {
            const step = suite._steps[0];
            if (!step) {
                stop();
                Quickshell.execDetached(["sh", "-c", "chmod -R u+rwx -- \"$1\"; rm -rf -- \"$1\"", "sh", suite._scratch]);
                suite.finish();
                return;
            }
            waited += interval;
            let ready = false;
            try {
                ready = step.condition();
            } catch (error) {}
            if (!ready && waited < 15000)
                return;
            waited = 0;
            suite._steps.shift();
            if (!ready)
                suite.fail("timed out waiting: " + step.description);
            try {
                step.action();
            } catch (error) {
                suite.fail("threw in \"" + step.description + "\": " + error);
            }
        }
    }

    property Component _config: Component {
        ConfigFile {
            property int reads: 0
            blockWrites: true
            printErrors: false
            onRead: reads++
            adapter: ConfigAdapter {}
        }
    }

    property Component _restorer: Component {
        ConfigRestore {
            property var result: null
            version: "2.2.0"
        }
    }

    property Component _runner: Component {
        Process {
            property var lines: null
            property int code: -1
            stdout: StdioCollector { id: _out }
            onExited: exitCode => {
                code = exitCode;
                lines = _out.text.split("\n").filter(line => line !== "");
            }
        }
    }

    property FileView _disk: FileView {
        blockAllReads: true
        blockWrites: true
        printErrors: false
    }

    function _read(path) {
        _disk.path = "";
        _disk.path = path;
        _disk.reload();
        return _disk.text() ?? "";
    }

    function _write(path, text) {
        _read(path);
        _disk.setText(text);
    }

    // A command run: an object whose `lines` (its output) is null until it ended
    function _run(command) {
        const process = _runner.createObject(suite, { command: command });
        process.running = true;
        return process;
    }

    // Every file under `dir` but the backups and their side files, with its content: what a
    // run leaves
    function _state(dir) {
        return _run(["sh", "-c", "cd -- \"$1\" && find . -path ./backup-side-files -prune -o -type f ! -name 'config.json.bak-*' -print | sort "
                     + "| while read -r file; do printf '%s=' \"$file\"; tr '\\n' ' ' < \"$file\"; echo; done", "sh", dir]);
    }

    function _open(dir, registry) {
        const config = _config.createObject(suite, { configPath: dir + "/config.json", viewDir: dir + "-view", version: "2.2.0" });
        config.registry = registry ?? [_accentTheme];
        return config;
    }

    // A restore of `backup` started; `extra(restorer)` before it starts
    function _restore(dir, backup, registry, extra) {
        const restorer = _restorer.createObject(suite, { configPath: dir + "/config.json" });
        restorer.registry = registry ?? [_accentTheme];
        if (typeof extra === "function")
            extra(restorer);
        assert(restorer.restore(backup, [], answer => restorer.result = answer), "restore started: " + backup);
        return restorer;
    }

    // A migration whose file scope names the hand-made backups' created files
    readonly property var _otherFiles: ({
        migrationId: "2026-11-26-testonly-other-files", since: "2.2.0", summary: "test other files",
        scope: ["file:c/*.json", "file:z/*.json"], migrate: doc => doc
    })

    // The folder's staging folders, then its backups' side folders
    function _leftovers(dir) {
        return _run(["sh", "-c", "for each in \"$1\"/.config-restore.*; do [ -e \"$each\" ] && echo \"stage ${each##*/}\"; done; "
                     + "[ -d \"$1/backup-side-files\" ] && ls -A -- \"$1/backup-side-files\" | sed 's/^/side /'; exit 0", "sh", dir]);
    }

    // A file-scope migration of the kind that moves settings into theme files: the accent set
    // as global goes into a new theme file at a free name (an existing one is never written
    // over), dark.json's height is renamed, old.json removed. Idempotent on what it leaves; run
    // on the old config beside the theme files it made, it would make a second theme
    readonly property var _accentTheme: ({
        migrationId: "2026-11-26-testonly-accent-theme", since: "2.2.0", summary: "test accent into a theme",
        scope: ["setting:testonly.*", "file:themes/*.json"],
        migrate: doc => {
            const accent = doc.globals["testonly.accent"];
            if (accent !== undefined) {
                let name = "themes/accent.json";
                for (let i = 2; Object.prototype.hasOwnProperty.call(doc.files, name); i++)
                    name = "themes/accent " + i + ".json";
                doc.files[name] = { accent: accent };
                delete doc.globals["testonly.accent"];
            }
            const dark = doc.files["themes/dark.json"];
            if (dark && dark.height !== undefined && dark.barHeight === undefined) {
                dark.barHeight = dark.height;
                delete dark.height;
            }
            delete doc.files["themes/old.json"];
            return doc;
        }
    })

    readonly property string _oldText: '{"profiles": "[{\\"name\\":\\"Full\\",\\"enabled\\":true,\\"when\\":{},\\"set\\":{}}]",\n'
        + ' "globals": "{\\"testonly.accent\\":\\"red\\"}",\n'
        + ' "migratedKeys": ["bar.height"], "writtenBy": "2.1.0"}\n'
    readonly property string _darkText: '{ "accent": "#88c0d0", "height": 30 }\n'
    readonly property string _oldThemeText: '{ "old": true }\n'

    function _seed(dir) {
        _write(dir + "/config.json", _oldText);
        _write(dir + "/themes/dark.json", _darkText);
        _write(dir + "/themes/old.json", _oldThemeText);
    }

    function runAsync() {
        _restoreAndRerun();
        _partialFailure();
        _crash();
        _noConfig();
        _changedSince();
        _pruning();
        _links();
        _clock.start();
    }

    // ---- Restored with the config, rerun: what a clean run gives ----
    function _restoreAndRerun() {
        const clean = _scratch + "/clean";
        const dir = _scratch + "/restored";
        let cleanRun = null;
        let firstRun = null;
        let rerun = null;
        let cleanState = null;
        let edited = null;
        let restorer = null;
        let undo = null;
        let restoreBackup = "";
        let state = null;
        let undone = null;
        let modeBefore = null;
        let accentText = "";
        _then("the folders", () => true, () => {
            _seed(clean);
            _seed(dir);
            cleanRun = _open(clean);
            cleanRun.load();
            firstRun = _open(dir);
            firstRun.load();
        });
        _then("both run", () => cleanRun.reads === 1 && !cleanRun.migrationBusy && firstRun.reads === 1 && !firstRun.migrationBusy, () => {
            assertEqual(_read(dir + "/themes/accent.json") !== "" && _read(dir + "/themes/old.json") === "", true,
                        "the run created a theme and removed one");
            cleanState = _state(clean);
            // Changed since the run: the theme it migrated
            _write(dir + "/themes/dark.json", '{ "barHeight": 40 }\n');
            accentText = _read(dir + "/themes/accent.json");
            edited = _state(dir);
            modeBefore = _run(["stat", "-c", "%a", "--", dir + "/config.json"]);
        });
        _then("the states read", () => cleanState.lines !== null && edited.lines !== null && modeBefore.lines !== null, () => {
            restorer = _restore(dir, firstRun.migrationReports.load.backup);
        });
        _then("restored", () => restorer.result !== null, () => {
            assertEqual(restorer.result.ok, true, "restored: " + restorer.result.problem);
            const restored = JSON.parse(_read(dir + "/config.json"));
            const old = JSON.parse(_oldText);
            assertEqual(restored.globals + "|" + restored.migratedKeys.join(",") + "|" + restored.profiles,
                        old.globals + "|" + old.migratedKeys.join(",") + "|" + old.profiles, "restored: the config from before the run");
            assertEqual(_read(dir + "/themes/dark.json"), _darkText, "restored: an overwritten side file as it was");
            assertEqual(_read(dir + "/themes/old.json"), _oldThemeText, "restored: a removed one back");
            assertEqual(_read(dir + "/themes/accent.json"), "", "restored: the one the run created removed (unchanged since)");
            restoreBackup = restorer.result.backup;
            const side = dir + "/backup-side-files/" + restoreBackup.replace(/^.*\//, "");
            assertEqual(_read(side + "/themes/dark.json"), '{ "barHeight": 40 }\n', "restored: the file it replaced kept with its backup");
            assertEqual(_read(side + "/themes/accent.json"), accentText, "restored: … and the one it removed");
            assertEqual(_read(side + "/.created-files"), Qt.md5(_oldThemeText) + " themes/old.json\n", "restored: … and the list of those it created, with their hash");
            state = _run(["sh", "-c", "ls -A -- \"$1\" | grep -c '^\\.config-restore\\.' ; stat -c %a -- \"$1/config.json\" \"$2\"", "sh", dir, restoreBackup]);
        });
        _then("the folder after the restore", () => state.lines !== null, () => {
            assertEqual(state.lines[0], "0", "restored: no staging folder left");
            assertEqual(state.lines[1], modeBefore.lines[0], "restored: config.json keeps its mode");
            rerun = _open(dir);
            rerun.load();
        });
        _then("the rerun", () => rerun.reads === 1 && !rerun.migrationBusy, () => {
            assertEqual(rerun.migrationReports.load?.applied?.join(","), "2026-11-26-testonly-accent-theme", "rerun: the migration ran again");
            state = _state(dir);
        });
        _then("the rerun's folder", () => state.lines !== null, () => {
            assertEqual(state.lines.join("\n"), cleanState.lines.join("\n"), "rerun: the same files with the same contents as a clean run");
            undo = _restore(dir, restoreBackup);
        });
        _then("the restore's backup restored", () => undo.result !== null, () => {
            assertEqual(undo.result.ok, true, "undone: " + undo.result.problem);
            undone = _state(dir);
        });
        _then("the undone folder", () => undone.lines !== null, () => {
            assertEqual(undone.lines.join("\n"), edited.lines.join("\n"), "undone: the files as they were before the restore (the one it put back removed)");
        });
    }

    // A backup in `dir` made by hand: its config text and its side files ({ path: text })
    function _backup(dir, stamp, text, sides) {
        const name = "config.json.bak-2026-01-0" + stamp + "T00-00-00-000Z-migration";
        _write(dir + "/" + name, text);
        for (const file of Object.keys(sides))
            _write(dir + "/backup-side-files/" + name + "/" + file, sides[file]);
        return dir + "/" + name;
    }

    // A backup made by hand with created files listed (path → the text the run wrote)
    function _createdList(dir, backup, created) {
        _write(dir + "/backup-side-files/" + backup.replace(/^.*\//, "") + "/.created-files", ConfigBackupRules.createdText(created));
    }

    readonly property string _nowText: '{"writtenBy": "2.2.0", "migratedKeys": ["now"]}\n'

    // The partial case's folder: a/x.json put back, a/new.json made, c/made.json and z/gone.json
    // (both made by the run, unchanged) removed — z/ last
    function _partialFolder(dir, stamp) {
        _write(dir + "/config.json", _nowText);
        _write(dir + "/a/x.json", "A now\n");
        _write(dir + "/c/made.json", "C made\n");
        _write(dir + "/z/gone.json", "Z made\n");
        const backup = _backup(dir, stamp, _oldText, { "a/x.json": "A then\n", "a/new.json": "A new\n" });
        _createdList(dir, backup, { "c/made.json": "C made\n", "z/gone.json": "Z made\n" });
        return backup;
    }

    function _partialAsBefore(dir, what) {
        assertEqual(_read(dir + "/config.json"), _nowText, what + ": config.json as it was");
        assertEqual(_read(dir + "/a/x.json"), "A now\n", what + ": a side file put back, as it was");
        assertEqual(_read(dir + "/a/new.json"), "", what + ": the one the restore made gone");
        assertEqual(_read(dir + "/c/made.json"), "C made\n", what + ": a removed one back");
        assertEqual(_read(dir + "/z/gone.json"), "Z made\n", what + ": the last one as it was");
    }

    // ---- A step that fails midway: everything as it was ----
    function _partialFailure() {
        const dir = _scratch + "/partial";
        let backup = "";
        let locked = null;
        let restorer = null;
        let state = null;
        _then("the partial case's folder", () => true, () => {
            backup = _partialFolder(dir, 1);
            // z/ cannot lose a file: the swap fails at its last step
            locked = _run(["chmod", "500", "--", dir + "/z"]);
        });
        _then("z locked", () => locked.lines !== null, () => {
            restorer = _restore(dir, backup, [_otherFiles]);
        });
        _then("the partial restore answered", () => restorer.result !== null, () => {
            assertEqual(restorer.result.ok, false, "partial: failed");
            assert(restorer.result.problem.includes("z/gone.json") && restorer.result.problem.includes("nothing restored"), "partial: the problem named: " + restorer.result.problem);
            _partialAsBefore(dir, "partial");
            state = _leftovers(dir);
        });
        _then("the partial folder", () => state.lines !== null, () => {
            assertEqual(state.lines.join(","), "side " + backup.replace(/^.*\//, ""), "partial: no staging folder, no side files kept for the new backup");
        });
    }

    // ---- Cut short (the shell ended mid-swap): put back at the next start ----
    function _crash() {
        const dir = _scratch + "/crash";
        let backup = "";
        let restorer = null;
        let state = null;
        let locked = null;
        let start = null;
        let again = null;
        _then("the crash case's folder", () => true, () => {
            backup = _partialFolder(dir, 3);
            // Stopped after config.json, a/new.json, a/x.json and c/made.json
            restorer = _restore(dir, backup, [_otherFiles], each => each._swap.stopAfter = 3);
        });
        _then("the crash case cut short", () => restorer.result !== null, () => {
            assertEqual(restorer.result.ok, false, "cut short: not done");
            assertEqual(_read(dir + "/c/made.json"), "", "cut short: half done (a created file removed)");
            assert(_read(dir + "/config.json") !== _nowText, "cut short: … config.json replaced");
            // a/ cannot take its file back: the first putting back fails
            locked = _run(["chmod", "500", "--", dir + "/a"]);
        });
        _then("a locked", () => locked.lines !== null, () => {
            start = _open(dir, []);
            start.load();
        });
        _then("the start after the cut", () => start.reads === 1 && !start.migrationBusy, () => {
            state = _leftovers(dir);
        });
        _then("the folder after a putting back that failed", () => state.lines !== null, () => {
            assertEqual(state.lines.filter(line => line.startsWith("stage ")).length, 1, "put back in part: the staging folder kept");
            assertEqual(state.lines.filter(line => line.startsWith("side ") && line.endsWith("-restore")).length, 1, "put back in part: the copies kept with the new backup");
            locked = _run(["chmod", "700", "--", dir + "/a"]);
        });
        _then("a unlocked", () => locked.lines !== null, () => {
            again = _open(dir, []);
            again.load();
        });
        _then("the next start", () => again.reads === 1 && !again.migrationBusy, () => {
            _partialAsBefore(dir, "put back");
            state = _leftovers(dir);
        });
        _then("the folder put back", () => state.lines !== null, () => {
            assertEqual(state.lines.join(","), "side " + backup.replace(/^.*\//, ""), "put back: no staging folder, no side files kept for the new backup");
        });
    }

    // ---- No config.json: nothing replaced without a backup to keep it in ----
    function _noConfig() {
        const dir = _scratch + "/no-config";
        let backup = "";
        let restorer = null;
        _then("the no-config case's folder", () => true, () => {
            _write(dir + "/c/made.json", "C made\n");
            backup = _backup(dir, 4, _oldText, { "themes/dark.json": "dark then\n" });
            _write(dir + "/themes/dark.json", "dark now\n");
            _createdList(dir, backup, { "c/made.json": "C made\n" });
            restorer = _restore(dir, backup, [_otherFiles]);
        });
        _then("the no-config restore answered", () => restorer.result !== null, () => {
            assertEqual(restorer.result.ok, false, "no config: refused");
            assert(restorer.result.problem.includes("no config.json to back up"), "no config: the problem said: " + restorer.result.problem);
            assertEqual(_read(dir + "/themes/dark.json"), "dark now\n", "no config: the side file as it was");
            assertEqual(_read(dir + "/c/made.json"), "C made\n", "no config: a created one not removed");
            assertEqual(_read(dir + "/config.json"), "", "no config: none written");
        });
    }

    // ---- A created file changed since, or no migration's: never removed ----
    function _changedSince() {
        const dir = _scratch + "/changed";
        let backup = "";
        let restorer = null;
        _then("the changed case's folder", () => true, () => {
            _write(dir + "/config.json", _nowText);
            _write(dir + "/c/made.json", "C made again\n");
            _write(dir + "/c/kept.json", "C kept\n");
            _write(dir + "/q/other.json", "Q made\n");
            backup = _backup(dir, 5, _oldText, {});
            _createdList(dir, backup, { "c/made.json": "C made\n", "c/kept.json": "C kept\n", "q/other.json": "Q made\n" });
            restorer = _restore(dir, backup, [_otherFiles]);
        });
        _then("the changed restore answered", () => restorer.result !== null, () => {
            assertEqual(restorer.result.ok, true, "changed: restored: " + restorer.result.problem);
            assertEqual(_read(dir + "/c/made.json"), "C made again\n", "changed: a created file made again since kept");
            assertEqual(_read(dir + "/c/kept.json"), "", "changed: an unchanged one removed");
            assertEqual(_read(dir + "/q/other.json"), "Q made\n", "changed: one no registered migration names kept");
        });
    }

    // ---- Pruning keeps a restore's backup that holds side files ----
    function _pruning() {
        const dir = _scratch + "/pruning";
        let pruner = null;
        let pruned = false;
        let listing = null;
        const withSides = "config.json.bak-2025-01-01T00-00-00-000Z-restore";
        const without = "config.json.bak-2025-01-02T00-00-00-000Z-restore";
        _then("the pruning case's folder", () => true, () => {
            _write(dir + "/" + withSides, _oldText);
            _write(dir + "/backup-side-files/" + withSides + "/themes/dark.json", "dark\n");
            _write(dir + "/" + without, _oldText);
            for (let i = 10; i < 21; i++)
                _write(dir + "/config.json.bak-2026-02-" + i + "T00-00-00-000Z-migration", _oldText);
            pruner = _prunerComponent.createObject(suite, { dir: dir });
            pruner.pruned.connect(() => pruned = true);
            pruner.prune("config.json.bak-2026-02-20T00-00-00-000Z-migration", []);
        });
        _then("pruned", () => pruned, () => {
            listing = _run(["ls", "-1A", "--", dir]);
        });
        _then("the pruned folder", () => listing.lines !== null, () => {
            assert(listing.lines.includes(withSides), "pruning: a restore's backup with side files kept, however old");
            assert(!listing.lines.includes(without), "pruning: one without them pruned as before");
            assertEqual(listing.lines.filter(name => name.endsWith("-migration")).length, 10, "pruning: it takes no place among the ten");
        });
    }

    property Component _prunerComponent: Component {
        ConfigBackupPruner {}
    }

    // ---- Links refuse the whole restore ----
    function _links() {
        const cases = [
            { name: "side-folder", what: "a linked side folder", setup: (dir, name) => ["sh", "-c", "mkdir -p -- \"$1/backup-side-files\" && ln -s -- \"$1/elsewhere\" \"$1/backup-side-files/$2\"", "sh", dir, name], linkedFolder: true },
            { name: "side-root", what: "a linked backup-side-files", setup: (dir, name) => ["ln", "-s", "--", dir + "/elsewhere-root", dir + "/backup-side-files"], linkedRoot: true },
            { name: "inside", what: "a link among the side files", setup: (dir, name) => ["ln", "-s", "--", dir + "/elsewhere/themes/dark.json", dir + "/backup-side-files/" + name + "/themes/link.json"] },
            { name: "target", what: "a link in a side file's place", through: true, setup: (dir, name) => ["sh", "-c", "rm -f -- \"$1/themes/dark.json\" && ln -s -- \"$1/elsewhere/themes/dark.json\" \"$1/themes/dark.json\"", "sh", dir] },
            { name: "target-folder", what: "a linked folder on a side file's way", setup: (dir, name) => ["sh", "-c", "mv -- \"$1/themes\" \"$1/real-themes\" && ln -s -- real-themes \"$1/themes\"", "sh", dir] }
        ];
        for (const each of cases)
            _link(each);
    }

    function _link(each) {
        const dir = _scratch + "/link-" + each.name;
        const now = _nowText;
        let name = "";
        let made = null;
        let restorer = null;
        _then(each.what + ": the folder", () => true, () => {
            _write(dir + "/config.json", now);
            _write(dir + "/themes/dark.json", "dark now\n");
            _write(dir + "/elsewhere/themes/dark.json", "elsewhere\n");
            _write(dir + "/elsewhere-root/x/themes/dark.json", "elsewhere\n");
            const sides = each.linkedFolder || each.linkedRoot ? {} : { "themes/dark.json": "dark then\n" };
            const path = _backup(dir, 2, _oldText, sides);
            name = path.replace(/^.*\//, "");
            made = _run(each.setup(dir, name));
        });
        _then(each.what + ": the link made", () => made.lines !== null, () => {
            assertEqual(made.code, 0, each.what + ": the link made");
            restorer = _restore(dir, dir + "/" + name);
        });
        _then(each.what + ": answered", () => restorer.result !== null, () => {
            assertEqual(restorer.result.ok, false, each.what + ": refused");
            assert(restorer.result.problem.includes("link") && restorer.result.problem.includes("nothing restored"), each.what + ": the problem said: " + restorer.result.problem);
            assertEqual(_read(dir + "/config.json"), now, each.what + ": config.json as it was");
            assertEqual(_read(dir + "/themes/dark.json"), each.through ? "elsewhere\n" : "dark now\n", each.what + ": the side file as it was");
            assertEqual(_read(dir + "/elsewhere/themes/dark.json"), "elsewhere\n", each.what + ": nothing written where the link points");
        });
    }
}
