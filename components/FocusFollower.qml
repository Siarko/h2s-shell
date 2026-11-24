import QtQuick
import qs.singletons

// Scrolls the item with the keyboard into view: every scrolled view (Flickable) it lies in
// moves just enough to show it whole (ApiElementRules.scrollToShow), so Tab never lands on
// a control out of sight. Put one anywhere in the window it watches.
Item {
    id: root

    // Kept above or below the item, so it does not sit on the view's edge
    property real margin: 8

    readonly property Item _focused: Window.activeFocusItem
    on_FocusedChanged: if (_focused) Qt.callLater(() => root.follow(root._focused))

    function follow(item) {
        if (!item || item !== Window.activeFocusItem)
            return;
        for (let view = item.parent; view; view = view.parent) {
            if (!(view instanceof Flickable) || !view.contentItem)
                continue;
            const place = item.mapToItem(view.contentItem, 0, 0);
            view.contentY = ApiElementRules.scrollToShow(place.y, place.y + item.height, view.contentY,
                view.height, view.contentHeight, margin);
        }
    }
}
