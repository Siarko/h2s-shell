pragma Singleton

import Quickshell
import Quickshell.Services.Mpris
import QtQuick
import qs.components
import qs.singletons

// Pauses music while dictation is active and resumes it afterwards: whatever comes out
// of the speakers is picked up by the microphone and transcribed along with speech.
//
// Instantiated from shell.qml, so this works regardless of whether the dictation widget
// is on the bar — dictation is just as often toggled by a Hyprland shortcut.
Singleton {
    id: root

    // Only the idle/active edge matters; listening ↔ speaking flips constantly.
    readonly property bool _dictating: Stt.dictation !== "idle"

    // The players this singleton paused, so only a pause it caused is ever undone. If
    // playback was already stopped when dictation began, dictation must not start it.
    // Every player that plays, not only the shown one: a player hidden from the music
    // panel's list is never the active one, but the microphone hears it all the same.
    property var _pausedPlayers: []

    Logger {
        id: logger
        prefix: "[STT/music]"
        enabled: Profiles.value("stt.debug") ?? false
    }

    on_DictatingChanged: {
        if (_dictating) {
            if (!(Profiles.value("stt.pauseMusicWhileDictating") ?? true))
                return;
            const playing = Music.listedPlayers.filter(player => player.playbackState === MprisPlaybackState.Playing && player.canPause);
            for (const player of playing) {
                logger.log("pausing", player.identity);
                player.pause();
            }
            _pausedPlayers = playing;
            return;
        }

        // Resumed even if the setting was switched off in the meantime — this undoes a
        // pause that was already applied, rather than acting on the setting.
        for (const player of _pausedPlayers) {
            if (_isPlayerAlive(player) && player.canPlay) {
                logger.log("resuming", player.identity);
                player.play();
            } else {
                logger.log("player gone, nothing to resume");
            }
        }
        _pausedPlayers = [];
    }

    // The stored player may have quit during dictation. Checked against the live list
    // the same way Music._updateActivePlayer validates its manual override, rather than
    // trusting the reference to have been cleared.
    function _isPlayerAlive(player) {
        const players = Music.players.values;
        for (var i = 0; i < players.length; i++) {
            if (players[i] === player)
                return true;
        }
        return false;
    }
}
