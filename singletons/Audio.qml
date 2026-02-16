pragma Singleton

import Quickshell
import Quickshell.Services.Pipewire

Singleton {
    property PwNode sink: Pipewire.defaultAudioSink
    property PwNode source: Pipewire.defaultAudioSource

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    readonly property int volume: sink?.audio?.volume != null
        ? Math.round(sink.audio.volume * 100) : 0
    readonly property bool muted: sink?.audio?.muted ?? false

    readonly property int sourceVolume: source?.audio?.volume != null
        ? Math.round(source.audio.volume * 100) : 0
    readonly property bool sourceMuted: source?.audio?.muted ?? false

    readonly property var nodes: Pipewire.nodes
    function setDefaultSink(node) { Pipewire.preferredDefaultAudioSink = node; }
    function setDefaultSource(node) { Pipewire.preferredDefaultAudioSource = node; }
}
