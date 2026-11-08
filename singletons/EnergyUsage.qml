pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick

// Use per app over time, estimated (EnergyRules; docs/plans/battery-popup.md, stage 3). On
// battery only, every 30 s: a sample of what each process has used
// (scripts/energy-sample.py) and the battery's power; the interval's energy, split between
// the system and the apps, goes into the current five-minute bucket. The battery popup
// sums buckets: since the last full charge (unplugged at 95 % or more), or a stretch picked
// on its graph (usageBetween).
//
// Kept in $XDG_STATE_HOME/h2s_shell/ — the buckets in energy-usage.jsonl, one line each,
// appended as each closes (never the whole file rewritten while running), for 7 days, the
// graph's longest span; `since` in energy-usage.json. Not per shell copy: the package and
// a checkout share them.
Singleton {
    id: root

    // Closed buckets, oldest first, and the one filling now (null between them)
    property var buckets: []
    property var _current: null
    // Since when "since full charge" counts (seconds; 0: nothing counted yet), and whether
    // that is a full charge seen or only when counting began
    property double since: 0
    property bool fromFullCharge: false

    readonly property int _keepSeconds: 7 * 24 * 3600

    // { system, apps: { app: Wh }, count } for [from, to) in seconds, the filling bucket
    // included
    function usageBetween(from, to) {
        return EnergyRules.sumBuckets(root._current ? root.buckets.concat([root._current]) : root.buckets, from, to);
    }

    // Since the last full charge (or since counting began)
    readonly property var sinceCharge: (buckets, _current, since > 0
        ? usageBetween(EnergyRules.bucketStart(since), Date.now() / 1000 + EnergyRules.bucketSeconds)
        : { system: 0, apps: {}, count: 0 })

    // The last sample and when it was taken; the recent power, for the baseline
    property var _lastSample: null
    property double _lastTime: 0
    property var _powers: []
    // An interval longer than this (asleep, the shell stopped) is not counted: what was
    // used in it is unknown
    readonly property int _longestInterval: 120

    readonly property var _device: UPower.displayDevice
    readonly property bool _sampling: _device.ready && _device.isPresent && UPower.onBattery && _loaded

    readonly property string _directory: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/h2s_shell"
    readonly property string _bucketsPath: _directory + "/energy-usage.jsonl"
    property int _loadedFiles: 0
    readonly property bool _loaded: _loadedFiles >= 2

    on_SamplingChanged: {
        // Not across time off battery: the next sample starts a fresh interval, and the
        // bucket that was filling is closed
        root._lastSample = null;
        if (!_sampling)
            root._closeBucket();
        else
            _sample.running = true;
    }

    Timer {
        interval: 30000
        repeat: true
        running: root._sampling
        onTriggered: _sample.running = true
    }

    // A new charge: watched on every state change
    property int _previousState: 0
    Connections {
        target: root._device
        function onStateChanged() {
            const state = root._device.state;
            if (EnergyRules.startsNewCharge(root._previousState, state, root._device.percentage * 100)) {
                root.since = Date.now() / 1000;
                root.fromFullCharge = true;
                root._saveMeta();
            }
            root._previousState = state;
        }
    }
    Component.onCompleted: root._previousState = root._device.state

    function _add(sample) {
        const now = Date.now() / 1000;
        const watts = root._device.changeRate;
        if (watts > 0)
            root._powers = root._powers.concat([watts]).slice(-60);
        const previous = root._lastSample;
        const seconds = now - root._lastTime;
        root._lastSample = sample.processes;
        root._lastTime = now;
        if (!previous || seconds <= 0 || seconds > root._longestInterval || watts <= 0)
            return;
        const part = EnergyRules.attribute(watts, seconds, EnergyRules.usage(previous, sample.processes),
                                           EnergyRules.baseline(root._powers));
        // The interval goes into the bucket of its end; one past that closes the last
        const start = EnergyRules.bucketStart(now);
        if (root._current && root._current.t !== start)
            root._closeBucket();
        root._current = EnergyRules.addToBucket(root._current ?? { t: start, system: 0, apps: {} }, part);
        if (root.since === 0) {
            root.since = now;
            root._saveMeta();
        }
    }

    function _closeBucket() {
        if (!root._current)
            return;
        const bucket = root._current;
        root._current = null;
        root.buckets = root.buckets.concat([bucket]);
        _append.lines = _append.lines.concat([JSON.stringify(bucket)]);
        if (!_append.running)
            _append.flush();
    }

    function _saveMeta() {
        _meta.setText(JSON.stringify({ since: root.since, fromFullCharge: root.fromFullCharge }));
    }

    // Appends closed buckets to the file, one line each
    Process {
        id: _append
        property var lines: []
        function flush() {
            if (lines.length === 0)
                return;
            command = ["sh", "-c", "printf '%s\\n' \"$1\" >> \"$2\"", "sh", lines.join("\n"), root._bucketsPath];
            lines = [];
            running = true;
        }
        onRunningChanged: if (!running) flush()
    }

    Process {
        id: _sample
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/energy-sample.py"]
        property string _output: ""
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => _sample._output += data
        }
        onRunningChanged: {
            if (running)
                return;
            const output = _output;
            _output = "";
            try {
                root._add(JSON.parse(output));
            } catch (error) {
                console.warn("[EnergyUsage] could not read a sample:", error);
            }
        }
    }

    // The folder made first, then both files read once
    Process {
        id: _mkdir
        command: ["mkdir", "-p", root._directory]
        Component.onCompleted: running = true
        onRunningChanged: {
            if (running)
                return;
            _meta.path = root._directory + "/energy-usage.json";
            _bucketFile.path = root._bucketsPath;
        }
    }

    FileView {
        id: _meta
        printErrors: false
        onLoaded: {
            try {
                const saved = JSON.parse(text());
                root.since = saved.since ?? 0;
                root.fromFullCharge = saved.fromFullCharge ?? false;
            } catch (error) {
                console.warn("[EnergyUsage] could not read since when it counts:", error);
            }
            root._loadedFiles++;
        }
        onLoadFailed: root._loadedFiles++
    }

    // Read at start; older lines than 7 days dropped, the file rewritten once if any were
    FileView {
        id: _bucketFile
        printErrors: false
        onLoaded: {
            const all = [];
            for (const line of text().split("\n")) {
                if (line.trim() === "")
                    continue;
                try {
                    all.push(JSON.parse(line));
                } catch (error) {
                    // A line cut short (the shell stopped mid-write): left out
                }
            }
            const kept = EnergyRules.keepBuckets(all, Date.now() / 1000 - root._keepSeconds);
            root.buckets = kept;
            if (kept.length < all.length)
                setText(kept.map(bucket => JSON.stringify(bucket)).join("\n") + (kept.length > 0 ? "\n" : ""));
            root._loadedFiles++;
        }
        onLoadFailed: root._loadedFiles++
    }
}
