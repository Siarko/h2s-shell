import QtQuick
import qs.singletons

// One file of a module built inside a guard (docs/plans/modules.md, "Module API 1.0"): the
// file is compiled first, and one that does not compile shows nothing — its error goes to the
// module's status (ModuleHost.reportError), nothing else is touched. Built, its root object
// gets the module's handle as `module` and `context` (when it declares them) before its
// Component.onCompleted; `context` is passed again only when it changes by value
// (ModuleRules.sameContext), so a contribution is not poked by a re-read that changed nothing
// of it. `properties` ({ name: value }) are passed the same way (a settings page's editIndex).
// `shown` (module API 1.2), when the root object declares `property bool shown`: true while
// the contribution is on screen — the place it sits in visible and its window open — kept
// current, so a page or a slot contribution does expensive work (polling, watching) only while
// it is seen. Gone, or blank, while the module is not active. A change of `url` and of the
// module's state together (another module's page picked) builds it once, not twice.
//
// ModuleSlot builds each contribution with one; ModuleHost.slotComponent hands one out as a
// Component for core places that take a Component per module (the VPN slots); the settings
// window shows a module's page with one.
Item {
    id: root

    property var host: Modules.host
    property string moduleId: ""
    property string url: ""
    // The slot it is built for ("" for a page), for the error it reports
    property string slot: ""
    property var context: null
    property var properties: ({})

    // Built and showing
    readonly property bool ready: _loader.status === Loader.Ready && _loader.item !== null
    readonly property var item: _loader.item
    // Why it shows nothing ("" while fine)
    property string error: ""

    readonly property bool _active: host !== null && host.activeIds.includes(moduleId) && url !== ""

    visible: ready
    implicitWidth: ready ? _loader.item.implicitWidth : 0
    implicitHeight: ready ? _loader.item.implicitHeight : 0

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
        _loader.setSource(url, host.initialProperties(url, Object.assign(_allProperties(), { module: host.handle(moduleId), context: context })));
    }

    function _failed(text) {
        error = text;
        host?.reportError(moduleId, (slot !== "" ? "slot " + slot + ": " : "") + text);
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

    Loader {
        id: _loader
        width: root.width
        onStatusChanged: {
            if (status === Loader.Error)
                root._failed(root.url + ": could not be created");
        }
    }
}
