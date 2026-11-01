pragma Singleton

import Quickshell
import Quickshell.Services.Mpris
import QtQuick
import qs.singletons

// The media players (MPRIS) and the one the shell shows and controls — the active player:
// picked by hand, else one playing, else the first. The music panel lists the players
// (`visiblePlayers`; those the user hid, by name in "media.hiddenPlayers", apart in
// `hiddenPlayers`) — playerctld, a stand-in for another player, never among them. A hidden
// player is never made active by itself.
Singleton {
    id: root

    readonly property var players: Mpris.players
    property MprisPlayer activePlayer: null

    readonly property var hiddenNames: Profiles.value("media.hiddenPlayers") ?? []
    // Every real player, the proxy left out
    readonly property var listedPlayers: players.values.filter(player => !PlayerRules.isProxy(player.dbusName))
    readonly property var visiblePlayers: listedPlayers.filter(player => !_hidden(player))
    readonly property var hiddenPlayers: listedPlayers.filter(player => _hidden(player))

    function _hidden(player) {
        return PlayerRules.isHidden(player.identity, player.dbusName, hiddenNames);
    }

    function hidePlayer(player) {
        if (player === _manualPlayer)
            _manualPlayer = null;
        Profiles.writeInEffect("media.hiddenPlayers",
            PlayerRules.withHidden(hiddenNames, PlayerRules.key(player.identity, player.dbusName), true));
    }

    function showPlayer(player) {
        Profiles.writeInEffect("media.hiddenPlayers",
            PlayerRules.withHidden(hiddenNames, PlayerRules.key(player.identity, player.dbusName), false));
    }

    // Plays `player` alone: every other listed player that is playing is paused (hidden
    // ones too are left as they are — a phone's player the user keeps out of the way), and
    // it becomes the active one
    function playOnly(player) {
        for (const other of visiblePlayers) {
            if (other !== player && other.playbackState === MprisPlaybackState.Playing && other.canPause)
                other.pause();
        }
        if (player.canPlay)
            player.play();
        selectPlayer(player);
    }

    // The play button beside a player: pauses it while it plays, else plays it alone
    function togglePlayer(player) {
        if (player.playbackState === MprisPlaybackState.Playing)
            player.pause();
        else
            playOnly(player);
    }

    // The application's icon for a player ("" when there is none): from the desktop entry
    // it names, or the one its name or bus name points to (PlayerRules.desktopEntryFor)
    readonly property var _apps: DesktopEntries.applications.values.map(entry => ({ id: entry.id, name: entry.name }))
    function playerIcon(player) {
        const id = PlayerRules.desktopEntryFor(player?.desktopEntry, player?.identity, player?.dbusName, _apps);
        const icon = id !== "" ? DesktopEntries.byId(id)?.icon ?? "" : "";
        return icon !== "" ? Quickshell.iconPath(icon, true) : "";
    }

    // Manual override — set by selectPlayer(), cleared when that player disappears
    property MprisPlayer _manualPlayer: null

    function selectPlayer(player) {
        root._manualPlayer = player;
        root.activePlayer = player;
    }

    // Auto-select logic: prefer manual override, then a playing player, then first
    // available — among the visible players
    function _updateActivePlayer() {
        const candidates = visiblePlayers;
        // If manual override is still valid, keep it
        if (_manualPlayer !== null) {
            if (candidates.includes(_manualPlayer)) {
                activePlayer = _manualPlayer;
                return;
            }
            // Manual player disappeared, or was hidden
            _manualPlayer = null;
        }

        // Prefer a currently playing player
        const playing = candidates.find(player => player.playbackState === MprisPlaybackState.Playing);
        if (playing) {
            activePlayer = playing;
            return;
        }

        // Fall back to first available
        activePlayer = candidates.length > 0 ? candidates[0] : null;
    }

    // Re-evaluate when the players, or which are hidden, change
    onVisiblePlayersChanged: _updateActivePlayer()

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

    // The player's position, polled every second while playing: MPRIS does not signal
    // position changes, only seeks and track changes
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
