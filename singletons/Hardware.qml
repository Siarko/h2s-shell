pragma Singleton

import Quickshell
import QtQuick
import qs.singletons.hardware

Singleton {
    id: root

    // The three sources of every GPU, in card order
    property var _gpuSources: []

    // Ordered list of all hardware sources; panels iterate this for display
    readonly property var sources: [CpuSource, RamSource, DiskSource, CpuTempSource].concat(_gpuSources)

    readonly property var sourceIds: sources.map(source => source.sourceId)

    // Ids from before multi-GPU support, still in saved configs: they mean the primary
    // card (see GpuDevices), so those configs keep showing what they showed before
    readonly property var _legacyGpuIds: ({ "gpu": "gpu@", "vram": "vram@", "gpuTemp": "gpuTemp@" })

    // Convenience shortcuts for widgets
    readonly property real cpuUsage:  CpuSource.value
    readonly property real ramUsage:  RamSource.value
    readonly property real diskUsage: DiskSource.value
    readonly property int  cpuTemp:   CpuTempSource.value

    function sourceForId(id) {
        const legacyPrefix = _legacyGpuIds[id]
        if (legacyPrefix !== undefined) {
            if (!GpuDevices.primary)
                return null
            id = legacyPrefix + GpuDevices.primary.slot
        }
        for (var i = 0; i < sources.length; i++)
            if (sources[i].sourceId === id) return sources[i]
        return null
    }

    // The user's label for a configured source id, or "" for none. A label of only
    // whitespace is kept — it is how a row or capsule part is shown without a label.
    function customLabel(labels, id) {
        const label = labels?.[id]
        return typeof label === "string" ? label : ""
    }

    // Label to show for a configured source id: the user's, or the source's own
    function displayLabel(labels, id) {
        const custom = customLabel(labels, id)
        return custom !== "" ? custom : (sourceForId(id)?.label ?? id)
    }

    // Cards are found once, so this runs once, after GpuDevices has finished
    Instantiator {
        model: ScriptModel {
            values: GpuDevices.cards
        }
        delegate: GpuCard {
            required property var modelData
            card: modelData
        }
        onObjectAdded: (index, object) => {
            root._gpuSources = root._gpuSources.concat(object.sources)
                .sort((a, b) => a.card.number - b.card.number)
        }
        onObjectRemoved: (index, object) => {
            root._gpuSources = root._gpuSources.filter(source => !object.sources.includes(source))
        }
    }
}
