pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.singletons

// The music visualiser's levels, 0–1 per band, left and right channel: from cava while a
// player is there, an ambient wave when cava gives nothing, falling flat while paused.
// Runs only while something shows it — the music panel registers with addViewer() and
// removeViewer() — so cava does not run with the panel closed.
Singleton {
    id: root

    property var leftBars: []
    property var rightBars: []
    // How loud the bass is, 0–1: the lowest few bands of both channels, averaged (the even
    // glow's level). The left channel ends with its bass, the right starts with it.
    readonly property real bass: {
        const bands = leftBars.slice(-4).concat(rightBars.slice(0, 4));
        return bands.length === 0 ? 0 : bands.reduce((sum, level) => sum + level, 0) / bands.length;
    }
    // Whether cava has sent levels since it started; until then the ambient wave shows
    property bool useCava: false

    property int _viewers: 0
    readonly property bool _active: _viewers > 0 && Music.hasPlayer
    property real _ambientPhase: 0

    function addViewer() {
        _viewers++;
    }

    function removeViewer() {
        _viewers = Math.max(0, _viewers - 1);
    }

    // cava runs from a config generated from the shell's own scripts/cava.ini, with the
    // frame rate the active profile sets ("polling.visualizer.fps"); the template stays
    // the one place to edit the rest of cava's settings
    readonly property int _cavaFps: Profiles.value("polling.visualizer.fps") ?? 60

    on_CavaFpsChanged: _restartCava()
    on_ActiveChanged: {
        _restartCava();
        // Shown again, it starts afresh, as a newly opened panel did
        if (!_active) {
            leftBars = [];
            rightBars = [];
            useCava = false;
        }
    }

    // Writes the config and (re)starts cava while active. A Process must not be started by
    // a declarative `running:` binding — see CLAUDE.md.
    function _restartCava() {
        _cava.running = false;
        if (!_active)
            return;
        const template = _cavaTemplate.text();
        _cavaGenerated.setText(template.replace(/^framerate\s*=.*$/m, "framerate = " + _cavaFps));
        Qt.callLater(() => _cava.running = root._active);
    }

    FileView {
        id: _cavaTemplate
        path: Qt.resolvedUrl("../scripts/cava.ini").toString().replace("file://", "")
        blockLoading: true
    }

    FileView {
        id: _cavaGenerated
        path: Quickshell.cachePath("cava.ini")
        blockWrites: true
        // Only ever written; it does not exist until the first write, and that is fine
        printErrors: false
    }

    // Real audio data from cava: a line of "level;level;…", the left channel's bands treble
    // to bass, then the right's bass to treble — mirrored, as cava draws stereo, with the
    // bass in the middle
    Process {
        id: _cava
        command: ["cava", "-p", _cavaGenerated.path]
        stdout: SplitParser {
            onRead: line => {
                const levels = line.split(";").filter(part => part !== "").map(part => parseInt(part) / 100.0);
                root.useCava = true;
                root.leftBars = levels.slice(0, levels.length / 2);
                root.rightBars = levels.slice(levels.length / 2);
            }
        }
    }

    // Ambient fallback when cava is unavailable
    Timer {
        interval: 33
        running: root._active && Music.playing && !root.useCava
        repeat: true
        onTriggered: {
            root._ambientPhase += 0.08;
            const left = [], right = [];
            for (let i = 0; i < 24; i++) {
                left.push(0.3 + 0.25 * Math.sin(root._ambientPhase + i * 0.25) + 0.12 * Math.sin(root._ambientPhase * 2.3 + i * 0.6));
                right.push(0.3 + 0.25 * Math.sin(root._ambientPhase + i * 0.25 + 0.8) + 0.12 * Math.sin(root._ambientPhase * 2.3 + i * 0.6 + 0.4));
            }
            root.leftBars = left;
            root.rightBars = right;
        }
    }

    // Decay bars to flat line when paused
    Timer {
        interval: 100
        running: root._active && !Music.playing
        repeat: true
        onTriggered: {
            root.leftBars = root.leftBars.map(value => Math.max(0, value - 0.05));
            root.rightBars = root.rightBars.map(value => Math.max(0, value - 0.05));
        }
    }
}
