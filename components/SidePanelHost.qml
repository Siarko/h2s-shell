import QtQuick
import qs.singletons

// Where a module page's public SidePanels (api/SidePanel.qml) show: a layer over the page
// frame (ModulePageFrame), outside its scrolling, with one SideDrawer. One panel is open at
// a time: another opening closes the first ("replaced"). It closes the open one when the
// session locks ("lock"), when its window hides or the frame goes ("page"), and when the
// user closes it (Close, a click beside it, Escape). The panel open is told why with its
// closer, handed over with it; a panel destroyed (its page or module gone) is let go with
// `release`, its content taken away at once, even while it slides out.
Item {
    id: root

    // The SidePanel open now, or null, and what closes it
    property Item current: null
    // What closes the open panel (its closer), in a JavaScript object the destruction's
    // closure holds: Qt may drop the host's properties before its destruction runs, and the
    // open panel must still be told then
    readonly property var _open: ({ closer: null })
    readonly property alias drawer: _drawer

    readonly property bool _locked: ApiElements.sessionLocked
    readonly property bool _windowShown: Window.window?.visible ?? false

    on_LockedChanged: if (_locked) close("locked")
    on_WindowShownChanged: if (!_windowShown) close("pageGone")
    Component.onCompleted: {
        const open = _open;
        Component.destruction.connect(() => {
            const closing = open.closer;
            open.closer = null;
            if (closing)
                closing(ApiElementRules.sidePanelEvent(true, "pageGone", false).reason);
        });
    }

    // `panel` asks to open, `closer(reason)` closing it: "" when it shows, else why not (it
    // then stays closed)
    function show(panel, closer) {
        const refusal = ApiElementRules.sidePanelRefusal(true, _locked);
        if (refusal !== "")
            return refusal;
        if (current === panel)
            return "";
        const before = _open.closer;
        _open.closer = closer;
        current = panel;
        if (before)
            before(ApiElementRules.sidePanelEvent(true, "otherOpened", false).reason);
        return "";
    }

    // The open panel closes on `event` (a key of ApiElementRules.sidePanelReasons)
    function close(event) {
        const outcome = ApiElementRules.sidePanelEvent(current !== null, event, false);
        if (!outcome.close)
            return;
        const closing = _open.closer;
        _open.closer = null;
        current = null;
        if (closing)
            closing(outcome.reason);
    }

    // The owner closed `panel` itself (its `open` set false): no reason to tell
    function hide(panel) {
        if (current !== panel)
            return;
        _open.closer = null;
        current = null;
    }

    // `panel` is being destroyed: closed now, nothing of its content kept — also when it is
    // closed already and its content is still sliding out
    function release(panel) {
        if (current !== panel && _shown !== panel)
            return;
        _drawer.dropContent();
        if (current === panel) {
            _open.closer = null;
            current = null;
        }
        _shown = null;
    }

    // The panel shown last, kept while it slides out (null once destroyed)
    property Item _shown: null
    onCurrentChanged: if (current) _shown = current

    SideDrawer {
        id: _drawer
        anchors.fill: parent
        open: root.current !== null
        title: root._shown?.title ?? ""
        content: root.current?.content ?? null
        panelWidth: ApiElementRules.sidePanelWidth(root._shown?.size, root.width, Theme.sidePanelWidths)
        onRequested: event => root.close(event)
    }
}
