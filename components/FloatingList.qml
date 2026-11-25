import QtQuick
import qs.singletons

// A list that floats over the content under `anchorItem` while `open`, rather than taking
// room in the layout: dropdowns, "+ Add" pickers, suggestions. It moves to the top of the
// window — or of the nearest ancestor named "overlayHost", e.g. a popup's panel, so it
// stays where clicks reach — and a press anywhere else closes it. Its items go inside it,
// as children; `closed` tells the owner.
//
// It stays attached to the anchor: while shown it follows the anchor's place in the host —
// a page scrolled under it, a layout settling, the host resized — and opens upwards when
// there is no room below (on neither side room for all of it: on the larger side, as tall
// as fits). The anchor scrolled out of view (out of a clipping ancestor, or of the host)
// closes it. Moved out from under the anchor, it no longer hides with it: it shows only
// while the anchor is shown, so a page hidden with its list open (or a plan's scene that
// holds one open) leaves neither the list nor its press catcher over the window. Taller
// than `maximumHeight`, it scrolls by itself; a wheel over it never reaches the page.
//
//   FloatingList { anchorItem: button; open: menuOpen; onClosed: menuOpen = false; … }
Rectangle {
    id: root

    required property Item anchorItem
    property bool open: false
    // Wide as the anchor by default
    property real listWidth: anchorItem ? anchorItem.width : 120
    property real maximumHeight: 240
    default property alias content: _items.data
    signal closed
    // What a side panel looks for to close an open list before itself (SideDrawer)
    readonly property bool floatingList: true

    // Where it lives: the nearest overlay host above the anchor, else the window's top
    readonly property Item _host: {
        for (let item = anchorItem?.parent; item; item = item.parent) {
            if (item.objectName === "overlayHost")
                return item;
        }
        return anchorItem?.Window.window?.contentItem ?? null;
    }

    // The anchor's own visibility counts its ancestors; the window check keeps a list whose
    // anchor moved to another window from covering this one
    readonly property bool _anchorShown: anchorItem !== null && anchorItem.visible && _host !== null
        && anchorItem.Window.window === _host.Window.window
    // The anchor inside the view of every clipping ancestor and of the host (_place)
    property bool _anchorInView: true
    // The room on the side it opens to, past which it scrolls (_place)
    property real _room: maximumHeight

    parent: _host
    z: 1000
    visible: open && _anchorShown && _anchorInView
    width: listWidth
    height: Math.max(0, Math.min(_items.implicitHeight + 6, maximumHeight, _room))
    radius: Theme.dropdown.radius
    color: Theme.popupBackground
    border.width: Theme.border.width
    border.color: Theme.outline
    clip: true

    // Under the anchor, or above it when there is room only there; with room on neither side
    // for all of it, on the larger side. And whether the anchor is in view at all.
    function _place() {
        if (!anchorItem || !_host)
            return;
        const top = anchorItem.mapToItem(_host, 0, 0);
        let inView = true;
        for (let item = anchorItem.parent; item && item !== _host; item = item.parent) {
            if (!item.clip)
                continue;
            const corner = anchorItem.mapToItem(item, 0, 0);
            if (corner.x + anchorItem.width <= 0 || corner.y + anchorItem.height <= 0
                || corner.x >= item.width || corner.y >= item.height)
                inView = false;
        }
        // (a host not laid out yet has no size: nothing is out of it)
        if (_host.width > 0 && _host.height > 0 && (top.x + anchorItem.width <= 0 || top.y + anchorItem.height <= 0
            || top.x >= _host.width || top.y >= _host.height))
            inView = false;
        // Scrolled out of view while shown: closed, as by a press outside
        const wasShown = visible;
        _anchorInView = inView;
        if (wasShown && !inView)
            closed();

        const wanted = _wanted;
        const roomBelow = _host.height - (top.y + anchorItem.height + 2);
        const roomAbove = top.y - 2;
        const below = wanted <= roomBelow || (wanted > roomAbove && roomBelow >= roomAbove);
        _room = Math.max(0, below ? roomBelow : roomAbove);
        x = Math.max(0, Math.min(top.x, _host.width - width));
        y = below ? top.y + anchorItem.height + 2 : top.y - height - 2;
    }

    // Following the anchor: every item from the anchor up to the host moves it when it moves
    // or changes size (a Flickable's content item is one of them, so a scroll is a move), and
    // a change of parent on the way makes the chain anew
    property var _watched: []
    function _watch() {
        _unwatch();
        if (!open || !anchorItem || !_host)
            return;
        const watched = [];
        for (let item = anchorItem; item; item = item.parent) {
            for (const name of ["xChanged", "yChanged", "widthChanged", "heightChanged"]) {
                item[name].connect(_place);
                watched.push({ item: item, name: name, handler: _place });
            }
            item.parentChanged.connect(_rewatch);
            watched.push({ item: item, name: "parentChanged", handler: _rewatch });
            if (item === _host)
                break;
        }
        _watched = watched;
    }
    function _unwatch() {
        for (const entry of _watched) {
            // An item of the old chain may be gone already
            try {
                entry.item[entry.name].disconnect(entry.handler);
            } catch (error) {}
        }
        _watched = [];
    }
    function _rewatch() {
        _watch();
        _place();
    }

    onOpenChanged: {
        _watch();
        if (open) {
            _place();
            // Once the layouts that are still pending have run
            Qt.callLater(_place);
        }
    }
    onAnchorItemChanged: _rewatch()
    on_HostChanged: _rewatch()
    // The anchor may have moved while it was hidden
    onVisibleChanged: if (visible) Qt.callLater(_place)
    // Its items changed: as tall as they want, it may fit on the other side now
    readonly property real _wanted: Math.min(_items.implicitHeight + 6, maximumHeight)
    on_WantedChanged: if (open) _place()
    Component.onCompleted: if (open) _rewatch()
    Component.onDestruction: _unwatch()

    Flickable {
        id: _flick
        anchors { fill: parent; margins: 3 }
        contentHeight: _items.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        // The wheel over the list is the list's, also at its ends and when it fits: the page
        // under it does not scroll away from under the pointer
        WheelScroll {
            target: null
            onWheel: event => _flick.contentY = Math.max(0, Math.min(_flick.contentHeight - _flick.height,
                _flick.contentY - step(event)))
        }

        Column {
            id: _items
            width: parent.width
        }
    }

    // A press anywhere else in the host closes the list (and is not passed on)
    MouseArea {
        parent: root._host
        z: 999
        anchors.fill: parent
        visible: root.visible
        onPressed: mouse => {
            const point = mapToItem(root, mouse.x, mouse.y);
            if (point.x >= 0 && point.y >= 0 && point.x < root.width && point.y < root.height) {
                mouse.accepted = false;
                return;
            }
            root.closed();
        }
    }
}
