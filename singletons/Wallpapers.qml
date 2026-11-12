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
        _listing.command = ["sh", "-c",
            "if [ -d \"$1\" ]; then echo folder; find -L \"$1\" -mindepth 1 -maxdepth \"$2\" -type f -printf '%P\\n' 2>/dev/null;"
            + " elif [ -f \"$1\" ]; then echo file; else echo missing; fi",
            "sh", source, String(Math.max(0, depth) + 1)];
        _listing.request();
    }

    property bool _redrawWhenListed: true

    function _drawAll() {
        if (mode !== "random")
            return;
        draws = WallpaperRules.draw(_slotsShown, pool, {}, draws, Math.random);
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
        if (_slotsShown.every(slot => slot in kept) && Object.keys(kept).length === Object.keys(draws).length)
            return;
        draws = WallpaperRules.draw(_slotsShown, pool, kept, {}, Math.random);
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
    on_SlotsShownChanged: _drawMissing()

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
            root.kind = kindLine;
            root.files = kindLine === "folder"
                ? lines.slice(1).filter(path => WallpaperRules.isImage(path)).sort((a, b) => a.localeCompare(b))
                : [];
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
                shown: shown
            }, null, 2);
        }
    }
}
