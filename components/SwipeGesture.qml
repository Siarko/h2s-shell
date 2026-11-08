import QtQuick

// A finger swipe: a DragHandler that moves nothing itself (target null) and measures the
// drag, for the owner to move what it likes and to decide on release (`onActiveChanged`,
// `active` false) whether the swipe went far or fast enough.
//
// - `deltaX`/`deltaY` are measured in the scene, not in the parent's coordinates: what the
//   owner moves is often the parent, and the finger would then be measured against what it
//   moves.
// - `velocity()` is worked out from the last positions rather than taken from
//   centroid.velocity, which two events close together made huge: a slow short drag was
//   taken for a fling.
// - `meant(delta, speed, distance)`: the same rule everywhere for "far enough or fast
//   enough".
//
// Touch only by default: a mouse drag selects text and clicks, as it always has.
DragHandler {
    id: root

    target: null
    acceptedDevices: PointerDevice.TouchScreen

    readonly property real deltaX: centroid.scenePosition.x - centroid.scenePressPosition.x
    readonly property real deltaY: centroid.scenePosition.y - centroid.scenePressPosition.y

    // How far back the speed at release looks, in ms
    readonly property int _speedWindow: 120
    property var _recent: []

    onActiveChanged: if (active) _recent = []
    onDeltaXChanged: _sample()
    onDeltaYChanged: _sample()

    function _sample() {
        if (!active)
            return;
        const now = Date.now();
        _recent = _recent.filter(sample => now - sample.t <= 250).concat([{ t: now, x: deltaX, y: deltaY }]);
    }

    // { x, y } in px/s over the last stretch of the drag; 0 with too little to tell
    function velocity(): var {
        const now = Date.now();
        const old = _recent.find(sample => now - sample.t <= _speedWindow) ?? _recent[_recent.length - 1];
        if (!old || now - old.t < 16)
            return { x: 0, y: 0 };
        const seconds = (now - old.t) / 1000;
        return { x: (deltaX - old.x) / seconds, y: (deltaY - old.y) / seconds };
    }

    // Whether a swipe of `delta` px ending at `speed` px/s is meant: past `distance`, or
    // a fling — fast, the way it went (not a finger turning back), and not just a twitch
    function meant(delta: real, speed: real, distance: real): bool {
        return Math.abs(delta) > distance || (speed * Math.sign(delta) > 800 && Math.abs(delta) > 30);
    }
}
