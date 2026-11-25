import QtQuick
import Quickshell.Io
import qs.singletons

// Keeps a theme's file before it is deleted, and puts a kept one back: the backups live in a
// folder of their own beside the themes folder (theme-backups), one file per deleted theme,
// named by ThemeRules.themeBackupName, readable by the user only. backUp() copies the theme
// file there and leaves the file for the caller to remove once the copy is made; restore()
// copies a backup back as its theme, never over a theme of that name, and keeps the backup.
// When theme-backups is a link nothing is copied either way (its files would land, or be read,
// wherever it points) and it is said. The names are checked here; they reach the fixed scripts
// as arguments. One at a time.
QtObject {
    id: root

    readonly property bool running: _process.running || _running

    property bool _running: false
    property var _done: null
    property var _answer: null

    // $1 the themes folder, $2 the backups folder, $3 the theme, $4 the backup's name. Prints
    // the backup's name, nothing when the theme has no file; each problem one line on stderr
    readonly property string _backUpScript: "umask 077; src=\"$1/$3.json\"; backups=$2; "
        + "if [ -L \"$backups\" ]; then echo \"theme-backups is a link: nothing kept\" >&2; exit 1; fi; "
        + "if [ ! -e \"$src\" ] && [ ! -L \"$src\" ]; then exit 0; fi; "
        + "mkdir -p -- \"$backups\" || { echo \"could not make theme-backups\" >&2; exit 1; }; "
        + "if [ -L \"$backups\" ] || [ ! -d \"$backups\" ]; then echo \"theme-backups is no folder: nothing kept\" >&2; exit 1; fi; "
        + "dest=\"$backups/$4\"; part=\"$backups/.$4.part\"; "
        + "if [ -e \"$dest\" ] || [ -L \"$dest\" ]; then echo \"$4 exists already\" >&2; exit 1; fi; "
        + "rm -f -- \"$part\"; "
        + "if ! cp -- \"$src\" \"$part\" || ! mv -- \"$part\" \"$dest\"; then rm -f -- \"$part\"; echo \"could not copy the theme\" >&2; exit 1; fi; "
        + "printf '%s\\n' \"$4\""

    // $1 the themes folder, $2 the backups folder, $3 the backup's name, $4 its theme
    readonly property string _restoreScript: "src=\"$2/$3\"; dest=\"$1/$4.json\"; part=\"$1/.$4.json.restore\"; "
        + "if [ -L \"$2\" ]; then echo \"theme-backups is a link: nothing restored\" >&2; exit 1; fi; "
        + "if [ -L \"$src\" ] || [ ! -f \"$src\" ]; then echo \"No such backup\" >&2; exit 1; fi; "
        + "if [ -e \"$dest\" ] || [ -L \"$dest\" ]; then echo \"A theme named $4 exists\" >&2; exit 1; fi; "
        + "mkdir -p -- \"$1\" || { echo \"could not make the themes folder\" >&2; exit 1; }; "
        + "rm -f -- \"$part\"; "
        + "if ! cat -- \"$src\" > \"$part\" || ! mv -- \"$part\" \"$dest\"; then rm -f -- \"$part\"; echo \"could not restore the theme\" >&2; exit 1; fi"

    function _folder(path) {
        return typeof path === "string" && path !== "";
    }

    // Copies theme `name`'s file from `themesDir` into `backupsDir`. `done({ ok, problem,
    // backup })` — `backup` the backup's name ("" when the theme has no file), `problem` the
    // first line of what went wrong. false when it cannot start (one runs, no folder, a name
    // that is no theme's)
    function backUp(themesDir, backupsDir, name, done) {
        const file = ThemeRules.themeBackupName(name, new Date().toISOString());
        if (running || !_folder(themesDir) || !_folder(backupsDir) || file === "")
            return false;
        return _start(["sh", "-c", _backUpScript, "sh", themesDir, backupsDir, name, file], done,
                      (ok, output) => ({ backup: ok ? output.trim() : "" }));
    }

    // Copies backup `file` (a bare name of the pattern) from `backupsDir` back into `themesDir`
    // as its theme. `done({ ok, problem, theme })`. false when it cannot start (one runs, no
    // folder, a name that is no backup)
    function restore(themesDir, backupsDir, file, done) {
        const parsed = ThemeRules.parseThemeBackupName(file);
        if (running || !_folder(themesDir) || !_folder(backupsDir) || typeof file !== "string" || file.includes("/") || !parsed.ok)
            return false;
        return _start(["sh", "-c", _restoreScript, "sh", themesDir, backupsDir, file, parsed.theme], done,
                      () => ({ theme: parsed.theme }));
    }

    function _start(command, done, answer) {
        _running = true;
        _done = done ?? null;
        _answer = answer;
        _process.command = command;
        _process.running = true;
        return true;
    }

    property Process _process: Process {
        stdout: StdioCollector { id: _output }
        stderr: StdioCollector { id: _errors }
        onExited: code => {
            const done = root._done;
            const answer = root._answer;
            root._done = null;
            root._answer = null;
            root._running = false;
            const first = (_errors.text.trim().split("\n")[0] ?? "").slice(0, 200);
            const result = Object.assign({ ok: code === 0, problem: code === 0 ? "" : first !== "" ? first : "could not copy" },
                                         answer(code === 0, _output.text));
            if (typeof done === "function")
                done(result);
        }
    }
}
