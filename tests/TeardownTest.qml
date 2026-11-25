import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.singletons
import qs.singletons.io as Io
import qs.singletons.network
import qs.panels.settings
import qs.api as Api

// What items undo at their destruction, done also where Qt has dropped their properties and
// functions before it runs: each subject is declared inside an owner of a derived type
// (TeardownOwner) made without a parent, destroyed, and its wrapper collected before the
// deferred delete — then everything declared inside reads undefined, 0, "" or false in its
// Component.onDestruction, and a function of its own is "not a function". A probe beside the
// subject (TeardownProbe) shows each step reached that case; an error line fails the run.
TestCase {
    id: suite
    suiteName: "Teardown"
    asynchronous: true

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
                suite.finish();
                return;
            }
            waited += interval;
            let ready = false;
            try {
                ready = step.condition();
            } catch (error) {}
            if (!ready && waited < 10000)
                return;
            waited = 0;
            suite._steps.shift();
            if (!ready)
                suite.fail("timed out waiting: " + step.description);
            try {
                step.action();
            } catch (error) {
                suite.fail(step.description + ": " + error);
            }
        }
    }

    // Each owner's probe counts here: { gone, dropped }
    property var _tally: ({ gone: 0, dropped: 0 })
    property int _goneBefore: 0
    property int _droppedBefore: 0
    readonly property int _owners: 6

    // Destroys the owners kept in `owners` (an array emptied here) and collects their wrappers
    // before the deferred deletes: one more owner after them (the last one destroyed may still
    // be held by the engine's registers), then a full collection
    function _drop(owners) {
        _goneBefore = _tally.gone;
        _droppedBefore = _tally.dropped;
        for (let index = 0; index < owners.length; index++)
            _destroyAt(owners, index);
        owners.length = 0;
        _destroySpare();
        gc();
    }
    function _destroyAt(owners, index) {
        owners[index].destroy();
        owners[index] = null;
    }
    function _destroySpare() {
        _spare.createObject(null).destroy();
    }
    // Made without a parent, `count` of them, kept in the returned array
    function _make(component, count, properties) {
        const owners = [];
        for (let index = 0; index < count; index++)
            owners.push(component.createObject(null, properties ? properties(index) : {}));
        return owners;
    }
    // The owners destroyed (and the spare), and some of them past Qt's dropping
    function _allGone() {
        return _tally.gone >= _goneBefore + _owners + 1;
    }
    function _reachedDropped(what) {
        assert(_tally.dropped > _droppedBefore, what + ": the case was reached (owners destroyed after Qt dropped what is inside them: "
               + (_tally.dropped - _droppedBefore) + " of " + (_tally.gone - _goneBefore) + ")");
    }

    property Component _spare: Component {
        TeardownOwner {
            id: owner
            TeardownProbe { tally: suite._tally }
        }
    }

    // ---- NetworkHold: the network pages' watch and scans ----
    property Component _holdOwner: Component {
        TeardownOwner {
            id: owner
            property alias hold: _hold
            TeardownProbe { tally: suite._tally }
            NetworkHold {
                id: _hold
                wanted: true
                scans: true
            }
        }
    }
    property var _holds: []
    property int _watchersBefore: 0
    property int _scansBefore: 0

    function runAsync() {
        _watchersBefore = NetworkOverview._watchers;
        _scansBefore = WifiManager._scanHolders;
        _holds = _make(_holdOwner, _owners);
        assertEqual((NetworkOverview._watchers - _watchersBefore) + " " + (WifiManager._scanHolders - _scansBefore), _owners + " " + _owners,
                    "NetworkHold: each wanted hold watches the overview and holds the scans");
        _holds[0].hold.scans = false;
        assertEqual(WifiManager._scanHolders - _scansBefore, _owners - 1, "… `scans` off: its scans let go, its watch kept");
        _holds[0].hold.scans = true;
        _drop(_holds);
        _then("the holds' owners are destroyed", _allGone, () => {
            _reachedDropped("NetworkHold");
            assertEqual(NetworkOverview._watchers + " " + WifiManager._scanHolders, _watchersBefore + " " + _scansBefore,
                        "NetworkHold: destroyed, every hold is let go");
            _anchors();
        });
        _clock.start();
    }

    // ---- AnchorBlock: the anchor paths reported to Anchors ----
    property Component _anchorOwner: Component {
        TeardownOwner {
            id: owner
            property string anchorBase: "settings.teardown"
            TeardownProbe { tally: suite._tally }
            AnchorBlock {
                anchor: "block"
            }
        }
    }
    property var _anchorOwners: []
    property string _anchorsBefore: ""

    function _anchors() {
        _anchorsBefore = JSON.stringify(Anchors.live);
        _anchorOwners = _make(_anchorOwner, _owners);
        const reported = Object.keys(Anchors.live).filter(path => path.startsWith("settings.teardown"));
        assertEqual(reported.length === 1 ? Anchors.live[reported[0]] : -1, _owners, "AnchorBlock: each block reports its path");
        _drop(_anchorOwners);
        _then("the blocks' owners are destroyed", _allGone, () => {
            _reachedDropped("AnchorBlock");
            assertEqual(JSON.stringify(Anchors.live), _anchorsBefore, "AnchorBlock: destroyed, its path is taken back");
            _handles();
        });
    }

    // ---- NotificationHandle: the server's signals ----
    property QtObject _server: QtObject {
        signal notificationClosed(int id, int reason)
        signal actionInvoked(int id, string identifier)
        function tracks(id) {
            return true;
        }
        function progressIds(run, handle) {
            return [];
        }
    }
    // Takes the show and never answers: the handle stays waiting on the server
    property QtObject _silentRunner: QtObject {
        property int starts: 0
        function start(argv, options) {
            starts++;
        }
    }
    property Component _handleOwner: Component {
        TeardownOwner {
            id: owner
            property var handle: _handle
            TeardownProbe { tally: suite._tally }
            Io.NotificationHandle {
                id: _handle
                server: suite._server
                runner: suite._silentRunner
                wanted: Notifier.progressContent("Teardown", {}, "teardown-run", "1")
            }
        }
    }
    property var _handleOwners: []

    function _handles() {
        const startsBefore = _silentRunner.starts;
        _handleOwners = _make(_handleOwner, _owners);
        assertEqual(_silentRunner.starts - startsBefore, _owners, "NotificationHandle: each handle sent its notification");
        _drop(_handleOwners);
        _then("the handles' owners are destroyed", _allGone, () => {
            _reachedDropped("NotificationHandle");
            // Nothing of a handle runs any more (an error line fails the run)
            _server.notificationClosed(0, 1);
            _server.actionInvoked(0, "default");
            _stores();
        });
    }

    // ---- ModuleStore: what waits to be written ----
    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-teardown-test-" + Date.now()
    property Component _storeOwner: Component {
        TeardownOwner {
            id: owner
            property alias store: _store
            property string moduleId
            TeardownProbe { tally: suite._tally }
            Api.ModuleStore {
                id: _store
                moduleId: owner.moduleId
                directory: suite._scratch
                writable: true
            }
        }
    }
    property var _storeOwners: []
    property string _written: ""
    property bool _reading: false

    function _stores() {
        _storeOwners = _make(_storeOwner, _owners, index => ({ moduleId: "teardown" + index }));
        _then("the stores have read their (missing) files", () => _storeOwners.every(owner => owner.store.ready), () => {
            _storeOwners.forEach((owner, index) => owner.store.set("kept", index));
            _drop(_storeOwners);
        });
        _then("the stores' owners are destroyed", _allGone, () => {
            _reachedDropped("ModuleStore");
            _readStores();
        });
        _then("the stores' files are read", () => !_reading, () => {
            assertEqual(_written, [0, 1, 2, 3, 4, 5].map(index => "{\"kept\":" + index + "}").join(" "),
                        "ModuleStore: destroyed within a second of a change, what waited is written");
            Quickshell.execDetached(["rm", "-rf", "--", _scratch]);
        });
    }

    property Process _reader: Process {
        stdout: StdioCollector {
            onStreamFinished: suite._written = text.trim().split("\n").join(" ")
        }
        onExited: suite._reading = false
    }
    function _readStores() {
        _reading = true;
        _reader.command = ["sh", "-c", "for i in 0 1 2 3 4 5; do cat \"$1/teardown$i.json\" 2>/dev/null || printf 'missing'; echo; done", "sh", _scratch];
        _reader.running = true;
    }
}
