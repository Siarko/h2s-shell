pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The theme files on disk: where they live, reading and writing them, and changing them
// for the settings — themes created, copied, re-parented, renamed and deleted (the Themes
// page), curves written, renamed and deleted in the library (the Curves page) — plus the
// one-time move of the bar's geometry into themes. Theme resolves what these files say,
// and keeps the drafts; a change here reloads it.
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

    function themePath(name) {
        return themesDir + "/" + name + ".json";
    }

    function draftPath(name) {
        return draftsDir + "/" + name + ".json";
    }

    Component.onCompleted: {
        if (!Config.readOnly)
            _ensureThemesDir.running = true;
        _migrateBarLayoutIfNeeded();
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
        if (Theme.themeNames.includes(source) && !(source in Theme.themeFiles)) {
            console.warn("[Theme] Not copying", themePath(source), "— it does not parse");
            return false;
        }
        writeTheme(name, JSON.parse(JSON.stringify(Theme.themeFiles[source] ?? {})));
        return true;
    }

    // Points the theme `name` at a new parent, unless that would make a cycle
    function setExtends(name, base) {
        const themes = Theme.themeFiles;
        if (Config.readOnly || !(name in themes))
            return false;
        if (ThemeRules.extendsCycle(name, base, themeName => themes[themeName] ?? null))
            return false;
        const theme = Object.assign({}, themes[name]);
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
        if (Config.readOnly || oldName === "default" || !(oldName in themes)
                || !ThemeRules.validThemeName(newName) || Theme.themeExists(newName))
            return false;
        writeTheme(newName, themes[oldName]);
        const changed = ThemeRules.renameExtends(themes, oldName, newName);
        for (const name in changed)
            writeTheme(name, changed[name]);
        _retargetProfiles(oldName, newName);
        Theme.moveDraft(oldName, newName);
        remove(themePath(oldName));
        return true;
    }

    // Deletes a theme: the themes extending it extend its parent instead, and the
    // profiles using it fall back to the default theme. The config is backed up first.
    function deleteTheme(name) {
        if (Config.readOnly || !Theme.themeNames.includes(name))
            return false;
        const changed = ThemeRules.withoutExtends(Theme.themeFiles, name);
        for (const other in changed)
            writeTheme(other, changed[other]);
        _retargetProfiles(name, "default");
        Theme.dropDraft(name);
        remove(themePath(name));
        return true;
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
        library[name] = points;
        _writeLibrary(library);
        return true;
    }

    // Removes the curve `name`; themes still naming it fall back (ThemeRules.fallbackCurve)
    function deleteCurve(name) {
        if (Config.readOnly)
            return false;
        const library = _libraryForEdit();
        if (library === null || !(name in library))
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
        if (library === null || !(oldName in library) || (newName in library))
            return false;
        const renamed = {};
        for (const name of Object.keys(library))
            renamed[name === oldName ? newName : name] = library[name];
        _writeLibrary(renamed);
        const changed = ThemeRules.renameCurveIn(Theme.themeFiles, oldName, newName);
        for (const name in changed)
            writeTheme(name, changed[name]);
        for (const name of Theme.themeNames) {
            if (!(name in Theme.themeFiles))
                console.warn("[Theme] Not renaming curve", oldName, "in", themePath(name), "— it does not parse");
        }
        return true;
    }

    // ---- Migration: the bar's geometry moves from profiles into themes, once ----
    readonly property string _barLayoutMigration: "theme.barLayout"

    function _migrateBarLayoutIfNeeded() {
        if (!Config.ready || Config.readOnly || Config.profiles === "" || _pendingMigration !== null
                || Config.migratedKeys.includes(_barLayoutMigration))
            return;
        // Geometry from before profiles that never reached one (the per-key migration
        // marks the keys it copied)
        const legacy = Config.migratedKeys.includes("bar.layout.barHeight")
            ? undefined : Profiles.oldConfig().bar?.layout;
        const result = ThemeRules.themesFromBarLayout(Profiles.profiles, Profiles.globals, legacy,
            name => readFile(themePath(name)).exists);
        if (result.themes.length > 0)
            Profiles.backUpConfig();
        _pendingMigration = result;
        // The theme files first, once their folder exists, then the profiles that pick them
        _ensureThemesDir.running = true;
    }

    property var _pendingMigration: null

    function _finishMigration() {
        const result = _pendingMigration;
        _pendingMigration = null;
        if (result === null || Config.migratedKeys.includes(_barLayoutMigration))
            return;
        for (const entry of result.themes)
            writeTheme(entry.name, entry.theme);
        if (result.themes.length > 0) {
            // Always shown, not only in debug: a one-time change to the user's config
            console.log("[Theme] Moved the bar geometry into themes:",
                        result.themes.map(entry => entry.name + " (" + Object.keys(entry.theme.bar).join(", ") + ")").join("; "));
        }
        Config.profiles = JSON.stringify(result.profiles);
        Config.globals = JSON.stringify(result.globals);
        Config.migratedKeys = Config.migratedKeys.concat([_barLayoutMigration]);
    }

    // FileView does not create folders: the themes folder is made at start, for
    // drafts and saves, and before the migration writes into it
    Process {
        id: _ensureThemesDir
        command: ["mkdir", "-p", root.themesDir, root.draftsDir]
        onExited: root._finishMigration()
    }

    Connections {
        target: Config
        function onReadyChanged() { Qt.callLater(root._migrateBarLayoutIfNeeded) }
        function onProfilesChanged() { Qt.callLater(root._migrateBarLayoutIfNeeded) }
    }
}
