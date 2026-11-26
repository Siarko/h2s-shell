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
// It is the explicit gc() that collects the wrappers, so the case is reached whichever way the
// collector runs otherwise: sliced (Qt's default) or whole (QV4_GC_TIMELIMIT=0), both seen.
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
    // be held by the engine's registers), then two full collections: the first may only end
    // one already under way, which marked them before they were destroyed (seen in a shard
    // whose other suites had the collector running: no owner reached the case)
    function _drop(owners) {
        _goneBefore = _tally.gone;
        _droppedBefore = _tally.dropped;
        for (let index = 0; index < owners.length; index++)
            _destroyAt(owners, index);
        owners.length = 0;
        _destroySpare();
        gc();
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
            _sidePanels();
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

    // ---- SidePanelHost: the open panel told it closed ----
    property var _closedFor: []
    property Component _sideOwner: Component {
        TeardownOwner {
            id: owner
            property alias host: _host
            TeardownProbe { tally: suite._tally }
            SidePanelHost {
                id: _host
            }
        }
    }
    property var _sideOwners: []

    function _sidePanels() {
        _closedFor = [];
        _sideOwners = _make(_sideOwner, _owners);
        _sideOwners.forEach(owner => owner.host.show(_panelStandIn, reason => suite._closedFor.push(reason)));
        assert(_sideOwners.every(owner => owner.host.current === _panelStandIn), "SidePanelHost: each host shows the panel");
        _drop(_sideOwners);
        _then("the side panel hosts' owners are destroyed", _allGone, () => {
            _reachedDropped("SidePanelHost");
            assertEqual(JSON.stringify(_closedFor), JSON.stringify(Array(_owners).fill(ApiElementRules.sidePanelEvent(true, "pageGone", false).reason)),
                        "SidePanelHost: destroyed with a panel open, the panel is told it closed (the page went)");
            _modals();
        });
    }
    property Item _panelStandIn: Item {}

    // ---- SettingsModalHost: the asker answered, cancelled ----
    property var _answers: []
    property Component _modalOwner: Component {
        TeardownOwner {
            id: owner
            property alias host: _host
            TeardownProbe { tally: suite._tally }
            SettingsModalHost {
                id: _host
            }
        }
    }
    property var _modalOwners: []

    function _modals() {
        _answers = [];
        _modalOwners = _make(_modalOwner, _owners);
        _modalOwners.forEach((owner, index) => owner.host.ask({ title: "Teardown", subject: { index: index } }, answer => suite._answers.push(answer)));
        assert(_modalOwners.every(owner => owner.host.open), "SettingsModalHost: each host's modal is open");
        _drop(_modalOwners);
        _then("the modal hosts' owners are destroyed", _allGone, () => {
            _reachedDropped("SettingsModalHost");
            assertEqual(JSON.stringify(_answers.map(answer => [answer.button, answer.cancelled, answer.reason, answer.subject.index]).sort()),
                        JSON.stringify([0, 1, 2, 3, 4, 5].map(index => ["cancel", true, "window", index])),
                        "SettingsModalHost: destroyed while open, the asker is answered: cancelled for \"window\", with its subject");
            _hoverTips();
        });
    }

    // ---- HoverTip: its handler on the target ----
    property Item _tipTarget: Item {}
    property Component _tipOwner: Component {
        TeardownOwner {
            id: owner
            TeardownProbe { tally: suite._tally }
            Api.HoverTip {
                target: suite._tipTarget
                text: "Teardown"
            }
        }
    }
    property var _tipOwners: []
    function _handlersOnTarget() {
        return Array.from(_tipTarget.data).filter(child => child instanceof HoverHandler).length;
    }

    function _hoverTips() {
        const before = _handlersOnTarget();
        _tipOwners = _make(_tipOwner, _owners);
        // (a handler replaced while the tooltip is built goes with the event loop)
        _then("the tooltips' handlers are made", () => _handlersOnTarget() - before === _owners, () => _drop(_tipOwners));
        _then("the tooltips' owners are destroyed", _allGone, () => {
            _reachedDropped("HoverTip");
            _then("the handlers are deleted", () => _handlersOnTarget() === before, () => {
                assertEqual(_handlersOnTarget(), before, "HoverTip: destroyed, its handler leaves the target");
                _pamLists();
            });
        });
    }

    // ---- PamRuleList: the page's Flickable a drag holds ----
    // A page Flickable for each list
    property Component _flickable: Component {
        Flickable {
            width: 100
            height: 100
            contentHeight: 400
        }
    }
    property var _flicks: []
    property Component _pamOwner: Component {
        TeardownOwner {
            id: owner
            property alias list: _list
            TeardownProbe { tally: suite._tally }
            PamRuleList {
                id: _list
            }
        }
    }
    property var _pamOwners: []

    function _pamLists() {
        _pamOwners = _make(_pamOwner, _owners);
        _flicks = _pamOwners.map(() => _flickable.createObject(null));
        // In a Flickable: only its parent item, the owner still has no parent object
        _pamOwners.forEach((owner, index) => owner.parent = _flicks[index].contentItem);
        _pamOwners.forEach(owner => owner.list._beginDrag("row"));
        assert(_flicks.every(flick => !flick.interactive), "PamRuleList: a drag holds the page's Flickable still");
        // Out of the Flickable again: an item in a shown tree keeps what is declared inside it
        _pamOwners.forEach(owner => owner.parent = null);
        _drop(_pamOwners);
        _then("the rule lists' owners are destroyed", _allGone, () => {
            _reachedDropped("PamRuleList");
            assert(_flicks.every(flick => flick.interactive), "PamRuleList: destroyed mid-drag, the page scrolls again");
            _flicks.forEach(flick => flick.destroy());
            _flicks = [];
            _modulePages();
        });
    }

    // ---- ModulesSettings: an install's preview cancelled ----
    property var _cancelled: []
    property QtObject _installer: QtObject {
        function cancelPreview(job) {
            suite._cancelled.push(job);
        }
    }
    property Component _modulesOwner: Component {
        TeardownOwner {
            id: owner
            property alias page: _page
            TeardownProbe { tally: suite._tally }
            ModulesSettings {
                id: _page
                installer: suite._installer
            }
        }
    }
    property var _modulesOwners: []

    function _modulePages() {
        _cancelled = [];
        _modulesOwners = _make(_modulesOwner, _owners);
        _modulesOwners.forEach((owner, index) => owner.page._installJob = 10 + index);
        _drop(_modulesOwners);
        _then("the modules pages' owners are destroyed", _allGone, () => {
            _reachedDropped("ModulesSettings");
            assertEqual(JSON.stringify(_cancelled.slice().sort()), JSON.stringify([10, 11, 12, 13, 14, 15]),
                        "ModulesSettings: destroyed with an install's preview waiting, the preview is cancelled");
        });
    }
}
