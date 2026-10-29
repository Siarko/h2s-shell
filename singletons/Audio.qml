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
    // Applications' playback streams, for the per-app volume sliders
    property var appNodes: []
    // Volume the user last set per app, by node name: re-applied when the app (or
    // Pipewire) resets it. Written by the sliders in AudioChannelRow.
    property var targetVolumes: ({})
    // One watcher per app stream, created when it appears and destroyed when it goes
    property var _watchers: []

    function setDefaultSink(node) {
        Pipewire.preferredDefaultAudioSink = node;
    }
    function setDefaultSource(node) {
        Pipewire.preferredDefaultAudioSource = node;
    }

    // Watches one app stream: applies its saved volume once the node is ready, then keeps
    // the volume the user chose if something else changes it
    Component {
        id: watcherComponent

        QtObject {
            id: watcher
            required property PwNode node
            property bool applied: false

            function tryApply() {
                if (applied || !node.ready || !node.audio)
                    return;
                applied = true;
                var saved = JSON.parse(Config.audio.appVolumes || "{}")[node.name];
                if (saved !== undefined) {
                    root.targetVolumes[node.name] = saved;
                    node.audio.volume = saved;
                }
            }

            property Connections readyWatch: Connections {
                target: watcher.node
                function onReadyChanged() { watcher.tryApply(); }
            }

            property Connections volumeWatch: Connections {
                target: watcher.node?.audio ?? null
                function onVolumeChanged() {
                    var intended = root.targetVolumes[watcher.node.name];
                    if (intended === undefined)
                        return;
                    if (Math.round(target.volume * 100) !== Math.round(intended * 100))
                        target.volume = intended;
                }
            }

            Component.onCompleted: tryApply()
        }
    }

    function _track(node) {
        if (node.type !== PwNodeType.AudioOutStream || appNodes.includes(node))
            return;
        appNodes = appNodes.concat([node]);
        _watchers = _watchers.concat([watcherComponent.createObject(root, { node: node })]);
    }

    // Streams already there when the shell starts get no insert signal
    Component.onCompleted: {
        for (const node of Pipewire.nodes.values)
            _track(node);
    }

    Connections {
        target: Pipewire.nodes
        function onObjectInsertedPost(object, index) {
            root._track(object);
        }
        // By object, not by index: the model's indices shift as nodes come and go
        function onObjectRemovedPre(object, index) {
            if (!root.appNodes.includes(object))
                return;
            root.appNodes = root.appNodes.filter(node => node !== object);
            const gone = root._watchers.filter(watcher => watcher.node === object);
            root._watchers = root._watchers.filter(watcher => watcher.node !== object);
            for (const watcher of gone)
                watcher.destroy();
        }
    }
}
