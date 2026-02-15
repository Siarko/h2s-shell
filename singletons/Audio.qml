pragma Singleton

import Quickshell
import Quickshell.Services.Pipewire

Singleton {
    property PwNode sink: Pipewire.defaultAudioSink

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    readonly property int volume: sink?.audio?.volume != null
        ? Math.round(sink.audio.volume * 100) : 0
    readonly property bool muted: sink?.audio?.muted ?? false
}
