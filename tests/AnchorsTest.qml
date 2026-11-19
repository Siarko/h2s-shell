import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.api
import qs.components
import qs.singletons

// The anchor blocks and their hosts (components/AnchorBlock.qml, AnchorContent.qml,
// SettingsPage.qml) on a fixture view, with a host of the suite's own (ModuleHost) and a
// table of its own: a page (settings.fixture) holding a block with a host at each of the four
// placements (AnchorFixtureBlock, "box") and one with no anchor. Two fixture modules
// (tests/fixtures/modules/places-a, places-b) put elements there: each placement in
// the one order, top to bottom; several modules by module id; the documented context and the
// module's handle; a place not offered and a placement not taken in the module's status; a
// module turned off takes its elements, on brings them back, the other module's element
// stays the same object; a reload builds them anew; a slot read as its anchor; Anchors.live
// following the blocks; the view opened and closed over and over. Asynchronous; after
// ModuleRegistriesTest, since both turn modules off through Config.disabledModules.
TestCase {
    id: suite
    suiteName: "Anchors"
    asynchronous: true
    timeLimitMs: 40000

    // A suite that must be done first
    property var after: null

    readonly property string fixtures: Quickshell.shellDir + "/tests/fixtures/modules"
    readonly property var table: [
        _row("settings.fixture", "page", ["prepend", "append"], "{ editIndex }"),
        _row("settings.fixture.box", "section", ["before", "after", "prepend", "append"], "{ boxed }"),
        _row("settings.general", "page", ["append"], "{ editIndex }")
    ]

    property ModuleHost host: ModuleHost {
        logStates: false
    }
    property var _steps: []
    property var _savedDisabled: []
    property var _views: []
    property var _view: null
    property var _betaItem: null
    property var _betaElement: null
    property int _betaContexts: 0
    property var _alphaElement: null
    property int _cycles: 0
    property real _waitUntil: 0

    function _row(path, kind, placements, context) {
        return { path: path, kind: kind, placements: placements, takes: "", marks: false, context: context, scope: "", since: "1.20",
                 where: "AnchorsTest's fixture view" };
    }

    function _then(description, condition, action, timeoutMs) {
        _steps.push({ description: description, condition: condition, action: action, deadline: timeoutMs ?? 10000 });
    }

    property Timer _clock: Timer {
        interval: 25
        repeat: true
        property int waited: 0
        onTriggered: {
            const step = suite._steps[0];
            if (!step) {
                stop();
                suite._end();
                return;
            }
            waited += interval;
            let ready = false;
            try {
                ready = step.condition();
            } catch (error) {
                ready = false;
            }
            if (!ready && waited < step.deadline)
                return;
            waited = 0;
            suite._steps.shift();
            if (!ready)
                suite.fail("timed out waiting: " + step.description);
            try {
                step.action();
            } catch (error) {
                suite.fail("threw in \"" + step.description + "\": " + error);
            }
        }
    }

    function _end() {
        for (const view of _views)
            view?.destroy();
        _views = [];
        host.unload();
        Config.disabledModules = _savedDisabled;
        finish();
    }

    // ---- The fixture view: a layer surface in a corner, its root given a base ----

    property Component _viewComponent: Component {
        PanelWindow {
            id: window

            property string base: "settings.fixture"
            property alias page: page
            property alias inside: inside
            property alias box: box
            property alias boxContent: boxContent
            property alias plain: plain

            anchors {
                top: true
                left: true
            }
            implicitWidth: 400
            implicitHeight: 700
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "h2s-tests"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // What the settings window's page loader will be: the base of the view's root
            Item {
                property string anchorBase: window.base
                anchors.fill: parent

                SettingsPage {
                    id: page
                    anchors.fill: parent
                    title: "Fixture"
                    host: suite.host
                    context: ({ editIndex: 2 })

                    Text {
                        id: inside
                        text: "the page's own content"
                    }

                    AnchorFixtureBlock {
                        id: box
                        anchor: "box"
                        context: ({ boxed: true })
                        Layout.fillWidth: true

                        Text {
                            id: boxContent
                            text: "the box's own content"
                        }
                    }

                    // No anchor: not addressable, adds no level
                    AnchorFixtureBlock {
                        id: plain
                        title: "Plain"
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }

    function _open(base) {
        const view = _viewComponent.createObject(suite, { base: base ?? "settings.fixture" });
        _views.push(view);
        return view;
    }

    function _close(view) {
        _views = _views.filter(each => each !== view);
        view.destroy();
    }

    // ---- Helpers ----

    function _settled() {
        return host.statuses.length > 0 && !host.statuses.some(status => status.state === "pending") && !host.checkingFiles;
    }

    function _has(list, fragment) {
        return (list ?? []).some(entry => String(entry).includes(fragment));
    }

    function _ready(hostItem, count) {
        return hostItem.items.length === count && hostItem.items.every(item => item.ready);
    }

    // The elements of view `view` all built (on the page's end, places-b's too while it is on)
    function _allBuilt(view) {
        const appended = host.status("places-b")?.state === "loaded" ? 3 : 2;
        return _ready(view.page.prependHost, 1) && _ready(view.page.appendHost, appended) && _ready(view.box.beforeHost, 1)
            && _ready(view.box.prependHost, 1) && _ready(view.box.appendHost, 1) && _ready(view.box.afterHost, 1);
    }

    // Top to bottom, what a view shows, as [name, y in the page]
    function _sequence(view) {
        const y = item => item.mapToItem(view.page, 0, 0).y;
        const page = view.page;
        const box = view.box;
        return [["page.prepend", y(page.prependHost.items[0])], ["page content", y(view.inside)], ["box.before", y(box.beforeHost.items[0])],
                ["box frame", y(box.frame)], ["box.prepend", y(box.prependHost.items[0])], ["box content", y(view.boxContent)],
                ["box.append", y(box.appendHost.items[0])], ["box.after", y(box.afterHost.items[0])],
                ["page.append 1", y(page.appendHost.items[0])], ["page.append 2", y(page.appendHost.items[1])],
                ["page.append 3", y(page.appendHost.items[2])]];
    }

    function _inOrder(view) {
        if (!_allBuilt(view))
            return false;
        const sequence = _sequence(view);
        return sequence.every((entry, index) => index === 0 || entry[1] > sequence[index - 1][1]);
    }

    function _names(hostItem) {
        return hostItem.items.map(item => item.item?.objectName ?? "?").join(",");
    }

    function _live(prefix) {
        return Object.keys(Anchors.live).filter(path => path === prefix || path.startsWith(prefix + ".")).sort()
            .map(path => path + ":" + Anchors.live[path]).join(",");
    }

    function runAsync() {
        _then("the suite before is done, the config read", () => (after === null || after.done) && Config.ready, () => {
            _savedDisabled = host._plainList(Config.disabledModules);
            Config.disabledModules = [];
            // This shell's table, as the API hands it out
            assertEqual(ModuleRules.anchorTableProblems(ModuleRules.anchorTable).join("; "), "", "this shell's anchor table is well formed");
            assert(!ModuleRules.anchorTable.some(row => /lock|screensaver/.test(row.path)), "… nothing on the lock screen or the screensaver");
            assertEqual(JSON.stringify(Api.anchors), JSON.stringify(ModuleRules.anchorTable), "Api.anchors: the anchor table");
            assert(Object.isFrozen(Api.anchors) && Api.anchors.every(row => Object.isFrozen(row) && Object.isFrozen(row.placements)), "… frozen, each row and its placements");
            assertEqual(ModuleRules.anchorTableProblems(table).join("; "), "", "the suite's table is well formed");

            host.anchorTable = table;
            _view = _open();
        }, 80000);
        _then("the view is up with no module", () => _view.page.flickable.contentHeight > 100, () => {
            assertEqual(_view.page.path + " " + _view.box.path + " " + _view.plain.path, "settings.fixture settings.fixture.box ",
                        "paths: the page takes the base, the box adds its name, a block with no anchor has none");
            assertEqual(_view.box.host, host, "a block's module host: the enclosing block's");
            assertEqual(_live("settings.fixture"), "settings.fixture:1,settings.fixture.box:1", "Anchors.live: the page and the box, once each; not the block with no anchor");
            assert(table.filter(row => row.path.startsWith("settings.fixture")).every(row => Anchors.live[row.path] > 0),
                   "every fixture table path the view builds is live");
            const hosts = [_view.page.prependHost, _view.page.appendHost, _view.box.beforeHost, _view.box.afterHost, _view.box.prependHost,
                           _view.box.appendHost, _view.plain.appendHost];
            assertEqual(hosts.map(each => each.count + (each.built ? "b" : "") + each.implicitHeight).join(","), "00,00,00,00,00,00,00",
                        "with no module: no host has a size or builds anything, not even its list");
            host.load([fixtures + "/places-b", fixtures + "/places-a"], {});
        });
        _then("the fixture modules settle", _settled, () => {
            const alpha = host.status("places-a");
            const beta = host.status("places-b");
            assertEqual(alpha?.state + " " + beta?.state, "loaded loaded", "both modules loaded");
            assert(_has(alpha?.errors, "anchors: \"settings.nowhere\" is not a place this shell offers (module API " + ModuleRules.apiVersion + ")"),
                   "a place this shell does not offer: an error in the module's status — " + alpha?.errors.join("; "));
            assert(_has(alpha?.errors, "anchors: \"settings.fixture\" does not take \"before\" (it takes: prepend, append)"),
                   "… a placement the place does not take, too");
            assertEqual(alpha?.errors.length + "," + alpha?.warnings.length, "2,0", "… nothing else, no warning: the rest of the module loads");
            assertEqual(alpha?.deprecations.join("|"),
                        "slots (\"settings.general.bottom\"): use `anchors`: \"settings.general\", \"append\" (goes with the shell's next tightening)",
                        "a slot whose place is offered is read as the anchor, listed among the deprecations");
            assertEqual(beta?.errors.length + "," + beta?.warnings.length + "," + beta?.deprecations.length, "0,0,0", "the other module: clean");
            assertEqual(host.slotContributions("settings.general.bottom").length, 0, "the slot read as an anchor is not a slot contribution any more");
            assertEqual(host.anchorContent("settings.nowhere", "append").length + host.anchorContent("settings.fixture", "before").length, 0,
                        "the host lists nothing for a place not offered or a placement not taken");
        });
        _then("every element is built and laid out", () => _inOrder(_view), () => {
            const sequence = _sequence(_view);
            console.log("  INFO: top to bottom: " + sequence.map(entry => entry[0] + " " + Math.round(entry[1])).join(" · "));
            assertEqual(_names(_view.page.appendHost), "places-a:Element,places-a:Second,places-b:Element",
                        "several modules at one place: by module id (loaded beta first), a module's together in its manifest's order");
            assertEqual(_names(_view.page.prependHost) + " " + _names(_view.box.beforeHost) + " " + _names(_view.box.afterHost),
                        "places-a:Element places-a:Element places-a:Element", "each placement its element");
            const appended = _view.page.appendHost.items[0].item;
            assertEqual(JSON.stringify(appended.context), JSON.stringify({ editIndex: 2, anchor: "settings.fixture", placement: "append" }),
                        "an element's context: the block's, with anchor and placement");
            assertEqual(JSON.stringify(_view.box.beforeHost.items[0].item.context), JSON.stringify({ boxed: true, anchor: "settings.fixture.box", placement: "before" }),
                        "… the box's own context at its places");
            assertEqual(appended.module, host.handle("places-a"), "each element gets its own module's handle");
            assertEqual(_view.page.appendHost.items[2].item.module, host.handle("places-b"), "… the other module's its own");
            assert(appended.shown, "… and `shown`: on screen");
            assertEqual(appended.text, "alpha settings.fixture append", "the element shows (plain text)");
            const model = _view.page.appendHost.repeaterModel;
            assert(model !== null && !Array.isArray(model) && model.objectProp === "key",
                   "the elements are made from a ScriptModel keyed by module and file, never a live array on Repeater.model");
            assertEqual(_view.plain.appendHost.count + "," + _view.plain.appendHost.built, "0,false", "a block with no anchor hosts nothing");
            _betaItem = _view.page.appendHost.items[2];
            _betaElement = _betaItem.item;
            _betaContexts = _betaElement.contextChanges;
            _alphaElement = appended;
            assert(host.setEnabled("places-a", false), "places-a turned off");
        });
        _then("places-a is off", () => host.status("places-a")?.state === "disabled" && _view.page.appendHost.items.length === 1, () => {
            assertEqual(_names(_view.page.appendHost), "places-b:Element", "its elements are gone; the other module's stays");
            assert(_view.page.appendHost.items[0] === _betaItem && _betaItem.item === _betaElement, "… the same object: not rebuilt");
            assertEqual(_betaElement.contextChanges, _betaContexts, "… its context not handed over again");
            const emptied = [_view.page.prependHost, _view.box.beforeHost, _view.box.afterHost, _view.box.prependHost, _view.box.appendHost];
            assertEqual(emptied.map(each => each.count + (each.built ? "b" : "") + each.implicitHeight).join(","), "00,00,00,00,00",
                        "the hosts it alone filled: empty, no size, their lists gone");
            assert(host.setEnabled("places-a", true), "places-a turned on");
        });
        _then("places-a is on again", () => host.status("places-a")?.state === "loaded" && _inOrder(_view), () => {
            assertEqual(_names(_view.page.appendHost), "places-a:Element,places-a:Second,places-b:Element", "its elements are back, in the one order");
            assert(_view.page.appendHost.items[2].item === _betaElement, "… the other module's element still the same object");
            _alphaElement = _view.page.appendHost.items[0].item;
            host.load([fixtures + "/places-a", fixtures + "/places-b"], {});
        });
        _then("reloaded", () => _settled() && host.status("places-a")?.state === "loaded" && _inOrder(_view)
                                && _view.page.appendHost.items[0].item !== _alphaElement, () => {
            assertEqual(_names(_view.page.appendHost), "places-a:Element,places-a:Second,places-b:Element", "a reload: the same elements, in the same order");
            assert(_view.page.appendHost.items[0].item !== _alphaElement, "… built anew");
            assert(_view.page.appendHost.items[0].item.module === host.handle("places-a"), "… with the module's handle");
            // A block renamed (or moved) has its new path at once
            _view.box.anchor = "renamed";
            assertEqual(_view.box.path, "settings.fixture.renamed", "a block renamed: its path follows");
            assertEqual(_live("settings.fixture"), "settings.fixture:1,settings.fixture.renamed:1", "… Anchors.live too");
            assertEqual(_view.box.beforeHost.count, 0, "… and a path not in the table takes nothing");
            _view.box.anchor = "box";
            _view.plain.parent = _view.box.frame.parent;
            _view.plain.anchor = "inner";
            assertEqual(_view.plain.path, "settings.fixture.box.inner", "a block moved into another: the enclosing block's path and its name");
            _view.plain.anchor = "";
            // A second view of the same page, and the General page with a slot read as its anchor
            _open("settings.fixture");
            _open("settings.general");
        });
        _then("the box has its elements back, the other views are up", () => _allBuilt(_view) && _allBuilt(_views[1])
                                                                            && _ready(_views[2].page.appendHost, 1), () => {
            assertEqual(_live("settings.fixture"), "settings.fixture:2,settings.fixture.box:2", "two views of one page: each path live twice");
            assertEqual(_live("settings.general"), "settings.general:1,settings.general.box:1",
                        "the General fixture: the page, and its box live but named, not published");
            const slotElement = _views[2].page.appendHost.items[0].item;
            assertEqual(slotElement?.objectName, "places-a:Element", "a slot read as its anchor: the module's slot file at the place");
            assertEqual(JSON.stringify(slotElement?.context), JSON.stringify({ editIndex: 2, slot: "settings.general.bottom", anchor: "settings.general", placement: "append" }),
                        "… its context carrying the slot's name, as the old name promised");
            assertEqual(_views[2].box.beforeHost.count, 0, "… a block whose path is not in the table takes nothing");
            _close(_views[2]);
            _close(_views[1]);
        });
        _then("two views closed", () => _live("settings.general") === "", () => {
            assertEqual(_live("settings.fixture"), "settings.fixture:1,settings.fixture.box:1", "a view closed: its blocks leave Anchors.live; the view still open stays");
            _close(_view);
            _view = null;
        });
        _then("the last view closed", () => _live("settings.fixture") === "", () => {
            _view = _open();
        });

        // Opened and closed over and over, each time built to the end, with a module turned
        // off and on between; then opened and closed in one go, before anything is built
        const cycle = number => {
            _then("the view built (cycle " + number + ")", () => _view !== null && _allBuilt(_view), () => {
                _cycles++;
                _close(_view);
                _view = null;
                if (_cycles === 5)
                    host.setEnabled("places-b", false);
                if (_cycles === 7)
                    host.setEnabled("places-b", true);
            });
            _then("… opened again", () => host.status("places-b")?.state === (number >= 5 && number < 7 ? "disabled" : "loaded"), () => {
                _view = _open();
            });
        };
        for (let i = 1; i <= 10; i++)
            cycle(i);
        _then("ten times opened and closed", () => _view !== null && _allBuilt(_view) && _live("settings.fixture") === "settings.fixture:1,settings.fixture.box:1", () => {
            assertEqual(_cycles, 10, "the view opened and closed ten times, built each time");
            assertEqual(_live("settings.fixture"), "settings.fixture:1,settings.fixture.box:1", "… one view live now (the closed ones gone)");
            _close(_view);
            _view = null;
            for (let i = 0; i < 10; i++)
                _close(_open());
            _waitUntil = Date.now() + 300;
        });
        _then("views closed before they were built leave nothing live", () => Date.now() >= _waitUntil && _live("settings.fixture") === "", () => {
            assertEqual(host.status("places-a")?.errors.length, 2, "no element failed meanwhile (the module's errors are its two anchors)");
        });
        _clock.start();
    }
}
