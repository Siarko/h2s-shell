pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.components

// The theme files on disk: where they live, reading and writing them, and changing them
// for the settings — themes created, copied, re-parented, renamed and deleted (the Themes
// page), curves written, renamed and deleted in the library (the Curves page). Theme
// resolves what these files say, and keeps the drafts; a change here reloads it.
Singleton {
    id: root

    // Where theme files live, next to the config
    readonly property string themesDir: Config.path.toString().replace(/^file:\/\//, "")
        .replace(/\/[^\/]*$/, "") + "/themes"
    // Beside the themes folder, not in it, so that it lists themes only: the curves
    // library, shared by every theme (ThemeRules, "Curves"), and the drafts — changes made
    // in the settings, not saved yet, one file per theme (ThemeRules, "Drafts")
    readonly property string _configDir: themesDir.replace(/\/[^\/]*$/, "")
    readonly property string curvesPath: _configDir + "/curves.json"
    readonly property string draftsDir: _configDir + "/theme-drafts"
    // A deleted theme's file is kept here first (ThemeBackups), restorable
    readonly property string backupsDir: _configDir + "/theme-backups"

    function themePath(name) {
        return themesDir + "/" + name + ".json";
    }

    function draftPath(name) {
        return draftsDir + "/" + name + ".json";
    }

    Component.onCompleted: {
        if (!Config.readOnly)
            _ensureThemesDir.running = true;
    }

    // ---- Reading and writing ----

    // A JSON file: { exists, value, error } — `value` null when it is missing or does not
    // parse, `error` saying why it does not ("" otherwise)
    function readFile(path) {
        _reader.path = path;
        // The reader keeps what it read last for an unchanged path
        _reader.reload();
        const text = _reader.text();
        if (text === "")
            return { exists: false, value: null, error: "" };
        try {
            return { exists: true, value: JSON.parse(text), error: "" };
        } catch (error) {
            return { exists: true, value: null, error: error.message };
        }
    }

    FileView {
        id: _reader
        blockAllReads: true
        printErrors: false
    }

    // Writes `value` as JSON to `path`. A FileView skips a write of the text it already
    // holds, and after a change of path it still held the previous file's (until a read
    // caught up — and reading a file that does not exist leaves it) — so a theme renamed
    // or copied, the same text under a new name, was never written. Clearing the path
    // first empties it.
    function write(path, value) {
        _writer.path = "";
        _writer.path = path;
        _writer.reload();
        _writer.setText(JSON.stringify(value, null, 2) + "\n");
    }

    FileView {
        id: _writer
        blockWrites: true
        blockAllReads: true
        printErrors: false
    }

    function writeTheme(name, theme) {
        write(themePath(name), theme);
        Theme.reloadQuietly();
    }

    // Files are removed one at a time, in the order asked
    property var _removals: []

    function remove(path) {
        _removals = _removals.concat([path]);
        if (!_remover.running)
            _nextRemoval();
    }

    function _nextRemoval() {
        if (_removals.length === 0)
            return;
        _remover.command = ["rm", "-f", "--", _removals[0]];
        _removals = _removals.slice(1);
        _remover.running = true;
    }

    Process {
        id: _remover
        onExited: {
            root._nextRemoval();
            Qt.callLater(Theme.reload);
        }
    }

    // ---- Managing themes (the Themes page) ----

    // Names of the profiles whose own `appearance.theme` is `name`, and "global" when it
    // is pinned — what renaming or deleting it changes
    function setters(name) {
        return ThemeRules.retargetTheme(Profiles.profiles, Profiles.globals, name, name).changed;
    }

    // A new theme extending `base`
    function createTheme(name, base) {
        if (Config.readOnly || !ThemeRules.validThemeName(name) || Theme.themeExists(name))
            return false;
        writeTheme(name, { extends: base || "default" });
        return true;
    }

    // A copy of the file of `source` under a new name: the same values, extending the
    // same theme
    function duplicateTheme(source, name) {
        if (Config.readOnly || !ThemeRules.validThemeName(name) || Theme.themeExists(name))
            return false;
        if (Theme.themeNames.includes(source) && !ThemeRules.hasOwn(Theme.themeFiles, source)) {
            console.warn("[Theme] Not copying", themePath(source), "— it does not parse");
            return false;
        }
        writeTheme(name, JSON.parse(JSON.stringify(ThemeRules.ownValue(Theme.themeFiles, source) ?? {})));
        return true;
    }

    // Points the theme `name` at a new parent, unless that would make a cycle
    function setExtends(name, base) {
        const themes = Theme.themeFiles;
        if (Config.readOnly || !ThemeRules.hasOwn(themes, name))
            return false;
        if (ThemeRules.extendsCycle(name, base, themeName => ThemeRules.ownValue(themes, themeName) ?? null))
            return false;
        const theme = JSON.parse(JSON.stringify(themes[name]));
        if (base === "default")
            delete theme.extends;
        else
            theme.extends = base;
        writeTheme(name, theme);
        return true;
    }

    // Renames a theme: the new file is written first, then the themes extending it and the
    // profiles using it follow, and the old file goes. The config is backed up first.
    function renameTheme(oldName, newName) {
        const themes = Theme.themeFiles;
        if (Config.readOnly || oldName === "default" || !ThemeRules.hasOwn(themes, oldName)
                || !ThemeRules.validThemeName(newName) || Theme.themeExists(newName))
            return false;
        writeTheme(newName, themes[oldName]);
        const changed = ThemeRules.renameExtends(themes, oldName, newName);
        for (const name of Object.keys(changed))
            writeTheme(name, changed[name]);
        _retargetProfiles(oldName, newName);
        Theme.moveDraft(oldName, newName);
        remove(themePath(oldName));
        return true;
    }

    // Deletes a theme: its file is kept in the theme backups first — not kept, nothing
    // changes —, then the themes extending it extend its parent instead, the profiles using
    // it fall back to the default theme (the config backed up first), and the file goes.
    // Deletes run one at a time, in the order asked. true when it is under way
    function deleteTheme(name) {
        if (Config.readOnly || !Theme.themeNames.includes(name) || _deletes.includes(name))
            return false;
        _deletes = _deletes.concat([name]);
        if (!_backups.running)
            _nextDelete();
        return true;
    }

    property var _deletes: []

    property ThemeBackups _backups: ThemeBackups {}

    function _nextDelete() {
        if (_deletes.length === 0 || _backups.running)
            return;
        const name = _deletes[0];
        _deletes = _deletes.slice(1);
        const started = _backups.backUp(themesDir, backupsDir, name, result => {
            root._backedUp(name, result);
            root._nextDelete();
        });
        if (!started) {
            console.warn("[Theme] Not deleting", themePath(name), "— its file could not be kept");
            _nextDelete();
        }
    }

    function _backedUp(name, result) {
        if (!result.ok) {
            console.warn("[Theme] Not deleting", themePath(name), "— its file could not be kept:", result.problem);
            return;
        }
        // What changed while the copy was made wins: a theme gone or settings that cannot be
        // saved now are left alone
        if (Config.readOnly || !Theme.themeNames.includes(name))
            return;
        if (result.backup !== "")
            console.log("[Theme] Theme", name, "kept in", backupsDir + "/" + result.backup);
        const changed = ThemeRules.withoutExtends(Theme.themeFiles, name);
        for (const other of Object.keys(changed))
            writeTheme(other, changed[other]);
        _retargetProfiles(name, "default");
        Theme.dropDraft(name);
        remove(themePath(name));
    }

    // Puts the kept file `backup` (a name in the theme backups) back as its theme, unless a
    // theme of that name exists; the backup stays. → "" started, else why not
    function restoreTheme(backup) {
        if (Config.readOnly)
            return "Settings are read-only";
        if (!ThemeRules.parseThemeBackupName(backup).ok || String(backup).includes("/"))
            return "Not a theme backup: " + String(backup ?? "").slice(0, 80);
        const started = _backups.restore(themesDir, backupsDir, backup, result => {
            if (result.ok)
                console.log("[Theme] Theme", result.theme, "restored from", backupsDir + "/" + backup);
            else
                console.warn("[Theme] Not restoring", backupsDir + "/" + backup, "—", result.problem);
            Qt.callLater(Theme.reload);
            root._nextDelete();
        });
        return started ? "" : "Busy: try again";
    }

    function _retargetProfiles(oldName, newName) {
        const result = ThemeRules.retargetTheme(Profiles.profiles, Profiles.globals, oldName, newName);
        if (result.changed.length === 0)
            return;
        Profiles.backUpConfig();
        console.log("[Theme] Theme", oldName, "is now", newName, "in:", result.changed.join(", "));
        Config.profiles = JSON.stringify(result.profiles);
        Config.globals = JSON.stringify(result.globals);
    }

    // ---- The curves library (the Curves page) ----

    // Where the library curve `name` is used: [{ theme, role }]
    function curveUsages(name) {
        return ThemeRules.curveUsages(Theme.themeFiles, name);
    }

    // Reads the library file for changing it: null when it does not parse — rewriting it
    // would lose the user's hand edits
    function _libraryForEdit() {
        const file = readFile(curvesPath);
        if (file.exists && file.value === null) {
            console.warn("[Theme] Not changing", curvesPath, "— it does not parse");
            return null;
        }
        return file.value ?? {};
    }

    function _writeLibrary(library) {
        write(curvesPath, library);
        Qt.callLater(Theme.reload);
    }

    // Adds or replaces the curve `name` ([x1, y1, x2, y2] or Qt's form)
    function writeCurve(name, points) {
        if (Config.readOnly || !ThemeRules.validCurveName(name) || ThemeRules.curvePoints(points) === null)
            return false;
        const library = _libraryForEdit();
        if (library === null)
            return false;
        ThemeRules.putOwn(library, name, points);
        _writeLibrary(library);
        return true;
    }

    // Removes the curve `name`; themes still naming it fall back (ThemeRules.fallbackCurve)
    function deleteCurve(name) {
        if (Config.readOnly)
            return false;
        const library = _libraryForEdit();
        if (library === null || !ThemeRules.hasOwn(library, name))
            return false;
        delete library[name];
        _writeLibrary(library);
        return true;
    }

    // Renames the curve `oldName` and points every theme using it at the new name. A theme
    // file that does not parse is left alone, and reported.
    function renameCurve(oldName, newName) {
        if (Config.readOnly || !ThemeRules.validCurveName(newName))
            return false;
        const library = _libraryForEdit();
        const renamed = library === null ? null : ThemeRules.libraryWithRename(library, oldName, newName);
        if (renamed === null)
            return false;
        _writeLibrary(renamed);
        const changed = ThemeRules.renameCurveIn(Theme.themeFiles, oldName, newName);
        for (const name of Object.keys(changed))
            writeTheme(name, changed[name]);
        for (const name of Theme.themeNames) {
            if (!ThemeRules.hasOwn(Theme.themeFiles, name))
                console.warn("[Theme] Not renaming curve", oldName, "in", themePath(name), "— it does not parse");
        }
        return true;
    }

    // FileView does not create folders: the themes folder is made at start, for drafts and
    // saves
    Process {
        id: _ensureThemesDir
        command: ["mkdir", "-p", root.themesDir, root.draftsDir]
    }
}
