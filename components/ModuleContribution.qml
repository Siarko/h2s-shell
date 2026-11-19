import QtQuick
import qs.singletons

// One file of a module built inside a guard (notes/plans/modules.md, "Module API 1.0"): the
// file is compiled first, and one that does not compile shows nothing — its error goes to the
// module's status (ModuleHost.reportError), nothing else is touched. Built, its root object
// gets the module's handle as `module` and `context` (when it declares them) before its
// Component.onCompleted; `context` is passed again only when it changes by value
// (ModuleRules.sameContext), so a contribution is not poked by a re-read that changed nothing
// of it. `properties` ({ name: value }) are passed the same way (a settings page's editIndex;
// one the root object has without declaring it in its file is set right after it is made).
// `shown` (module API 1.2), when the root object declares `property bool shown`: true while
// the contribution is on screen — the place it sits in visible and its window open — kept
// current, so a page or a slot contribution does expensive work (polling, watching) only while
// it is seen. Gone, or blank, while the module is not active. A change of `url` and of the
// module's state together (another module's page picked) builds it once, not twice.
//
// `takes` ("" anything): what its root object must be, by the mark a public element carries
// (`apiElement`: "SmallButton" on a card's `actions`). Another object is destroyed as soon as it
// is made, shows nothing, and its module's status says what the place takes.
//
// ModuleSlot and AnchorContent build each contribution with one; ModuleHost.slotComponent hands one out as a
// Component for a place that takes a Component per module; the settings window shows a
// module's page with one.
Item {
    id: root

    property var host: Modules.host
    property string moduleId: ""
    property string url: ""
    // The slot it is built for ("" for a page), for the error it reports
    property string slot: ""
    // Or the anchor's path and placement (AnchorContent)
    property string anchor: ""
    property string placement: ""
    // What the root object must be ("" anything; else its `apiElement` mark)
    property string takes: ""
    property var context: null
    property var properties: ({})
    // The element is given this wrapper's height as well as its width (a card's name line)
    property bool givenHeight: false

    // Built and showing
    readonly property bool ready: _loader.status === Loader.Ready && _loader.item !== null
        && (takes === "" || _loader.item.apiElement === takes)
    readonly property var item: _loader.item
    // Why it shows nothing ("" while fine)
    property string error: ""

    readonly property bool _active: host !== null && host.activeIds.includes(moduleId) && url !== ""

    // Whether the element itself is shown: an element with `visible: false` has no size, so a
    // layout skips it with its gap (a stacked button) and a Column too. Its own `visible` reads
    // its parents' as well and its explicit value cannot be read, so this wrapper's `visible`
    // cannot follow it (hidden, the element would read hidden for good); while the wrapper is
    // not shown, the element's is unknown and its size is kept
    readonly property bool elementShown: ready && (!_loader.visible || _loader.item.visible)

    visible: ready
    // An element with no implicit width (a `Rectangle { width: 16 }`) takes the width it had
    // when it was made, so it shows on a name line instead of standing at no width
    implicitWidth: elementShown ? (_loader.item.implicitWidth > 0 ? _loader.item.implicitWidth : _ownWidth) : 0
    implicitHeight: elementShown ? _loader.item.implicitHeight : 0

    // The element's own width, read as it is made, before it is given this wrapper's
    property real _ownWidth: 0
    property bool _measured: false

    property var _passedContext: null
    property var _passedProperties: ({})
    // On screen: where it sits is visible (its own `visible` follows `ready`, so the parent's
    // is read) and its window is open
    readonly property bool shown: (parent?.visible ?? false) && (Window.window?.visible ?? false)
    property bool _loadQueued: false
    property bool _completed: false

    on_ActiveChanged: _queueLoad()
    onUrlChanged: _queueLoad()
    Component.onCompleted: {
        _completed = true;
        _load();
    }
    onContextChanged: _passContext()
    onPropertiesChanged: _passProperties()
    onShownChanged: _passProperties()

    // url and the module's state often change in one go (the settings window picks another
    // module's page: moduleId and url): one build for both, at the end of the event
    function _queueLoad() {
        if (!_completed || _loadQueued)
            return;
        _loadQueued = true;
        Qt.callLater(_load);
    }

    // What the root object is given besides module and context
    function _allProperties() {
        return Object.assign({}, properties ?? {}, { shown: shown });
    }

    function _load() {
        _loadQueued = false;
        _measured = false;
        _ownWidth = 0;
        _loader.source = "";
        error = "";
        if (!_active)
            return;
        let component = null;
        try {
            component = Qt.createComponent(url, Component.PreferSynchronous);
        } catch (thrown) {
            _failed(String(thrown));
            return;
        }
        if (!component || component.status !== Component.Ready) {
            _failed(component ? component.errorString().trim() : "cannot be loaded");
            return;
        }
        _passedContext = context;
        _passedProperties = _allProperties();
        // The compiled file is cached: this does not compile it again
        // Given only what its root object declares (a Loader warns about the rest)
        const initial = host.initialProperties(url, Object.assign(_allProperties(), { module: host.handle(moduleId), context: context }));
        _loader.setSource(url, initial);
        // Made at once (the compiled file is cached, the Loader is synchronous): what it is
        // is read here, before it is shown — its own width too, before it is given one
        _ownWidth = _loader.item ? _loader.item.width : 0;
        _measured = true;
        _refuseWrongKind();
        _giveInherited(initial);
    }

    // `properties` the root object has without declaring them in its file (a public
    // button's `size`), which a Loader cannot be given: set right after it is made
    function _giveInherited(initial) {
        const target = _loader.item;
        if (!target)
            return;
        for (const key of Object.keys(properties ?? {})) {
            if (key in initial || !(key in target) || key === "module" || key === "context")
                continue;
            try {
                target[key] = properties[key];
            } catch (thrown) {
                // Not writable there: left alone
            }
        }
    }

    // Whether the object made is not what the place takes
    function _wrongKind() {
        return takes !== "" && _loader.item !== null && _loader.item.apiElement !== takes;
    }

    function _refuseWrongKind() {
        if (!_wrongKind())
            return;
        _loader.source = "";
        error = "takes a " + takes;
        host?.reportError(moduleId, "anchors: " + ModuleRules.show(anchor) + " takes a " + takes);
    }

    function _failed(text) {
        error = text;
        const where = anchor !== "" ? "anchors: " + anchor + ", " + placement + ": " : slot !== "" ? "slot " + slot + ": " : "";
        host?.reportError(moduleId, where + text);
    }

    function _passContext() {
        const target = _loader.item;
        if (!target || ModuleRules.sameContext(_passedContext, context))
            return;
        try {
            if ("context" in target)
                target.context = context;
        } catch (thrown) {
            // It takes no context
        }
        _passedContext = context;
    }

    function _passProperties() {
        const target = _loader.item;
        const wanted = _allProperties();
        if (!target || ModuleRules.sameContext(_passedProperties, wanted))
            return;
        for (const key of Object.keys(wanted)) {
            try {
                if (key in target && key !== "module" && key !== "context")
                    target[key] = wanted[key];
            } catch (thrown) {
                // Not writable there: left alone
            }
        }
        _passedProperties = wanted;
    }

    // Its width given to the element itself, not through the Loader's: a Loader of a set width
    // resizes its item as soon as it is made, and the element's own width is lost
    Loader {
        id: _loader
        onStatusChanged: {
            if (status === Loader.Error)
                root._failed(root.url + ": could not be created");
            else if (status === Loader.Ready && root._wrongKind())
                Qt.callLater(root._refuseWrongKind);
        }
    }
    Binding { target: _loader.item; property: "width"; value: root.width; when: root._measured && _loader.item !== null }
    Binding { target: _loader; property: "height"; value: root.height; when: root.givenHeight }
}
