import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.singletons

// A deleted theme's file kept (ThemeBackups), on scratch folders: the backup holds the same
// content, private, and the theme file is left for the caller to remove; a theme with no file
// backs up nothing; a name with a space at its end and a 230-byte one kept under a hashed
// name with a record, and restored under their own; a backup restored brings the theme back with that content, never over a
// theme of the name, never from a name that is no backup; a linked theme-backups folder is
// refused both ways, nothing copied where it points; one at a time.
TestCase {
    id: suite
    suiteName: "ThemeBackups"
    asynchronous: true

    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-theme-backups-test-" + Date.now() + "-" + Math.floor(Math.random() * 1e6)
    readonly property string _themes: _scratch + "/themes"
    readonly property string _backups: _scratch + "/theme-backups"
    readonly property string _long: "a".repeat(230)
    readonly property string _content: "{\n  \"extends\": \"default\",\n  \"colors\": { \"accent\": \"#123456\" }\n}\n"

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
                Quickshell.execDetached(["rm", "-rf", "--", suite._scratch]);
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

    property ThemeBackups _subject: ThemeBackups {}

    property Component _process: Component {
        Process {
            property int code: -1
            property string output: ""
            stdout: StdioCollector { id: _out }
            onExited: exitCode => {
                output = _out.text;
                code = exitCode;
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

    function _run(command) {
        const process = _process.createObject(suite, { command: command });
        process.running = true;
        return process;
    }

    function runAsync() {
        let made = null;
        let result = null;
        let second = null;
        let backup = "";
        let listing = null;
        let made2 = null;
        let odd = "";
        let backups2 = "";
        const outside = _scratch + "/outside";

        _then("the stand-in folders", () => true, () => {
            made = _run(["sh", "-c", "mkdir -p -- \"$1\" \"$2\" && printf '%s' \"$3\" > \"$1/Power save.json\" && printf '%s' \"$3\" > \"$1/other.json\"",
                         "sh", _themes, outside, _content]);
            made2 = _run(["sh", "-c", "mkdir -p -- \"$1\" && printf '%s' \"$2\" > \"$1/ x.json\" && printf '%s' \"$2\" > \"$1/$3.json\"", "sh", _themes, _content, _long]);
        });
        _then("made", () => made.code !== -1 && made2.code !== -1, () => {
            assertEqual(made.code + "|" + made2.code, "0|0", "the stand-in themes made");
            assert(!_subject.backUp(_themes, _backups, "../escape", () => {}), "not a theme's name: not started");
            assert(!_subject.backUp("", _backups, "Power save", () => {}), "no themes folder: not started");
            assert(_subject.backUp(_themes, _backups, "Power save", answer => result = answer), "a backup started");
            assert(_subject.running, "it runs");
            assert(!_subject.backUp(_themes, _backups, "other", answer => second = answer), "one at a time");
        });
        _then("backed up", () => result !== null, () => {
            assertEqual(result.ok + "|" + result.problem, "true|", "the backup made");
            backup = result.backup;
            assert(ThemeRules.parseThemeBackupName(backup).ok && ThemeRules.parseThemeBackupName(backup).theme === "Power save",
                   "named as a theme backup of the theme: " + backup);
            assertEqual(_read(_backups + "/" + backup), _content, "the backup holds the theme file's content");
            assertEqual(_read(_themes + "/Power save.json"), _content, "the theme file is left for the caller to remove");
            listing = _run(["sh", "-c", "stat -c %a -- \"$1\" \"$1/$2\"; ls -A -- \"$1\"", "sh", _backups, backup]);
        });
        _then("listed", () => listing.code !== -1, () => {
            assertEqual(listing.output, "700\n600\n" + backup + "\n", "private, and nothing else left in the folder");
            result = null;
            assert(_subject.backUp(_themes, _backups, "missing", answer => result = answer), "a theme with no file: started");
        });
        _then("no file", () => result !== null, () => {
            assertEqual(result.ok + "|" + result.backup, "true|", "no file: nothing to keep, no backup");
            result = null;
            assert(_subject.backUp(_themes, _backups, " x", answer => result = answer), "a name with a space first: started");
        });
        _then("a space first: kept", () => result !== null, () => {
            assertEqual(result.ok + "|" + result.problem, "true|", "kept");
            odd = result.backup;
            assert(odd.startsWith("theme-") && ThemeRules.parseThemeBackupName(odd).ok, "under a hashed name: " + odd);
            assertEqual(_read(_backups + "/" + odd), _content, "with the content");
            assertEqual(_subject.themeOf(_backups, odd), " x", "the record names the theme");
            result = null;
            assert(_subject.backUp(_themes, _backups, _long, answer => result = answer), "a 230-byte name: started");
        });
        _then("a long name: kept", () => result !== null, () => {
            assertEqual(result.ok + "|" + result.problem, "true|", "kept");
            assertEqual(_subject.themeOf(_backups, result.backup), _long, "the record names the theme");
            assertEqual(_read(_backups + "/" + result.backup), _content, "with the content");
            backups2 = result.backup;
            made = _run(["rm", "--", _themes + "/Power save.json", _themes + "/ x.json", _themes + "/" + _long + ".json"]);
        });
        _then("odd names deleted", () => made.code !== -1, () => {
            assertEqual(made.code, 0, "the odd themes deleted");
            result = null;
            assert(_subject.restore(_themes, _backups, odd, answer => result = answer), "restoring a space first: started");
        });
        _then("a space first: restored", () => result !== null, () => {
            assertEqual(result.ok + "|" + result.theme, "true| x", "restored under its own name");
            assertEqual(_read(_themes + "/ x.json"), _content, "with the content");
            result = null;
            assert(_subject.restore(_themes, _backups, backups2, answer => result = answer), "restoring a long name: started");
        });
        _then("a long name: restored", () => result !== null, () => {
            assertEqual(result.ok + "|" + result.problem, "true|", "restored");
            assertEqual(_read(_themes + "/" + _long + ".json"), _content, "under its own name, with the content");
            listing = _run(["ls", "-A", "--", _themes]);
        });
        _then("no temporary files", () => listing.code !== -1, () => {
            assertEqual(listing.output.split("\n").filter(line => line !== "").sort().join("|"), [" x.json", _long + ".json", "other.json"].sort().join("|"),
                        "the themes folder: only themes, nothing left over");
        });
        _then("the theme deleted", () => made.code !== -1, () => {
            result = null;
            assert(!_subject.restore(_themes, _backups, "Power save.json", () => {}), "a name that is no backup: not started");
            assert(!_subject.restore(_themes, _backups, "../" + backup, () => {}), "a path: not started");
            assert(_subject.restore(_themes, _backups, backup, answer => result = answer), "a restore started");
        });
        _then("restored", () => result !== null, () => {
            assertEqual(result.ok + "|" + result.problem + "|" + result.theme, "true||Power save", "restored");
            assertEqual(_read(_themes + "/Power save.json"), _content, "the theme is back with its content");
            assertEqual(_read(_backups + "/" + backup), _content, "the backup stays");
            made = _run(["sh", "-c", "printf '%s' changed > \"$1/Power save.json\"", "sh", _themes]);
        });
        _then("changed", () => made.code !== -1, () => {
            result = null;
            assert(_subject.restore(_themes, _backups, backup, answer => result = answer), "a restore over a theme of the name: started");
        });
        _then("not over a theme", () => result !== null, () => {
            assertEqual(result.ok + "|" + result.problem, "false|A theme named Power save exists", "refused, said");
            assertEqual(_read(_themes + "/Power save.json"), "changed", "the theme there kept");
            result = null;
            assert(_subject.restore(_themes, _backups, "gone.json.bak-2026-11-26T09-05-07-042Z", answer => result = answer), "a backup not there: started");
        });
        _then("not there", () => result !== null, () => {
            assertEqual(result.ok + "|" + result.problem, "false|No such backup", "refused, said");
            made = _run(["sh", "-c", "mv -- \"$1\" \"$1-real\" && ln -s -- \"$2\" \"$1\"", "sh", _backups, outside]);
        });
        _then("a linked theme-backups", () => made.code !== -1, () => {
            assertEqual(made.code, 0, "theme-backups made a link");
            result = null;
            assert(_subject.backUp(_themes, _backups, "other", answer => result = answer), "a backup through a link: started");
        });
        _then("linked: backup refused", () => result !== null, () => {
            assertEqual(result.ok + "|" + result.problem, "false|theme-backups is a link: nothing kept", "refused, said");
            listing = _run(["ls", "-A", "--", outside]);
        });
        _then("linked: nothing where it points", () => listing.code !== -1, () => {
            assertEqual(listing.output, "", "nothing copied where the link points");
            made = _run(["sh", "-c", "cp -- \"$1-real/$2\" \"$3/$2\" && rm -- \"$4/Power save.json\"", "sh", _backups, backup, outside, _themes]);
        });
        _then("a backup where the link points", () => made.code !== -1, () => {
            assertEqual(made.code, 0, "a backup put where the link points");
            result = null;
            assert(_subject.restore(_themes, _backups, backup, answer => result = answer), "a restore through a link: started");
        });
        _then("linked: restore refused", () => result !== null, () => {
            assertEqual(result.ok + "|" + result.problem, "false|theme-backups is a link: nothing restored", "refused, said");
            assertEqual(_read(_themes + "/Power save.json"), "", "no theme restored from where the link points");
            assertEqual(second, null, "the refused second backup never answered");
        });
        _clock.start();
    }
}
