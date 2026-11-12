pragma Singleton

import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import qs.singletons.io

// The wallpaper's live state: the source listed, the random draw, the day, and whether
// another program draws a wallpaper too. Which image a screen shows is WallpaperRules';
// the surfaces (wallpaper/WallpaperSurface.qml) ask fileFor(). Nothing runs while the
// feature is off. docs/plans/wallpapers.md has the model.
//
//   h2s-shell ipc call wallpaper shuffle     (draw again; re-read the folder)
//   h2s-shell ipc call wallpaper status
Singleton {
    id: root

    readonly property bool enabled: Profiles.value("wallpaper.enabled") === true
    readonly property string source: WallpaperRules.expand(Profiles.value("wallpaper.source") ?? "", Quickshell.env("HOME") ?? "")
    readonly property int depth: Profiles.value("wallpaper.depth") ?? 2
    readonly property string scope: Profiles.value("wallpaper.scope") ?? "everywhere"
    readonly property string mode: Profiles.value("wallpaper.mode") ?? "fixed"
    readonly property int interval: Profiles.value("wallpaper.interval") ?? 0
    readonly property var subset: Profiles.value("wallpaper.subset") ?? []
    readonly property var settings: ({
        scope: root.scope,
        mode: root.mode,
        subset: root.subset,
        assignments: Profiles.value("wallpaper.assignments") ?? {},
        pinned: Profiles.value("wallpaper.pinned") ?? {},
        weekdays: Profiles.value("wallpaper.weekdays") ?? []
    })

    // What the source is ("file", "folder", "missing"; "" before it is listed) and, for a
    // folder, its images relative to it, sorted
    property string kind: ""
    property var files: []
    // The random draw: { slot: path }; kept for slots not on screen, so a workspace comes
    // back with its image
    property var draws: ({})
    // Today, for the weekday mode; moved on at midnight
    property date today: new Date()
    // Another program's wallpaper: [{ monitor, namespace }] (WallpaperRules.foreignBackgrounds)
    property var foreign: []
    // The background colour each screen's image gave ({ screenName: "#rrggbb" }), read by
    // its surface when `wallpaper.backgroundFromImage` is on
    property var edgeColors: ({})

    function setEdgeColor(screenName: string, color: string): void {
        if (edgeColors[screenName] === color)
            return;
        const colors = Object.assign({}, edgeColors);
        colors[screenName] = color;
        edgeColors = colors;
    }

    readonly property var pool: WallpaperRules.pool(files, subset)
    readonly property var _slotsShown: WallpaperRules.slotsShown(scope, Workspaces.screens)
    // What is drawn for: the slots shown, and per workspace also the workspaces there are
    // and the ones beside those shown — so their images can be decoded before a switch
    // reaches them (WallpaperSurface preloads them)
    readonly property var _slotsDrawn: {
        if (scope !== "workspace")
            return _slotsShown;
        const numbers = new Set(_slotsShown.map(Number));
        for (const workspace of Workspaces.workspaces?.values ?? []) {
            if (workspace.id > 0)
                numbers.add(workspace.id);
        }
        for (const shown of _slotsShown.map(Number)) {
            numbers.add(shown + 1);
            if (shown > 1)
                numbers.add(shown - 1);
        }
        return Array.from(numbers).sort((a, b) => a - b).map(String);
    }

    // The image a screen would show on `workspace` (absolute; "" for none) — for preloading
    function workspaceFileFor(screenName: string, workspace: int): string {
        const screens = Workspaces.screens;
        const file = WallpaperRules.fileFor(settings, { name: screenName, workspace: workspace }, {
            kind: kind, source: source, files: files, draws: draws, date: today, screens: screens
        });
        return typeof file === "string" ? file : "";
    }

    // The image the screen named `screenName` shows (absolute), "" for none, null to keep
    // what it shows
    function fileFor(screenName: string): var {
        const screens = Workspaces.screens;
        const screen = screens.find(entry => entry.name === screenName) ?? { name: screenName, workspace: 0 };
        return WallpaperRules.fileFor(settings, screen, {
            kind: kind, source: source, files: files, draws: draws, date: today, screens: screens
        });
    }

    // Draws again (random mode) and re-reads the source, whatever the mode: an image
    // added to the folder is seen
    function shuffle(): void {
        _redrawWhenListed = true;
        refresh();
    }

    function refresh(): void {
        if (!enabled || source === "") {
            kind = enabled ? "missing" : "";
            files = [];
            return;
        }
        // Each file with its modification time and size ("1731400000.5 2351234 a/b.jpg"):
        // part of the key of its copies resized to a screen, so a replaced image gets new ones
        _listing.command = ["sh", "-c",
            "if [ -d \"$1\" ]; then echo folder; find -L \"$1\" -mindepth 1 -maxdepth \"$2\" -type f -printf '%T@ %s %P\\n' 2>/dev/null;"
            + " elif [ -f \"$1\" ]; then echo file; stat -L -c '%Y %s .' \"$1\"; else echo missing; fi",
            "sh", source, String(Math.max(0, depth) + 1)];
        _listing.request();
    }

    property bool _redrawWhenListed: true

    function _drawAll() {
        if (mode !== "random")
            return;
        draws = WallpaperRules.draw(_slotsDrawn, pool, {}, draws, Math.random);
    }

    // Slots shown without a draw (a workspace seen for the first time, a drawn image
    // gone): drawn, the others kept
    function _drawMissing() {
        if (mode !== "random" || kind !== "folder")
            return;
        const present = new Set(pool);
        const kept = {};
        for (const slot in draws) {
            if (present.has(draws[slot]))
                kept[slot] = draws[slot];
        }
        if (_slotsDrawn.every(slot => slot in kept) && Object.keys(kept).length === Object.keys(draws).length)
            return;
        draws = WallpaperRules.draw(_slotsDrawn, pool, kept, {}, Math.random);
    }

    // The source or how deep to look changed: listed again, a little later, so a few
    // changes at once (a profile switch) list once
    onEnabledChanged: _relist.restart()
    onSourceChanged: _relist.restart()
    onDepthChanged: _relist.restart()
    // What the draw is for changed: drawn again
    onScopeChanged: _drawAll()
    onModeChanged: _drawAll()
    onSubsetChanged: _drawAll()
    on_SlotsDrawnChanged: _drawMissing()

    Timer {
        id: _relist
        interval: 50
        onTriggered: {
            root.kind = "";
            root.refresh();
            root._findForeign();
        }
    }

    Component.onCompleted: _relist.restart()

    CommandQuery {
        id: _listing
        onDone: lines => {
            const kindLine = lines[0] ?? "missing";
            const stamps = {};
            const listed = [];
            for (const line of lines.slice(1)) {
                const match = /^(\S+) (\S+) (.*)$/.exec(line);
                if (!match)
                    continue;
                stamps[match[3]] = match[1] + " " + match[2];
                if (kindLine === "folder" && WallpaperRules.isImage(match[3]))
                    listed.push(match[3]);
            }
            root._stamps = stamps;
            root.kind = kindLine;
            root.files = listed.sort((a, b) => a.localeCompare(b));
            if (root._redrawWhenListed) {
                root._redrawWhenListed = false;
                root._drawAll();
            } else {
                root._drawMissing();
            }
        }
    }

    Timer {
        id: _intervalTimer
        interval: Math.max(60000, root.interval)
        repeat: true
        running: root.enabled && root.mode === "random" && root.interval > 0
        onTriggered: root.shuffle()
    }

    // Midnight, for the weekday mode: the interval follows `today`, so each firing arms
    // the next; repeating, or the timer would stop itself and drop the `running` binding
    Timer {
        id: _midnight
        repeat: true
        running: root.enabled && root.mode === "weekday"
        interval: {
            const now = root.today;
            const next = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 0, 0, 5);
            return Math.max(1000, next.getTime() - now.getTime());
        }
        onTriggered: root.today = new Date()
        onRunningChanged: if (running) root.today = new Date()
    }

    // ── Another program's wallpaper ──
    // Its surface is on the background layer too, and which one covers the other is not
    // ours to decide; Hyprland tells when a layer surface opens or closes, `hyprctl layers`
    // whose it is (as ScreenKeyboard does for the keyboard)
    function _findForeign() {
        if (!enabled) {
            foreign = [];
            return;
        }
        _layers.running = true;
    }

    Connections {
        target: Hyprland
        enabled: root.enabled
        function onRawEvent(event) {
            if (event.name === "openlayer" || event.name === "closelayer")
                _layersSettle.restart();
        }
    }

    Timer {
        id: _layersSettle
        interval: 300
        onTriggered: root._findForeign()
    }

    Process {
        id: _layers
        command: ["hyprctl", "layers", "-j"]
        property string _output: ""
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => _layers._output += data
        }
        onRunningChanged: {
            if (running)
                return;
            let found = [];
            try {
                found = WallpaperRules.foreignBackgrounds(JSON.parse(_output));
            } catch (error) {
                found = [];
            }
            _output = "";
            root.foreign = root.enabled ? found : [];
        }
    }

    // ── Copies resized to the screen ──
    // A large image takes long to decode and scale (a 19 MB PNG 586 ms on the Framework, a
    // JPEG at the screen's size 80 ms), so each image is resized once to each screen it
    // shows on, with vipsthumbnail, and kept as a JPEG in ~/.cache/h2s_shell/wallpapers —
    // named by WallpaperRules.screenCopyName, so a larger screen never shows a smaller copy.
    // Made in the background, at low priority, for the images shown and about to be
    // (WallpaperSurface asks with prepare()); until one is made, the image itself shows.
    // The oldest copies go past `copiesLimit`. Without vipsthumbnail, the images themselves.

    readonly property string copiesDir: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/h2s_shell/wallpapers"
    readonly property int copiesLimit: 300 * 1024 * 1024
    property bool canMakeCopies: false
    // The copies there are: { name: true }
    property var copies: ({})
    // "modification-time size" by path relative to the folder ("." for a single file)
    property var _stamps: ({})
    property var _queue: []
    property var _failed: ({})
    property int _madeSincePrune: 0
    property bool _copiesListed: false

    function _stampOf(path) {
        if (kind === "file")
            return _stamps["."] ?? "";
        const prefix = source + "/";
        return path.startsWith(prefix) ? (_stamps[path.slice(prefix.length)] ?? "") : "";
    }

    function _copyName(path, width, height, fit) {
        return WallpaperRules.screenCopyName(path, _stampOf(path), Math.round(width), Math.round(height), fit);
    }

    // What to load for `path` on a screen of `width` × `height` physical pixels with `fit`:
    // its copy when there is one, else the image itself
    function displayPath(path: string, width: real, height: real, fit: string): string {
        const name = _copyName(path, width, height, fit);
        return name !== "" && copies[name] === true ? copiesDir + "/" + name : path;
    }

    // Asks for `path`'s copy for such a screen, made in the background if there is none
    function prepare(path: string, width: real, height: real, fit: string): void {
        const name = _copyName(path, width, height, fit);
        // Queued before the copies are listed too (the shell's first image asks at once);
        // kept short, in case vipsthumbnail turns out to be missing
        if (name === "" || copies[name] === true || _failed[name] === true || _queue.some(job => job.name === name) || _queue.length >= 40)
            return;
        _queue = _queue.concat([{ name: name, path: path, width: Math.round(width), height: Math.round(height), fit: fit }]);
        _makeNext();
    }

    function _makeNext() {
        if (!canMakeCopies || !_copiesListed || _making.running || _queue.length === 0)
            return;
        // Made meanwhile (listed since it was asked for): nothing to do
        if (copies[_queue[0].name] === true) {
            _queue = _queue.slice(1);
            Qt.callLater(_makeNext);
            return;
        }
        const job = _queue[0];
        _making.job = job;
        // Written beside, then moved in: a half-written copy is never taken for a copy
        _making.command = ["sh", "-c",
            "mkdir -p \"$1\" && nice -n 19 vipsthumbnail \"$2\" -s \"$3\" $4 -o \"$1/.$5.part.jpg[Q=92,strip]\" 2>/dev/null"
            + " && mv -f \"$1/.$5.part.jpg\" \"$1/$5\"",
            "sh", copiesDir, job.path, job.width + "x" + job.height, job.fit === "cover" ? "-m centre" : "", job.name];
        _making.running = true;
    }

    Process {
        id: _making
        property var job: null
        onExited: (exitCode, exitStatus) => {
            const job = _making.job;
            root._queue = root._queue.filter(entry => entry.name !== job.name);
            if (exitCode === 0) {
                const made = Object.assign({}, root.copies);
                made[job.name] = true;
                root.copies = made;
                if (++root._madeSincePrune >= 10)
                    root._prune();
            } else {
                const failed = Object.assign({}, root._failed);
                failed[job.name] = true;
                root._failed = failed;
                console.warn("Wallpaper: no copy made of", job.path);
            }
            Qt.callLater(root._makeNext);
        }
    }

    // The copies there are, and whether they can be made
    CommandQuery {
        id: _copiesList
        command: ["sh", "-c", "command -v vipsthumbnail > /dev/null && echo can-make; ls -1 \"$1\" 2>/dev/null | grep -E '^[0-9a-f]{32}\\.jpg$'", "sh", root.copiesDir]
        onDone: lines => {
            root.canMakeCopies = lines.includes("can-make");
            root._copiesListed = true;
            const found = {};
            for (const line of lines) {
                if (line !== "can-make")
                    found[line] = true;
            }
            root.copies = found;
            root._makeNext();
        }
    }

    // Past the limit, the oldest copies go; then they are listed again
    function _prune() {
        _madeSincePrune = 0;
        if (!_pruning.running)
            _pruning.running = true;
    }

    Process {
        id: _pruning
        command: ["sh", "-c",
            "cd \"$1\" 2>/dev/null || exit 0; total=0; for f in $(ls -t -- *.jpg 2>/dev/null); do"
            + " size=$(stat -c %s -- \"$f\"); total=$((total + size)); [ $total -gt $2 ] && rm -f -- \"$f\"; done",
            "sh", root.copiesDir, String(root.copiesLimit)]
        onExited: _copiesList.request()
    }

    Timer {
        id: _startCopies
        interval: 2000
        running: root.enabled
        onTriggered: root._prune()
    }

    IpcHandler {
        target: "wallpaper"

        function shuffle(): string {
            if (!root.enabled)
                return "The wallpaper is off (Settings → Wallpaper).";
            root.shuffle();
            return "";
        }

        function status(): string {
            // Object.fromEntries is not in Qt's JavaScript
            const shown = {};
            for (const screen of Workspaces.screens)
                shown[screen.name] = root.fileFor(screen.name);
            return JSON.stringify({
                enabled: root.enabled, source: root.source, kind: root.kind, depth: root.depth,
                images: root.files.length, pool: root.pool.length, scope: root.scope, mode: root.mode,
                draws: root.draws, foreign: root.foreign, edgeColors: root.edgeColors,
                copies: { canMake: root.canMakeCopies, made: Object.keys(root.copies).length, queued: root._queue.length },
                shown: shown
            }, null, 2);
        }
    }
}
