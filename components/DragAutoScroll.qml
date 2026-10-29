import QtQuick

// Scrolls the Flickable around `item` while a drag inside it is held near the
// Flickable's top or bottom edge — faster the closer to the edge — so a row can be
// dragged to a place that is scrolled out of view. The pointer does not move while the
// content does, so `scrolled()` tells the owner to recompute what is under the pointer.
//
//   onPressed:         autoScroll.begin()
//   onPositionChanged: autoScroll.update(mapToItem(null, 0, mouseY).y)
//   onReleased:        autoScroll.end()
Timer {
    id: root

    // An item inside the Flickable to scroll; the nearest Flickable ancestor is used
    required property Item item
    // Distance from the edge where scrolling starts, and the speed at the very edge
    property int edge: 48
    property real maxStep: 16

    // The pointer, in window coordinates
    property real sceneY: 0

    signal scrolled

    property var _flickable: null

    interval: 16
    repeat: true

    function begin() {
        _flickable = null;
        for (let parent = item?.parent; parent; parent = parent.parent) {
            if (parent.contentY !== undefined && parent.flick !== undefined) {
                _flickable = parent;
                break;
            }
        }
    }

    function update(pointerSceneY) {
        sceneY = pointerSceneY;
        running = _step() !== 0;
    }

    function end() {
        running = false;
        _flickable = null;
    }

    // Pixels to scroll this tick: positive down, negative up, 0 away from the edges
    function _step() {
        if (!_flickable)
            return 0;
        const top = _flickable.mapToItem(null, 0, 0).y;
        const bottom = top + _flickable.height;
        if (sceneY > bottom - edge)
            return maxStep * Math.min(1, (sceneY - (bottom - edge)) / edge);
        if (sceneY < top + edge)
            return -maxStep * Math.min(1, ((top + edge) - sceneY) / edge);
        return 0;
    }

    onTriggered: {
        const step = _step();
        const maxContentY = Math.max(0, _flickable.contentHeight - _flickable.height);
        const next = Math.max(0, Math.min(maxContentY, _flickable.contentY + step));
        if (step === 0 || next === _flickable.contentY) {
            running = false;
            return;
        }
        _flickable.contentY = next;
        scrolled();
    }
}
