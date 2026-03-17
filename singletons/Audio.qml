pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Singleton {
    id: root
    property PwNode sink: Pipewire.defaultAudioSink
    property PwNode source: Pipewire.defaultAudioSource

    PwObjectTracker {
        objects: Pipewire.nodes.values
    }

    readonly property int volume: sink?.audio?.volume != null ? Math.round(sink.audio.volume * 100) : 0
    readonly property bool muted: sink?.audio?.muted ?? false

    readonly property int sourceVolume: source?.audio?.volume != null ? Math.round(source.audio.volume * 100) : 0
    readonly property bool sourceMuted: source?.audio?.muted ?? false

    readonly property var nodes: Pipewire.nodes
    property var appNodes: []
    property var appNodesByIndex: ({})

    function setDefaultSink(node) {
        Pipewire.preferredDefaultAudioSink = node;
    }
    function setDefaultSource(node) {
        Pipewire.preferredDefaultAudioSource = node;
    }

    function applySavedVolume(node) {
        if (!node.ready || !node.audio)
            return;
        var volumes = JSON.parse(Config.audio.appVolumes || "{}");
        var saved = volumes[node.name];
        if (saved !== undefined)
            node.audio.volume = saved;
    }

    Connections {
        target: Pipewire.nodes
        function onObjectInsertedPost(object, index) {
            if (object.type === 21) { //21 is releated to the app source for some reason
                root.appNodesByIndex[index] = object;
                root.appNodes = Object.values(root.appNodesByIndex);

                if (object.ready) {
                    root.applySavedVolume(object);
                } else {
                    object.readyChanged.connect(function() {
                        root.applySavedVolume(object);
                    });
                }
            }
        }
        function onObjectRemovedPre(object, index) {
            delete root.appNodesByIndex[index];
            root.appNodes = Object.values(root.appNodesByIndex);
        }
    }
}
