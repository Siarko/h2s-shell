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

    // The application's icon for a player ("" when there is none): the desktop entry it
    // names, else Quickshell's own guess from its name, else ours (PlayerRules
    // .desktopEntryFor: by the application's name — Quickshell's finds no "Brave" — or bus
    // name). An icon given as a file path is that file; a name, the icon theme's.
    function playerIcon(player) {
        if (!player)
            return "";
        // Read in a binding, this brings the icon in once the applications have been read
        void DesktopEntries.applications.values.length;
        let entry = DesktopEntries.byId(player.desktopEntry ?? "") ?? DesktopEntries.heuristicLookup(player.identity ?? "");
        if (!entry) {
            const apps = DesktopEntries.applications.values.map(application => ({ id: application.id, name: application.name }));
            const id = PlayerRules.desktopEntryFor(player.desktopEntry, player.identity, player.dbusName, apps);
            entry = id !== "" ? DesktopEntries.byId(id) : null;
        }
        const icon = entry?.icon ?? "";
        if (icon.startsWith("/"))
            return "file://" + icon;
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
            function onPlaybackStateChanged() { root._playbackStateChanged(modelData); }
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

    // The way the last skip asked for went (1 next, -1 previous) and when (ms): the music
    // panel slides the new track in from that side. A track that changes on its own (the
    // last one ended) comes as a next one.
    property int lastSkipDirection: 1
    property double lastSkipAt: 0

    // A skip from paused stays paused, as MPRIS has it ("if playback is paused or
    // stopped, it remains paused or stopped") — but Spotify starts playing. So a player
    // skipped while not playing is paused again if it starts within a moment after.
    property MprisPlayer _keepPaused: null
    property double _keepPausedUntil: 0

    function _skip(direction) {
        lastSkipDirection = direction;
        lastSkipAt = Date.now();
        const player = activePlayer;
        if (player.playbackState !== MprisPlaybackState.Playing) {
            _keepPaused = player;
            _keepPausedUntil = Date.now() + 3000;
        } else {
            _keepPaused = null;
        }
        if (direction > 0)
            player.next();
        else
            player.previous();
    }

    function _playbackStateChanged(player) {
        if (player === _keepPaused && player.playbackState === MprisPlaybackState.Playing) {
            _keepPaused = null;
            if (Date.now() < _keepPausedUntil && player.canPause)
                player.pause();
        }
        _updateActivePlayer();
    }

    function next() {
        if (activePlayer && activePlayer.canGoNext)
            _skip(1);
    }

    function previous() {
        if (activePlayer && activePlayer.canGoPrevious)
            _skip(-1);
    }

    function seek(offset) {
        if (activePlayer && activePlayer.canSeek) activePlayer.seek(offset);
    }

    function setPosition(pos) {
        if (activePlayer && activePlayer.canSeek) activePlayer.position = pos;
    }

    Component.onCompleted: _updateActivePlayer()
}
