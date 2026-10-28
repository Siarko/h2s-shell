pragma Singleton

import Quickshell
import Quickshell.Services.Mpris
import QtQuick

Singleton {
    id: root

    readonly property var players: Mpris.players
    property MprisPlayer activePlayer: null

    // Manual override — set by selectPlayer(), cleared when that player disappears
    property MprisPlayer _manualPlayer: null

    function selectPlayer(player) {
        root._manualPlayer = player;
        root.activePlayer = player;
    }

    // Auto-select logic: prefer manual override, then a playing player, then first available
    function _updateActivePlayer() {
        // If manual override is still valid, keep it
        if (_manualPlayer !== null) {
            for (var i = 0; i < players.values.length; i++) {
                if (players.values[i] === _manualPlayer) {
                    activePlayer = _manualPlayer;
                    return;
                }
            }
            // Manual player disappeared
            _manualPlayer = null;
        }

        // Prefer a currently playing player
        for (var j = 0; j < players.values.length; j++) {
            if (players.values[j].playbackState === MprisPlaybackState.Playing) {
                activePlayer = players.values[j];
                return;
            }
        }

        // Fall back to first available
        activePlayer = players.values.length > 0 ? players.values[0] : null;
    }

    // Re-evaluate when the player list changes
    property var _playersList: players.values
    on_PlayersListChanged: _updateActivePlayer()

    // Watch for playback state changes on all players
    Instantiator {
        model: Mpris.players
        delegate: Connections {
            required property MprisPlayer modelData
            target: modelData
            function onPlaybackStateChanged() { root._updateActivePlayer(); }
        }
    }

    // Convenience properties
    readonly property bool hasPlayer: activePlayer !== null
    readonly property string title: activePlayer?.trackTitle ?? ""
    readonly property string artist: activePlayer?.trackArtist ?? ""
    readonly property string artUrl: activePlayer?.trackArtUrl ?? ""
    readonly property bool playing: activePlayer?.playbackState === MprisPlaybackState.Playing
    readonly property real length: activePlayer?.lengthSupported ? activePlayer.length : 0
    readonly property bool canNext: activePlayer?.canGoNext ?? false
    readonly property bool canPrev: activePlayer?.canGoPrevious ?? false
    readonly property bool canSeek: activePlayer?.canSeek ?? false
    readonly property bool canPlay: activePlayer?.canPlay ?? false
    readonly property bool canPause: activePlayer?.canPause ?? false

    // Interpolated position — MPRIS position doesn't update continuously
    property real position: activePlayer?.positionSupported ? activePlayer.position : 0

    Timer {
        interval: 1000
        running: root.playing
        repeat: true
        onTriggered: {
            if (root.activePlayer?.positionSupported) {
                root.position = root.activePlayer.position;
            }
        }
    }

    // Sync position when track changes or playback state changes
    onActivePlayerChanged: {
        if (activePlayer?.positionSupported)
            position = activePlayer.position;
        else
            position = 0;
    }

    // Control methods
    function togglePlay() {
        if (activePlayer) activePlayer.togglePlaying();
    }

    function play() {
        if (activePlayer && activePlayer.canPlay) activePlayer.play();
    }

    function pause() {
        if (activePlayer && activePlayer.canPause) activePlayer.pause();
    }

    function next() {
        if (activePlayer && activePlayer.canGoNext) activePlayer.next();
    }

    function previous() {
        if (activePlayer && activePlayer.canGoPrevious) activePlayer.previous();
    }

    function seek(offset) {
        if (activePlayer && activePlayer.canSeek) activePlayer.seek(offset);
    }

    function setPosition(pos) {
        if (activePlayer && activePlayer.canSeek) activePlayer.position = pos;
    }

    Component.onCompleted: _updateActivePlayer()
}
