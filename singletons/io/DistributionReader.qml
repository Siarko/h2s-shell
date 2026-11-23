import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons

// Reads what DistributionRules decides the distribution from: each distribution's
// distribution.json in the shell's tree, then the markers they name and os-release. The
// shell's one instance is Distribution. Every place it reads is a property, so a suite
// points it at made-up files (tests/DistributionReadingTest.qml).
//
// Files are read as text without blocking (FileView), never run; a file that is not there
// is told from one that could not be read. Read once when made; refresh() reads everything
// again, and an answer from before a newer refresh() is dropped. Until every reading has
// answered, `detection` is DistributionRules' unknown answer.
QtObject {
    id: root

    // TestSeams.distribution: names the distribution, "" to detect it
    property string override: ""
    // Where the distributions' directories are
    property string distributionsDirectory: Quickshell.shellDir + "/distributions"
    // Put before every system path read (os-release, the markers): a suite's scratch tree
    property string fileRoot: ""
    // TestSeams.distributionHold: while this file is there (looked at every 100 ms),
    // nothing is read — a test of what waits for the answer; "" for none
    property string holdWhile: ""

    // DistributionRules.detect's answer: { ready, id, facts, how, problem }
    readonly property var detection: DistributionRules.detect(_readings)

    function refresh() {
        const generation = ++_generation;
        _readings = { override: override, manifests: {}, markers: {}, osRelease: DistributionRules.osReleasePaths.map(() => null) };
        if (holdWhile !== "") {
            _hold.generation = generation;
            _hold.restart();
            return;
        }
        _readAll(generation);
    }

    // The hold: once its file is gone, the reading goes on
    property Timer _hold: Timer {
        property int generation: 0
        interval: 100
        repeat: true
        onTriggered: root._load(generation, root.holdWhile, reading => {
            if (reading.state === "absent" && root._hold.running) {
                root._hold.stop();
                root._readAll(root._hold.generation);
            }
        })
    }

    function _readAll(generation) {
        for (const id of DistributionRules.ids) {
            _load(generation, distributionsDirectory + "/" + id + "/distribution.json", reading => {
                const manifests = Object.assign({}, root._readings.manifests);
                manifests[id] = reading.state === "text" ? reading.text : { failed: true };
                root._readings = Object.assign({}, root._readings, { manifests: manifests });
                root._readSystem(generation);
            });
        }
    }

    property var _readings: ({})
    property int _generation: 0

    // Once every manifest has answered: the markers they name, and os-release
    function _readSystem(generation) {
        if (DistributionRules.ids.some(id => _readings.manifests[id] === undefined))
            return;
        const manifests = DistributionRules.ids.map(id => DistributionRules.manifest(_readings.manifests[id], id));
        const markers = [];
        for (const manifest of manifests) {
            for (const path of manifest?.markers ?? []) {
                if (!markers.includes(path))
                    markers.push(path);
            }
        }
        for (const path of markers) {
            _load(generation, fileRoot + path, reading => {
                const answers = Object.assign({}, root._readings.markers);
                answers[path] = reading.state === "text" ? "present" : reading.state;
                root._readings = Object.assign({}, root._readings, { markers: answers });
            });
        }
        DistributionRules.osReleasePaths.forEach((path, index) => {
            _load(generation, fileRoot + path, reading => {
                const answers = root._readings.osRelease.slice();
                answers[index] = reading;
                root._readings = Object.assign({}, root._readings, { osRelease: answers });
            });
        });
    }

    // Reads one file → answer({ state: "text" | "absent" | "failed", text }), unless a newer
    // refresh() came first
    function _load(generation, path, answer) {
        _fileComponent.createObject(root, { path: path, answer: reading => {
            if (generation === root._generation)
                answer(reading);
        } });
    }

    // One load of one file, gone once it answered
    property Component _fileComponent: Component {
        FileView {
            id: load
            property var answer: null
            printErrors: false
            onLoaded: done({ state: "text", text: text() })
            onLoadFailed: error => done({ state: error === FileViewError.FileNotFound ? "absent" : "failed", text: "" })

            function done(reading) {
                const answer = load.answer;
                load.answer = null;
                answer?.(reading);
                load.destroy();
            }
        }
    }

    // A new override reads everything again (late answers of the old one are dropped)
    onOverrideChanged: {
        if (_completed)
            refresh();
    }
    property bool _completed: false

    Component.onCompleted: {
        _completed = true;
        refresh();
    }
}
