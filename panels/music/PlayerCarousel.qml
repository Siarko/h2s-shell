import QtQuick
import Quickshell.Services.Mpris
import qs.singletons

// The active player's view (PlayerView), sliding sideways when the active player changes —
// picked in the list, scrolled to, or a new one playing: a player further down the list
// comes in from the right, one further up from the left, the old one going out the other
// way. Two live views take turns, each keeping its player: the one coming in gets the new
// player, the one going out keeps the old until it is out of sight. A change mid-slide
// carries on from where the views are. While sliding as tall as the taller of the two (the
// view coming in has no height until it has been laid out, a frame later), then moving to
// the shown one's. No slide with reduced motion, or for the first player.
Item {
    id: root

    property string visualizerLayout: "horizontal"
    property string visualizerStyle: "waveform"
    property bool showVisualizer: false

    // Cut at its edges only while sliding, so the view going out leaves by them; at rest the
    // visualiser round the cover (a glow, a turned square's corners) may reach past them
    clip: _slide.running
    implicitHeight: _slide.running ? Math.max(_first.implicitHeight, _second.implicitHeight)
        : (_slots[_current]?.implicitHeight ?? 0)
    Behavior on implicitHeight {
        enabled: !Theme.reduceMotion
        NumberAnimation { duration: Theme.duration("move"); easing: Theme.curve("move") }
    }

    // Which view shows the active player (0 or 1); the other is the one going out
    property int _current: 0
    // 1: the new player came from the right, -1: from the left
    property int _direction: 1
    // Where the view coming in is, from its place (0) — the one going out is a width
    // beyond it, on the side it leaves by
    property real _shift: 0
    readonly property var _slots: [_first, _second]

    Component.onCompleted: _first.player = Music.activePlayer

    Connections {
        target: Music
        function onActivePlayerChanged() { root._show(Music.activePlayer) }
    }

    function _show(player) {
        const shown = _slots[_current];
        if (shown.player === player)
            return;
        if (Theme.reduceMotion || shown.player === null || player === null || !visible) {
            _slide.stop();
            _shift = 0;
            shown.player = player;
            _slots[1 - _current].player = null;
            return;
        }
        const players = Music.visiblePlayers;
        const from = players.indexOf(shown.player), to = players.indexOf(player);
        _direction = from < 0 || to < 0 || to > from ? 1 : -1;
        // The view coming in starts a width off the one going out — which, mid-slide, is
        // where the view that was coming in has got to
        const start = (_slide.running ? _shift : 0) + _direction * width;
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
        // Out of sight: the old view lets go of its player
        onFinished: root._slots[1 - root._current].player = null
    }

    component Slot: PlayerView {
        required property int slotIndex
        readonly property bool shownNow: slotIndex === root._current
        width: root.width
        visible: player !== null
        x: shownNow ? root._shift : root._shift - root._direction * root.width
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
}
