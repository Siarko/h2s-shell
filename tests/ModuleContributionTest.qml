import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.singletons

// components/ModuleContribution.qml with a stand-in host, in a window (a Row lays out its
// children in its polish pass): how wide an element is.
// In a column (a card's `before`, a popup's rows, a page) the element is as wide as the
// place, one anchored to its parent's sides too. Sized by its element (a card's name line, its
// buttons' row): one made with a width of its own and no implicit width keeps that width;
// any other follows its implicit width, down to none when it empties itself.
TestCase {
    id: suite
    suiteName: "ModuleContribution"
    asynchronous: true

    // The host's part a contribution uses: the module on, the element given nothing more
    property var _host: QtObject {
        readonly property var activeIds: ["fake"]
        function initialProperties(url, properties) {
            return {};
        }
        function handle(moduleId) {
            return null;
        }
        function reportError(moduleId, text) {
            console.warn("ModuleContributionTest: " + moduleId + ": " + text);
        }
    }

    property var _window: PanelWindow {
        anchors { top: true; left: true }
        implicitWidth: 300
        implicitHeight: 100
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "h2s-tests"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    }

    property var _driver: WindowDriver {
        name: "ModuleContributionDriver"
    }

    function _until(condition, limitMs = 3000) {
        for (let waited = 0; waited < limitMs && !condition(); waited += 10)
            _driver.wait(10);
        return condition();
    }

    // A host that gives an element its context, as ModuleHost.initialProperties does for an
    // element that declares one
    property var _contextHost: QtObject {
        readonly property var activeIds: ["fake"]
        function initialProperties(url, properties) {
            return { context: properties.context };
        }
        function handle(moduleId) {
            return null;
        }
        function reportError(moduleId, text) {
            console.warn("ModuleContributionTest: " + moduleId + ": " + text);
        }
    }

    // The context the bound contributions take from the start
    property var _given: null
    property Component _boundContribution: Component {
        ModuleContribution {
            host: suite._contextHost
            moduleId: "fake"
            url: Qt.resolvedUrl("fixtures/elements/ContextElement.qml")
            context: Object.assign({}, suite._given ?? {}, { placement: "append" })
        }
    }

    property Component _contribution: Component {
        ModuleContribution {}
    }

    function _make(file, properties) {
        return _contribution.createObject(_window.contentItem, Object.assign({ host: _host, moduleId: "fake",
                                                                   url: Qt.resolvedUrl("fixtures/elements/" + file) }, properties));
    }

    function runAsync() {
        assert(_until(() => _window.visible), "the window is shown");
        // A column: an element anchored to its parent's sides is as wide as the place
        const filling = _make("Filling.qml", { width: 200 });
        assert(filling.ready, "column: the element built");
        assertEqual(filling.item.width + " " + filling.implicitHeight, "200 20", "column: an element anchored left and right is as wide as the place");
        filling.width = 150;
        assertEqual(filling.item.width, 150, "column: … and follows it");
        filling.destroy();

        // Sized by its element: a width of its own and no implicit width is kept
        const fixed = _make("FixedWidth.qml", { sizedByElement: true });
        assertEqual(fixed.implicitWidth, 16, "sized by its element: a width of its own and no implicit width kept (16)");
        fixed.width = fixed.implicitWidth;
        assertEqual(fixed.item.width, 16, "… the element given it");
        fixed.destroy();

        // Sized by its element: a row whose child hides takes no width, not the width it had
        const row = _make("HidingRow.qml", { sizedByElement: true });
        assert(_until(() => row.implicitWidth === 10), "sized by its element: a row as wide as its child (" + row.implicitWidth + ")");
        row.width = Qt.binding(() => row.implicitWidth);
        row.item.childShown = false;
        assert(_until(() => row.implicitWidth === 0), "… its child hidden: no width (" + row.implicitWidth + ")");
        row.item.childShown = true;
        assert(_until(() => row.implicitWidth === 10), "… shown again: its width back (" + row.implicitWidth + ")");
        row.destroy();

        // Sized by its element: a text emptied takes no width
        const text = _make("EmptiedText.qml", { sizedByElement: true });
        assert(text.implicitWidth > 0, "sized by its element: a text as wide as its words (" + text.implicitWidth + ")");
        text.width = Qt.binding(() => text.implicitWidth);
        text.item.text = "";
        assertEqual(text.implicitWidth, 0, "… emptied: no width");
        text.destroy();

        // Two elements at one place, given one context from the start, as AnchorContent binds
        // it (it reaches the element through Loader.setSource's initial properties): each its
        // own, frozen, its lists and plain objects a new copy at each read — a change to one
        // element's reaches neither the other nor the view's
        suite._given = { anchor: "settings.x", otherVpnsUp: ["Work"], count: 1, vpn: { name: "Work", active: true, routes: ["10.0.0.0/8"] } };
        const first = _boundContribution.createObject(_window.contentItem, {});
        const second = _boundContribution.createObject(_window.contentItem, {});
        const given = suite._given;
        assert(_until(() => first.ready && second.ready), "context: both elements built");
        assertEqual(first.item.atStart + " " + second.item.atStart, "true,true,true,true true,true,true,true",
                    "… given from the start through the initial properties: frozen, its list an Array, its list and its plain object getters");
        assert(first.item.othersUp === 1 && second.item.othersUp === 1, "context: given to each element");
        assert(first.item.context !== second.item.context && first.item.context !== given && Object.isFrozen(first.item.context),
               "… each its own frozen object, never the one given");
        for (const change of [list => list.push("Evil"), list => { list[0] = "Evil"; }, list => list.sort(() => -1)]) {
            try {
                change(first.item.context.otherVpnsUp);
            } catch (error) {}
            try {
                change(first.item.context.vpn.routes);
            } catch (error) {}
        }
        try {
            first.item.context.vpn.active = false;
        } catch (error) {}
        assertEqual(JSON.stringify(first.item.context.otherVpnsUp) + " " + JSON.stringify(second.item.context.otherVpnsUp) + " " + JSON.stringify(given.otherVpnsUp),
                    "[\"Work\"] [\"Work\"] [\"Work\"]", "… push, an index write, sort on one element's list: not at its next read, nor the other's, nor the view's");
        const vpnText = JSON.stringify({ name: "Work", active: true, routes: ["10.0.0.0/8"] });
        assertEqual(JSON.stringify(first.item.context.vpn) + " " + JSON.stringify(second.item.context.vpn) + " " + JSON.stringify(given.vpn),
                    vpnText + " " + vpnText + " " + vpnText, "… the VPN's row: a write into it or its routes not at its next read, nor the other's, nor the view's");
        try {
            first.item.context.count = 5;
        } catch (error) {}
        assertEqual(second.item.context.count + " " + first.item.context.count, "1 1", "… a write to a key does not stay");
        // Passed again when it changes by value: a binding on the element's list follows
        first.context = { anchor: "settings.x", otherVpnsUp: ["Work", "Home"], count: 1, vpn: given.vpn };
        assert(_until(() => first.item.othersUp === 2), "… a new context: the element's binding follows (" + first.item.othersUp + ")");
        assert(Object.isFrozen(first.item.context) && second.item.othersUp === 1, "… frozen again, the other element unchanged");
        assert(Array.isArray(second.item.context.otherVpnsUp) && Array.isArray(first.item.context.otherVpnsUp),
               "… its list an Array when passed later too");
        first.destroy();
        second.destroy();
        finish();
    }
}
