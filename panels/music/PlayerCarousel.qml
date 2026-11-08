import QtQuick
import Quickshell.Services.Mpris
import qs.components
import qs.singletons

// The active player's view (PlayerView), moving along two axes:
//
// - **Players, vertically.** When the active player changes — picked in the list,
//   scrolled to, a new one playing, swiped to — a player further down the list comes in
//   from below, one further up from above, the old one going out the other way. Two live
//   views take turns, each keeping its player: the one coming in gets the new player, the
//   one going out keeps the old until it is out of sight. A change mid-slide carries on
//   from where the views are.
// - **Tracks, sideways.** A new track of the shown player slides in from the right (next,
//   or the last one ended) or from the left (previous — Music remembers which way the
//   last skip went). The track going out is a snapshot: the player's view already shows
//   the new one by the time anyone is told. Two snapshots take turns — one kept live (out
//   of sight) so it always holds what the view last showed, frozen the moment the track
//   changes.
//
// A finger swipe across the view does the same: up or down for the next or previous
// player, whose real view follows the finger; left or right for the next or previous
// track, which no player tells beforehand — the gap shows ⏭/⏮ instead, lit once the
// swipe is far enough. Let go, the player is asked and the view waits where it was left
// (a moment at most; a player that does nothing, as most do with "previous" well into a
// track, sends it back) for the new track to slide in from there.
//
// While moving as tall as the taller of the two views (the view coming in has no height
// until it has been laid out, a frame later), then moving to the shown one's. No slides
// with reduced motion, or for the first player.
Item {
    id: root

    property string visualizerLayout: "horizontal"
    property string visualizerStyle: "waveform"
    property bool showVisualizer: false

    // Cut at its edges only while moving, so a view going out leaves by them; at rest the
    // visualiser round the cover (a glow, a turned square's corners) may reach past them
    readonly property bool _moving: _slide.running || _trackSlide.running || _swipe.active
        || _previewDirection !== 0 || _awaitingTrack
    clip: _moving
    readonly property real _shownHeight: _slide.running ? Math.max(_first.implicitHeight, _second.implicitHeight)
        : (_slots[_current]?.implicitHeight ?? 0)
    implicitHeight: _shownHeight
    // Not the first height: the view is laid out a frame after it is made, and growing from
    // nothing then made the popup open short and grow after
    property bool _laidOut: false
    on_ShownHeightChanged: if (!_laidOut && _shownHeight > 0) Qt.callLater(() => root._laidOut = true)
    Behavior on implicitHeight {
        enabled: root._laidOut && !Theme.reduceMotion
        NumberAnimation { duration: Theme.duration("move"); easing: Theme.curve("move") }
    }

    // ---- Players, vertically ----

    // Which view shows the active player (0 or 1); the other is the one going out, or the
    // one a swipe is bringing in
    property int _current: 0
    // 1: the new player came from below, -1: from above
    property int _direction: 1
    // Where the shown view is, up or down from its place (0) — the one going out is a
    // view's height beyond it, on the side it leaves by
    property real _shift: 0
    readonly property real _distance: Math.max(_first.implicitHeight, _second.implicitHeight) + 8
    // While a swipe brings the next player in from below (1) or the one before from above
    // (-1), in the other view; 0: none
    property int _previewDirection: 0
    readonly property var _slots: [_first, _second]

    Component.onCompleted: _first.player = Music.activePlayer

    Connections {
        target: Music
        function onActivePlayerChanged() { root._show(Music.activePlayer) }
    }

    // The player next to the shown one in the list, below (1) or above (-1); null at an end
    function _neighbour(direction) {
        const players = Music.visiblePlayers;
        const index = players.indexOf(_slots[_current].player);
        return index < 0 ? null : (players[index + direction] ?? null);
    }

    function _show(player) {
        const shown = _slots[_current];
        if (shown.player === player)
            return;
        _endTrackMotion();
        const other = _slots[1 - _current];
        if (_previewDirection !== 0 && player !== null && other.player === player) {
            // A swipe let go: the view it brought in becomes the shown one, from where it is
            _direction = _previewDirection;
            _previewDirection = 0;
            _slide.stop();
            _current = 1 - _current;
            _shift += _direction * _distance;
            _slide.start();
            return;
        }
        _previewDirection = 0;
        if (Theme.reduceMotion || shown.player === null || player === null || !visible) {
            _slide.stop();
            _shift = 0;
            shown.player = player;
            other.player = null;
            return;
        }
        const players = Music.visiblePlayers;
        const from = players.indexOf(shown.player), to = players.indexOf(player);
        _direction = from < 0 || to < 0 || to > from ? 1 : -1;
        // The view coming in starts a view's height off the one going out — which, mid-slide
        // or left by a finger, is where that one is now
        const start = _shift + _direction * _distance;
        _slide.stop();
        _current = 1 - _current;
        _slots[_current].player = player;
        _shift = start;
        _slide.start();
    }

    NumberAnimation {
        id: _slide
        target: root
        property: "_shift"
        to: 0
        duration: Theme.duration("move")
        easing: Theme.curve("move")
        // Out of sight: the other view lets go of its player — the one gone out, or the one
        // a swipe brought in only partway
        onFinished: {
            root._previewDirection = 0;
            root._slots[1 - root._current].player = null;
        }
    }

    // A vertical swipe at `offset`: the player that way follows the shown view in; at an
    // end of the list the view only gives a little
    function _dragPlayer(offset) {
        const direction = offset < 0 ? 1 : -1;
        const neighbour = offset === 0 ? null : _neighbour(direction);
        const other = _slots[1 - _current];
        if (neighbour) {
            _previewDirection = direction;
            other.player = neighbour;
            _shift = offset;
        } else {
            _previewDirection = 0;
            other.player = null;
            _shift = offset * 0.25;
        }
    }

    function _releasePlayer(delta, speed) {
        const other = _slots[1 - _current];
        if (_previewDirection !== 0 && delta * _previewDirection < 0
                && _swipe.meant(delta, speed, _distance / 4)) {
            Music.selectPlayer(other.player);
        } else {
            _slide.start();
        }
    }

    // ---- Tracks, sideways ----

    // Where the shown view is, left or right from its place (0); the track going out is a
    // width beyond it, on the side it leaves by
    property real _trackShift: 0
    // 1: the new track came from the right, -1: from the left
    property int _trackDirection: 1
    // A swipe let go far enough: the player was asked, and the view waits where it is
    property bool _awaitingTrack: false
    property int _awaitDirection: 1
    // Which snapshot is live (0 or 1); the other holds the track going out
    property int _liveSnapshot: 0
    readonly property var _snapshots: [_snapshotA, _snapshotB]

    Connections {
        target: root._slots[root._current].player
        function onTrackChanged() { root._trackChanged() }
    }

    function _trackChanged() {
        // Under a finger it just changes in place
        if (_swipe.active)
            return;
        if (Theme.reduceMotion || !visible || !_laidOut) {
            _endTrackMotion();
            return;
        }
        const direction = _awaitingTrack ? _awaitDirection
            : (Date.now() - Music.lastSkipAt < 3000 ? Music.lastSkipDirection : 1);
        _awaitingTrack = false;
        _awaitTimeout.stop();
        _trackDirection = direction;
        // The live snapshot freezes on the track going out
        _liveSnapshot = 1 - _liveSnapshot;
        const start = _trackShift + direction * width;
        _trackSlide.stop();
        _trackShift = start;
        _trackSlide.start();
    }

    function _endTrackMotion() {
        _trackSlide.stop();
        _awaitingTrack = false;
        _awaitTimeout.stop();
        _trackShift = 0;
    }

    NumberAnimation {
        id: _trackSlide
        target: root
        property: "_trackShift"
        to: 0
        duration: Theme.duration("move")
        easing: Theme.curve("move")
    }

    // A player that did not change the track: the view goes back
    Timer {
        id: _awaitTimeout
        interval: 1200
        onTriggered: {
            root._awaitingTrack = false;
            _trackSlide.start();
        }
    }

    // How far a sideways swipe has to go to skip
    readonly property real _skipDistance: width / 4
    readonly property int _dragSide: _trackShift < 0 ? 1 : -1
    readonly property bool _canSkipThatWay: _dragSide > 0 ? Music.canNext : Music.canPrev

    function _dragTrack(offset) {
        const direction = offset < 0 ? 1 : -1;
        const can = direction > 0 ? Music.canNext : Music.canPrev;
        _trackShift = can ? offset : offset * 0.25;
    }

    function _releaseTrack(delta, speed) {
        const direction = delta < 0 ? 1 : -1;
        const can = direction > 0 ? Music.canNext : Music.canPrev;
        if (can && _swipe.meant(delta, speed, _skipDistance)) {
            _awaitingTrack = true;
            _awaitDirection = direction;
            _awaitTimeout.restart();
            if (direction > 0)
                Music.next();
            else
                Music.previous();
        } else {
            _trackSlide.start();
        }
    }

    // The two snapshots of the shown view, out of sight in a clipped corner, where they are
    // still rendered (the live one stays current) but not seen. Size and view are followed
    // only while live, so the frozen one keeps the track going out as it was.
    component Snapshot: ShaderEffectSource {
        required property int snapshotIndex
        x: 1
        live: snapshotIndex === root._liveSnapshot && !Theme.reduceMotion
        Binding on sourceItem {
            when: live
            value: root._slots[root._current]
            restoreMode: Binding.RestoreNone
        }
        Binding on width {
            when: live
            value: root.width
            restoreMode: Binding.RestoreNone
        }
        Binding on height {
            when: live
            value: root._slots[root._current]?.implicitHeight ?? 0
            restoreMode: Binding.RestoreNone
        }
    }

    Item {
        width: 1
        height: 1
        clip: true

        Snapshot {
            id: _snapshotA
            snapshotIndex: 0
        }
        Snapshot {
            id: _snapshotB
            snapshotIndex: 1
        }
    }

    // The track going out
    ShaderEffect {
        readonly property Item _frozen: root._snapshots[1 - root._liveSnapshot]
        property variant source: _frozen
        visible: _trackSlide.running
        x: root._trackShift - root._trackDirection * root.width
        y: root._shift
        width: _frozen.width
        height: _frozen.height
    }

    // ---- The views ----

    component Slot: PlayerView {
        required property int slotIndex
        readonly property bool shownNow: slotIndex === root._current
        width: root.width
        visible: player !== null
        x: shownNow ? root._trackShift : 0
        y: shownNow ? root._shift
            : root._shift + (root._previewDirection !== 0 ? root._previewDirection : -root._direction) * root._distance
        visualizerLayout: root.visualizerLayout
        visualizerStyle: root.visualizerStyle
        showVisualizer: root.showVisualizer
    }

    Slot {
        id: _first
        slotIndex: 0
    }

    Slot {
        id: _second
        slotIndex: 1
    }

    // No player at all: what the view says then
    PlayerView {
        width: root.width
        visible: Music.activePlayer === null
    }

    // In the gap a sideways swipe opens: where it is going, lit once it is far enough
    Text {
        readonly property bool _far: Math.abs(root._trackShift) > root._skipDistance
        visible: root._canSkipThatWay && Math.abs(root._trackShift) > 1
            && ((_swipe.active && _swipe.axis === "x") || root._awaitingTrack)
        text: root._dragSide > 0 ? "󰒭" : "󰒮"
        x: (root._dragSide > 0 ? root.width : 0) + root._trackShift / 2 - width / 2
        y: root._shift + ((root._slots[root._current]?.implicitHeight ?? 0) - height) / 2
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeXXLargeDisplay
        color: _far || root._awaitingTrack ? Theme.textPrimary : Theme.textDisabled
        opacity: root._awaitingTrack ? 1 : Math.min(1, Math.abs(root._trackShift) / root._skipDistance)
        Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }
    }

    // ---- The swipe ----

    Item {
        anchors.fill: parent
        z: 10

        SwipeGesture {
            id: _swipe
            enabled: Music.hasPlayer
            // Decided as the swipe begins, kept to its end: "x" tracks, "y" players
            property string axis: ""
            property real _base: 0
            onActiveChanged: {
                if (active) {
                    axis = Math.abs(deltaX) >= Math.abs(deltaY) ? "x" : "y";
                    if (axis === "x") {
                        root._awaitingTrack = false;
                        _awaitTimeout.stop();
                        _trackSlide.stop();
                        _base = root._trackShift;
                    } else {
                        root._endTrackMotion();
                        _slide.stop();
                        _base = root._shift;
                    }
                    return;
                }
                const velocity = _swipe.velocity();
                if (axis === "x")
                    root._releaseTrack(deltaX, velocity.x);
                else
                    root._releasePlayer(deltaY, velocity.y);
            }
            onDeltaXChanged: if (active && axis === "x") root._dragTrack(_base + deltaX)
            onDeltaYChanged: if (active && axis === "y") root._dragPlayer(_base + deltaY)
        }
    }
}
