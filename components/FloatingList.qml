import QtQuick
import qs.singletons

// A list that floats over the content under `anchorItem` while `open`, rather than taking
// room in the layout: dropdowns, "+ Add" pickers, suggestions. It moves to the top of the
// window — or of the nearest ancestor named "overlayHost", e.g. a popup's panel, so it
// stays where clicks reach — opens upwards when there is no room below, and a press
// anywhere else closes it. Its items go inside it, as children; `closed` tells the owner.
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

    // Where it lives: the nearest overlay host above the anchor, else the window's top
    readonly property Item _host: {
        for (let item = anchorItem?.parent; item; item = item.parent) {
            if (item.objectName === "overlayHost")
                return item;
        }
        return anchorItem?.Window.window?.contentItem ?? null;
    }

    parent: _host
    z: 1000
    visible: open && _host !== null
    width: listWidth
    height: Math.min(_items.implicitHeight + 6, maximumHeight)
    radius: 6
    color: Theme.popupBackground
    border.width: 1
    border.color: Theme.outline
    clip: true

    // Placed when it opens (the anchor does not move while it is open): under the anchor,
    // or above it when the host has no room below
    function _place() {
        if (!anchorItem || !_host)
            return;
        const below = anchorItem.mapToItem(_host, 0, anchorItem.height + 2);
        const above = anchorItem.mapToItem(_host, 0, -height - 2);
        x = Math.max(0, Math.min(below.x, _host.width - width));
        y = below.y + height <= _host.height || above.y < 0 ? below.y : above.y;
    }
    onOpenChanged: if (open) Qt.callLater(_place)
    onHeightChanged: if (open) _place()

    Flickable {
        anchors { fill: parent; margins: 3 }
        contentHeight: _items.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

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
