pragma Singleton

import Quickshell
import QtQuick
import qs.singletons.hardware

Singleton {
    id: root

    // Ordered list of all hardware sources; panels iterate this for display
    readonly property var sources: [CpuSource, RamSource, DiskSource, CpuTempSource, GpuSource, GpuTempSource]

    // Convenience shortcuts for widgets
    readonly property real cpuUsage:  CpuSource.value
    readonly property real ramUsage:  RamSource.value
    readonly property real diskUsage: DiskSource.value
    readonly property int  cpuTemp:   CpuTempSource.value
    readonly property real gpuUsage:  GpuSource.value
    readonly property int  gpuTemp:   GpuTempSource.value

    function formatBytes(bytes) {
        if (bytes >= 1073741824) return (bytes / 1073741824).toFixed(1) + " GB"
        if (bytes >= 1048576)    return (bytes / 1048576).toFixed(0) + " MB"
        return bytes + " B"
    }

    function sourceForId(id) {
        for (var i = 0; i < sources.length; i++)
            if (sources[i].sourceId === id) return sources[i]
        return null
    }
}
