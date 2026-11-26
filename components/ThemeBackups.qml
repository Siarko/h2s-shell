import QtQuick
import Quickshell.Io
import qs.singletons

// Keeps a theme's file before it is deleted, and puts a kept one back: the backups live in a
// folder of their own beside the themes folder (theme-backups), one file per deleted theme,
// named by ThemeRules.themeBackup (a hashed name with a record of the theme's name beside it
// when the name cannot stand in the backup's), readable by the user only. backUp() copies the
// theme file there, synced to disk, and leaves the file for the caller to remove once the copy
// is made; restore() copies a backup back as its theme, never over a theme of that name (a
// hard link to a finished copy: it fails when the name is taken), and keeps the backup.
// Temporary files have short names of their own, so a theme name of any length a file can
// have works. When theme-backups is a link nothing is copied either way (its files would land,
// or be read, wherever it points) and it is said. The names are checked here; they reach the
// fixed scripts as arguments. One at a time.
QtObject {
    id: root

    readonly property bool running: _process.running || _running

    property bool _running: false
    property var _done: null
    property var _answer: null

    // $1 the themes folder, $2 the backups folder, $3 the theme, $4 the backup's name, $5 the
    // record's text ("" none). Prints the backup's name, nothing when the theme has no file;
    // each problem one line on stderr
    readonly property string _backUpScript: "umask 077; src=\"$1/$3.json\"; backups=$2; dest=\"$backups/$4\"; record=\"$dest.theme\"; part=\"$backups/.part-$$\"; "
        + "if [ -L \"$backups\" ]; then echo \"theme-backups is a link: nothing kept\" >&2; exit 1; fi; "
        + "if [ ! -e \"$src\" ] && [ ! -L \"$src\" ]; then exit 0; fi; "
        + "mkdir -p -- \"$backups\" || { echo \"could not make theme-backups\" >&2; exit 1; }; "
        + "if [ -L \"$backups\" ] || [ ! -d \"$backups\" ]; then echo \"theme-backups is no folder: nothing kept\" >&2; exit 1; fi; "
        + "if [ -e \"$dest\" ] || [ -L \"$dest\" ] || [ -e \"$record\" ] || [ -L \"$record\" ]; then echo \"$4 exists already\" >&2; exit 1; fi; "
        + "rm -f -- \"$part\"; "
        + "if [ -n \"$5\" ]; then "
        + "if ! printf '%s' \"$5\" > \"$part\" || ! { sync -- \"$part\" 2> /dev/null || sync; } || ! ln -- \"$part\" \"$record\"; then rm -f -- \"$part\"; echo \"could not keep the theme's name\" >&2; exit 1; fi; "
        + "rm -f -- \"$part\"; fi; "
        + "if ! cp -- \"$src\" \"$part\" || ! { sync -- \"$part\" 2> /dev/null || sync; } || ! ln -- \"$part\" \"$dest\"; then "
        + "rm -f -- \"$part\"; [ -z \"$5\" ] || rm -f -- \"$record\"; echo \"could not copy the theme\" >&2; exit 1; fi; "
        + "rm -f -- \"$part\"; sync -- \"$backups\" 2> /dev/null; "
        + "printf '%s\\n' \"$4\""

    // $1 the themes folder, $2 the backups folder, $3 the backup's name, $4 its theme
    readonly property string _restoreScript: "src=\"$2/$3\"; dest=\"$1/$4.json\"; part=\"$1/.restore-$$\"; "
        + "if [ -L \"$2\" ]; then echo \"theme-backups is a link: nothing restored\" >&2; exit 1; fi; "
        + "if [ -L \"$src\" ] || [ ! -f \"$src\" ]; then echo \"No such backup\" >&2; exit 1; fi; "
        + "if [ -e \"$dest\" ] || [ -L \"$dest\" ]; then echo \"A theme named $4 exists\" >&2; exit 1; fi; "
        + "mkdir -p -- \"$1\" || { echo \"could not make the themes folder\" >&2; exit 1; }; "
        + "rm -f -- \"$part\"; "
        + "if ! cat -- \"$src\" > \"$part\" || ! { sync -- \"$part\" 2> /dev/null || sync; }; then rm -f -- \"$part\"; echo \"could not restore the theme\" >&2; exit 1; fi; "
        + "if ! ln -- \"$part\" \"$dest\"; then rm -f -- \"$part\"; "
        + "if [ -e \"$dest\" ] || [ -L \"$dest\" ]; then echo \"A theme named $4 exists\" >&2; else echo \"could not restore the theme\" >&2; fi; exit 1; fi; "
        + "rm -f -- \"$part\""

    function _folder(path) {
        return typeof path === "string" && path !== "";
    }

    // Copies theme `name`'s file from `themesDir` into `backupsDir`. `done({ ok, problem,
    // backup })` — `backup` the backup's name ("" when the theme has no file), `problem` the
    // first line of what went wrong. false when it cannot start (one runs, no folder, a name
    // no theme file can have)
    function backUp(themesDir, backupsDir, name, done) {
        const backup = ThemeRules.themeBackup(name, new Date().toISOString());
        if (running || !_folder(themesDir) || !_folder(backupsDir) || backup.file === "")
            return false;
        return _start(["sh", "-c", _backUpScript, "sh", themesDir, backupsDir, name, backup.file, backup.record], done,
                      (ok, output) => ({ backup: ok ? output.trim() : "" }));
    }

    property FileView _reader: FileView {
        blockAllReads: true
        printErrors: false
    }

    // The theme backup `file` (a bare name of the pattern) in `backupsDir` restores as: its
    // record's name, else its own name's (ThemeRules.restoredTheme); "" no backup name
    function themeOf(backupsDir, file) {
        if (!_folder(backupsDir) || typeof file !== "string" || file.includes("/") || !ThemeRules.parseThemeBackupName(file).ok)
            return "";
        _reader.path = "";
        _reader.path = backupsDir + "/" + ThemeRules.themeBackupRecord(file);
        _reader.reload();
        let record = null;
        try {
            record = JSON.parse(_reader.text() ?? "");
        } catch (error) {}
        return ThemeRules.restoredTheme(file, record);
    }

    // Copies backup `file` from `backupsDir` back into `themesDir` as its theme (themeOf).
    // `done({ ok, problem, theme })`. false when it cannot start (one runs, no folder, a name
    // that is no backup)
    function restore(themesDir, backupsDir, file, done) {
        const theme = themeOf(backupsDir, file);
        if (running || !_folder(themesDir) || theme === "")
            return false;
        return _start(["sh", "-c", _restoreScript, "sh", themesDir, backupsDir, file, theme], done,
                      () => ({ theme: theme }));
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
