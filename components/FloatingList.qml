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
// while the anchor and its window are shown, so a page hidden with its list open (or a
// plan's scene that holds one open) leaves neither the list nor its press catcher over the
// window — and the anchor hidden while open emits `closed`. Taller
// than `maximumHeight`, it scrolls by itself; a wheel over it never reaches the page.
//
//   FloatingList { anchorItem: button; open: menuOpen; onClosed: menuOpen = false; … }
//
// The keyboard, as a combobox's: the focus stays on the control that opened it, which hands
// its keys to `handleKey(event)` while the list is open (true: taken). Up and Down, Home
// and End, Page Up and Page Down move `currentItem` among the entries, Enter activates it,
// Escape emits `closed`, a letter moves to the next entry starting with it. An entry is an
// item inside the list with `floatingEntry: true`, its text for the letters in
// `floatingEntryText`, `floatingEntryEnabled: false` when it cannot be picked (passed by the
// keys), and `floatingActivate()`, what Enter does; it shows itself current when
// `currentItem` is it. Other items (a group's title, FloatingListHeader) are passed by.
// `highlight(entry)` makes an entry current and scrolls it into view (null: none).
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
    // The entry the keys are on (null: none yet)
    property Item currentItem: null

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
    // Whether the anchor has been shown: the hidden one at the start (no window yet) closes nothing
    property bool _anchorWasShown: false
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

    // The entries shown, in the order they stand
    function _entries() {
        const found = [];
        const walk = item => {
            for (const child of item.children) {
                if (!child.visible)
                    continue;
                if (child.floatingEntry === true)
                    found.push(child);
                else
                    walk(child);
            }
        };
        walk(_items);
        return found.map(entry => ({ entry: entry, y: entry.mapToItem(_items, 0, 0).y }))
            .sort((first, second) => first.y - second.y).map(item => item.entry);
    }
    function _enabled(entry) {
        return entry.floatingEntryEnabled !== false;
    }

    function highlight(entry) {
        currentItem = entry ?? null;
        if (!currentItem)
            return;
        const top = currentItem.mapToItem(_items, 0, 0).y;
        if (top < _flick.contentY)
            _flick.contentY = top;
        else if (top + currentItem.height > _flick.contentY + _flick.height)
            _flick.contentY = Math.min(_flick.contentHeight - _flick.height, top + currentItem.height - _flick.height);
    }

    // `steps` enabled entries on from the current one (negative: back), at most to the
    // first or last; with none current, Down starts at the first, Up at the last
    function _move(steps) {
        const entries = _entries().filter(_enabled);
        if (entries.length === 0)
            return;
        const at = entries.indexOf(currentItem);
        let next;
        if (at < 0)
            next = steps > 0 ? Math.min(steps - 1, entries.length - 1) : Math.max(entries.length + steps, 0);
        else
            next = Math.max(0, Math.min(entries.length - 1, at + steps));
        highlight(entries[next]);
    }
    // As many entries as one view of the list holds
    function _pageSteps() {
        const entries = _entries();
        if (entries.length === 0)
            return 1;
        const tallest = Math.max(...entries.map(entry => entry.height), 1);
        return Math.max(1, Math.floor(_flick.height / tallest));
    }
    // The next enabled entry after the current one whose text starts with `letter`, round
    function _typeAhead(letter) {
        const wanted = letter.toLocaleLowerCase();
        const entries = _entries().filter(_enabled);
        const at = entries.indexOf(currentItem);
        for (let offset = 1; offset <= entries.length; offset++) {
            const entry = entries[(at + offset + entries.length) % entries.length];
            if (String(entry.floatingEntryText ?? "").toLocaleLowerCase().startsWith(wanted)) {
                highlight(entry);
                return;
            }
        }
    }

    function handleKey(event) {
        if (!visible)
            return false;
        const plain = (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) === 0;
        switch (event.key) {
        case Qt.Key_Down: _move(1); return true;
        case Qt.Key_Up: _move(-1); return true;
        case Qt.Key_Home: _move(-_entries().length); return true;
        case Qt.Key_End: _move(_entries().length); return true;
        case Qt.Key_PageDown: _move(_pageSteps()); return true;
        case Qt.Key_PageUp: _move(-_pageSteps()); return true;
        case Qt.Key_Escape: closed(); return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (currentItem && currentItem.visible && _enabled(currentItem) && typeof currentItem.floatingActivate === "function")
                currentItem.floatingActivate();
            else
                closed();
            return true;
        }
        if (plain && event.text.length === 1 && event.text.trim() !== "") {
            _typeAhead(event.text);
            return true;
        }
        return false;
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
        currentItem = null;
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
    // The anchor hidden while open (its page, its window): closed, so the owner's state says
    // so and the list does not come back open with the page. A list held open by a binding
    // stays open, and shows again with its anchor.
    on_AnchorShownChanged: {
        if (_anchorShown)
            _anchorWasShown = true;
        else if (open && _anchorWasShown)
            closed();
    }
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
